from __future__ import annotations
import json
import logging
import os
from datetime import datetime
from typing import Optional

import torch
from transformers import AutoModelForCausalLM, AutoTokenizer, BitsAndBytesConfig
from peft import PeftModel

# ── Keyword-based issue extraction for any language ──────────────────────────
_ISSUE_KEYWORDS = {
    "billing":   ["bill", "charge", "payment", "refund", "money", "paid", "amount",
                  "पैसे", "बिल", "चार्ज", "रिफंड", "भुगतान", "पेमेंट",
                  "पैसा", "कटे", "कट", "दोबारा", "वापस"],
    "network":   ["internet", "connection", "network", "signal", "slow", "drop",
                  "नेटवर्क", "कनेक्शन", "इंटरनेट", "सिग्नल", "स्पीड"],
    "account":   ["account", "login", "password", "access", "blocked",
                  "अकाउंट", "पासवर्ड", "लॉगिन", "ब्लॉक", "अकाउन्ट"],
    "delivery":  ["deliver", "order", "package", "ship", "received",
                  "डिलीवरी", "ऑर्डर", "पैकेज", "मिला", "नहीं मिला"],
    "technical": ["error", "crash", "bug", "not working", "issue", "problem",
                  "एरर", "काम नहीं", "समस्या", "खराब", "नहीं चल"],
}

def detect_issue_category(text: str) -> str:
    text_lower = text.lower()
    for category, keywords in _ISSUE_KEYWORDS.items():
        if any(kw in text_lower for kw in keywords):
            return category
    return "general"
# ─────────────────────────────────────────────────────────────────────────────
# Logging
# ─────────────────────────────────────────────────────────────────────────────
log = logging.getLogger("ai_pipeline")

# ─────────────────────────────────────────────────────────────────────────────
# Config
# ─────────────────────────────────────────────────────────────────────────────
WHISPER_SIZE = os.getenv("WHISPER_SIZE", "base")  
SIMILARITY_THRESHOLD = float(os.getenv("SIMILARITY_THRESHOLD", "0.80"))
SENTIMENT_MODEL      = "cardiffnlp/twitter-roberta-base-sentiment-latest"
EMBED_MODEL          = "sentence-transformers/all-MiniLM-L6-v2"
FINETUNED_MODEL_PATH = os.getenv("FINETUNED_MODEL_PATH", "./call_center_lora_adapter")
CHROMA_DIR           = os.getenv("CHROMA_DIR", "./chroma_db")

DEVICE = "cuda" if torch.cuda.is_available() else "cpu"
log.info("Running on device: %s", DEVICE)

# ─────────────────────────────────────────────────────────────────────────────
# Lazy-loaded singletons
# ─────────────────────────────────────────────────────────────────────────────
_whisper_model       = None
_sentiment_pipeline  = None
_embed_model         = None
_finetuned_model     = None
_finetuned_tokenizer = None
_chroma_collection   = None


def _get_whisper():
    global _whisper_model
    if _whisper_model is None:
        import whisper
        log.info("Loading Whisper '%s'...", WHISPER_SIZE)
        _whisper_model = whisper.load_model(WHISPER_SIZE)
    return _whisper_model


def _get_sentiment():
    global _sentiment_pipeline
    if _sentiment_pipeline is None:
        from transformers import pipeline as hf_pipeline
        _sentiment_pipeline = hf_pipeline(
            "sentiment-analysis", model=SENTIMENT_MODEL, top_k=None
        )
    return _sentiment_pipeline


def _get_embedder():
    global _embed_model
    if _embed_model is None:
        from sentence_transformers import SentenceTransformer
        _embed_model = SentenceTransformer(EMBED_MODEL)
    return _embed_model


def _get_chroma():
    """Return ChromaDB collection — persistent, stored in ./chroma_db/"""
    global _chroma_collection
    if _chroma_collection is None:
        import chromadb
        client = chromadb.PersistentClient(path=CHROMA_DIR)
        _chroma_collection = client.get_or_create_collection(
            name="customer_issues",
            metadata={"hnsw:space": "cosine"},
        )
        log.info("ChromaDB collection ready at %s", CHROMA_DIR)
    return _chroma_collection


def _get_finetuned_model():
    global _finetuned_model, _finetuned_tokenizer
    if _finetuned_model is None:
        adapter_config_path = os.path.join(FINETUNED_MODEL_PATH, "adapter_config.json")
        if not os.path.exists(adapter_config_path):
            raise FileNotFoundError(
                f"adapter_config.json not found in {FINETUNED_MODEL_PATH}."
            )
        adapter_cfg = json.load(open(adapter_config_path))
        base_id = adapter_cfg.get("base_model_name_or_path", "facebook/opt-125m")
        log.info("Loading base model '%s' on %s...", base_id, DEVICE)

        if DEVICE == "cuda":
            bnb = BitsAndBytesConfig(
                load_in_4bit=True,
                bnb_4bit_use_double_quant=True,
                bnb_4bit_quant_type="nf4",
                bnb_4bit_compute_dtype=torch.float16,
            )
            base = AutoModelForCausalLM.from_pretrained(
                base_id, quantization_config=bnb, device_map="auto",
                trust_remote_code=True, torch_dtype=torch.float16,
            )
        else:
            base = AutoModelForCausalLM.from_pretrained(
                base_id, torch_dtype=torch.float32, trust_remote_code=True,
            )

        _finetuned_model = PeftModel.from_pretrained(base, FINETUNED_MODEL_PATH)
        _finetuned_model.eval()
        _finetuned_tokenizer = AutoTokenizer.from_pretrained(
            FINETUNED_MODEL_PATH, trust_remote_code=True
        )
        if _finetuned_tokenizer.pad_token is None:
            _finetuned_tokenizer.pad_token = _finetuned_tokenizer.eos_token
        log.info("Fine-tuned model loaded on %s", DEVICE)
    return _finetuned_model, _finetuned_tokenizer


# ─────────────────────────────────────────────────────────────────────────────
# Transcription
# ─────────────────────────────────────────────────────────────────────────────
def transcribe(audio_path: str) -> dict:
    return _get_whisper().transcribe(audio_path, word_timestamps=True, verbose=False)


# ─────────────────────────────────────────────────────────────────────────────
# Speaker labeling
# ─────────────────────────────────────────────────────────────────────────────
def label_speakers(whisper_result: dict) -> tuple[list[dict], str, str]:
    segments = whisper_result.get("segments", [])
    if not segments:
        return [], "", ""

    labeled = []
    current_role = "AGENT"
    last_end = 0.0

    for seg in segments:
        start = seg["start"]
        if start > 30 and (start - last_end) > 1.5:
            current_role = "CUSTOMER" if current_role == "AGENT" else "AGENT"
        labeled.append({
            "start":   round(seg["start"], 2),
            "end":     round(seg["end"], 2),
            "speaker": "SPEAKER_00" if current_role == "AGENT" else "SPEAKER_01",
            "role":    current_role,
            "text":    seg["text"].strip(),
        })
        last_end = seg["end"]

    agent_text    = " ".join(s["text"] for s in labeled if s["role"] == "AGENT")
    customer_text = " ".join(s["text"] for s in labeled if s["role"] == "CUSTOMER")
    return labeled, agent_text, customer_text


# ─────────────────────────────────────────────────────────────────────────────
# Issue extraction via fine-tuned model
# ─────────────────────────────────────────────────────────────────────────────
_INSTRUCTION = (
    "You are a CRM analyst. Given a customer support call transcript, "
    "extract the issue, write a summary, and analyze sentiment. "
    "Respond ONLY with a JSON object with keys: "
    "issue_title (max 8 words), summary (2-3 sentences), "
    "sentiment (negative/neutral/positive), sentiment_score (-1.0 to 1.0)."
)


def extract_issue_and_summary(customer_text: str, full_text: str) -> dict:
    text = (customer_text or full_text)[:1000]

    def _smart_fallback():
        category = detect_issue_category(text)
        title_map = {
            "billing":   "Billing / Payment Issue",
            "network":   "Network / Connection Problem",
            "account":   "Account Access Issue",
            "delivery":  "Delivery / Order Issue",
            "technical": "Technical / App Issue",
            "general":   "General Customer Complaint",
        }
        issue_title = title_map.get(category, "Customer Support Issue")
        summary = text[:300] if text else "No summary available"
        return {
            "issue_title": issue_title,
            "summary": summary,
            "sentiment": "neutral",
            "sentiment_score": 0.0,
        }

    # Non-ASCII check — skip LLM for Hindi/Marathi
    non_ascii = sum(1 for c in text if ord(c) > 127)
    if non_ascii > len(text) * 0.3:
        log.info("Non-English text detected — using keyword-based extraction")
        return _smart_fallback()

    try:
        model, tokenizer = _get_finetuned_model()
        prompt = (
            f"### Instruction:\n{_INSTRUCTION}\n\n"
            f"### Input:\n{text}\n\n"
            f"### Response:\n"
        )
        inputs = tokenizer(prompt, return_tensors="pt").to(DEVICE)
        with torch.no_grad():
            out = model.generate(
                **inputs, max_new_tokens=200, temperature=0.1,
                do_sample=True, pad_token_id=tokenizer.eos_token_id,
            )
        decoded = tokenizer.decode(out[0], skip_special_tokens=True)
        raw = decoded.split("### Response:")[-1].strip()
        raw = raw.replace("```json", "").replace("```", "").strip()
        j_start = raw.find("{")
        j_end   = raw.rfind("}") + 1
        if j_start == -1 or j_end <= j_start:
            return _smart_fallback()
        result = json.loads(raw[j_start:j_end])
        required = {"issue_title", "summary", "sentiment", "sentiment_score"}
        if not required.issubset(result.keys()):
            return _smart_fallback()
        return result
    except FileNotFoundError as e:
        log.warning("Fine-tuned model not found: %s", e)
        return _smart_fallback()
    except Exception as e:
        log.warning("Fine-tuned model error: %s", e)
        return _smart_fallback()
# ─────────────────────────────────────────────────────────────────────────────
# Sentiment analysis
# ─────────────────────────────────────────────────────────────────────────────
def analyze_sentiment(text: str) -> tuple[str, float]:
    if not text.strip():
        return "neutral", 0.0
    try:
        results   = _get_sentiment()(text[:512])[0]
        label_map = {"LABEL_0": "negative", "LABEL_1": "neutral", "LABEL_2": "positive"}
        score_map = {"negative": -1, "neutral": 0, "positive": 1}
        best  = max(results, key=lambda x: x["score"])
        label = label_map.get(best["label"].upper(), best["label"].lower())
        return label, round(score_map.get(label, 0) * best["score"], 4)
    except Exception as e:
        log.warning("Sentiment error: %s", e)
        return "neutral", 0.0


# ─────────────────────────────────────────────────────────────────────────────
# Embeddings
# ─────────────────────────────────────────────────────────────────────────────
def embed(text: str) -> list[float]:
    return _get_embedder().encode(text, normalize_embeddings=True).tolist()


# ─────────────────────────────────────────────────────────────────────────────
# ChromaDB deduplication (replaces manual cosine similarity)
# ─────────────────────────────────────────────────────────────────────────────
def deduplicate_issue(conn, issue_title: str, summary: str) -> int:
    """
    Uses ChromaDB to find duplicate issues via vector similarity.
    If a similar issue exists (score >= threshold), increments its count.
    Otherwise, inserts a new issue into both PostgreSQL and ChromaDB.
    """
    collection = _get_chroma()
    query_text = issue_title + " " + summary
    embedding  = embed(query_text)

    # Check if any issues exist in ChromaDB first
    existing_count = collection.count()
    best_pg_id = None

    if existing_count > 0:
        results = collection.query(
            query_embeddings=[embedding],
            n_results=1,
            include=["distances", "metadatas"],
        )
        distances  = results["distances"][0]
        metadatas  = results["metadatas"][0]

        if distances and metadatas:
            # ChromaDB cosine distance: 0 = identical, 1 = opposite
            # Convert to similarity: similarity = 1 - distance
            similarity = 1.0 - distances[0]
            if similarity >= SIMILARITY_THRESHOLD:
                best_pg_id = int(metadatas[0]["pg_id"])
                log.info(
                    "Duplicate issue found (similarity=%.2f): pg_id=%d",
                    similarity, best_pg_id,
                )

    if best_pg_id is not None:
        # Increment count in PostgreSQL
        cur = conn.cursor()
        cur.execute(
            "UPDATE customer_issues SET count = count + 1, last_seen = %s WHERE id = %s",
            (datetime.utcnow().isoformat(), best_pg_id),
        )
        return best_pg_id

    # New issue — insert into PostgreSQL first to get ID
    cur = conn.cursor()
    cur.execute(
        "INSERT INTO customer_issues (title, description, embedding) VALUES (%s, %s, %s) RETURNING id",
        (issue_title, summary, json.dumps(embedding)),
    )
    new_pg_id = cur.fetchone()["id"]

    # Then add to ChromaDB with pg_id as metadata
    collection.add(
        ids=[str(new_pg_id)],
        embeddings=[embedding],
        documents=[query_text],
        metadatas=[{"pg_id": new_pg_id, "title": issue_title}],
    )
    log.info("New issue stored: pg_id=%d title='%s'", new_pg_id, issue_title)
    return new_pg_id


# ─────────────────────────────────────────────────────────────────────────────
# Main pipeline
# ─────────────────────────────────────────────────────────────────────────────
def run_pipeline(call_log_id: int, audio_path: str, db_path: str = "calls.db"):
    import psycopg2
    import psycopg2.extras
    from dotenv import load_dotenv
    load_dotenv()

    DATABASE_URL = os.getenv("DATABASE_URL", "postgresql://crm_user:crm123@localhost:5433/crm_calls")

    def parse_url(url):
        url = url.replace("postgresql://", "").replace("postgres://", "")
        user_pass, rest = url.split("@")
        user, password = user_pass.split(":")
        host_port, dbname = rest.split("/")
        host, port = (host_port.split(":") + ["5432"])[:2]
        return dict(host=host, port=int(port), dbname=dbname, user=user, password=password)

    conn = psycopg2.connect(**parse_url(DATABASE_URL), cursor_factory=psycopg2.extras.RealDictCursor)
    analysis_id: Optional[int] = None

    try:
        cur = conn.cursor()
        cur.execute(
            "INSERT INTO call_analysis (call_log_id, audio_path, status) VALUES (%s, %s, 'processing') RETURNING id",
            (call_log_id, audio_path),
        )
        analysis_id = cur.fetchone()["id"]
        conn.commit()

        # 1. Transcribe
        w_result = transcribe(audio_path)
        merged, agent_text, customer_text = label_speakers(w_result)
        full_text = " ".join(s["text"] for s in merged)

        # 2. Extract issue + summary via fine-tuned model
        llm_out     = extract_issue_and_summary(customer_text or full_text, full_text)
        issue_title = llm_out.get("issue_title", "Unknown issue")
        summary     = llm_out.get("summary", "")

        # 3. Sentiment
        sentiment_label, sentiment_score = analyze_sentiment(customer_text or full_text)

        # 4. Deduplicate via ChromaDB
        issue_id = deduplicate_issue(conn, issue_title, summary)

        # 5. Save results
        cur = conn.cursor()
        cur.execute("""
            UPDATE call_analysis SET
                transcript=%s, agent_text=%s, customer_text=%s,
                summary=%s, issue_title=%s, sentiment=%s, sentiment_score=%s,
                status='done', error_msg=NULL
            WHERE id=%s
        """, (
            json.dumps(merged), agent_text, customer_text,
            summary, issue_title, sentiment_label, sentiment_score,
            analysis_id,
        ))
        cur.execute(
            "INSERT INTO issue_occurrences (issue_id, call_analysis_id) VALUES (%s, %s)",
            (issue_id, analysis_id),
        )
        conn.commit()
        log.info("[%d] Done. Issue: '%s' | Sentiment: %s", call_log_id, issue_title, sentiment_label)

    except Exception as e:
        log.exception("[%d] Pipeline error: %s", call_log_id, e)
        if analysis_id:
            cur = conn.cursor()
            cur.execute(
                "UPDATE call_analysis SET status='error', error_msg=%s WHERE id=%s",
                (str(e), analysis_id),
            )
            conn.commit()
    finally:
        conn.close()