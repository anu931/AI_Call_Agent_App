from __future__ import annotations
import json
import logging
import os
import sqlite3
from datetime import datetime
from typing import Optional
import anthropic

log = logging.getLogger("ai_pipeline")

_whisper_model = None
_sentiment_pipeline = None
_embed_model = None

WHISPER_SIZE = os.getenv("WHISPER_SIZE", "small")
SIMILARITY_THRESHOLD = float(os.getenv("SIMILARITY_THRESHOLD", "0.80"))
ANTHROPIC_API_KEY = os.getenv("ANTHROPIC_API_KEY", "")
SENTIMENT_MODEL = "cardiffnlp/twitter-roberta-base-sentiment-latest"
EMBED_MODEL = "sentence-transformers/all-MiniLM-L6-v2"


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
        _sentiment_pipeline = hf_pipeline("sentiment-analysis", model=SENTIMENT_MODEL, top_k=None)
    return _sentiment_pipeline


def _get_embedder():
    global _embed_model
    if _embed_model is None:
        from sentence_transformers import SentenceTransformer
        _embed_model = SentenceTransformer(EMBED_MODEL)
    return _embed_model


def transcribe(audio_path: str) -> dict:
    return _get_whisper().transcribe(audio_path, word_timestamps=True, verbose=False)


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
            "start": round(seg["start"], 2),
            "end": round(seg["end"], 2),
            "speaker": "SPEAKER_00" if current_role == "AGENT" else "SPEAKER_01",
            "role": current_role,
            "text": seg["text"].strip(),
        })
        last_end = seg["end"]
    agent_text = " ".join(s["text"] for s in labeled if s["role"] == "AGENT")
    customer_text = " ".join(s["text"] for s in labeled if s["role"] == "CUSTOMER")
    return labeled, agent_text, customer_text


def extract_issue_and_summary(customer_text: str, full_text: str) -> dict:
    text = (customer_text or full_text)[:1500]
    if not ANTHROPIC_API_KEY:
        words = text.split()
        return {"issue_title": " ".join(words[:8]), "summary": text[:300]}
    try:
        client = anthropic.Anthropic(api_key=ANTHROPIC_API_KEY)
        msg = client.messages.create(
            model="claude-haiku-4-5-20251001",
            max_tokens=300,
            messages=[{"role": "user", "content": (
                "You are a CRM analyst. Respond with ONLY a JSON object, no markdown.\n"
                "Keys: \"issue_title\" (max 8 words), \"summary\" (2-3 sentences)\n\n"
                f"Customer said:\n{text}"
            )}],
        )
        raw = msg.content[0].text.strip().replace("```json", "").replace("```", "").strip()
        return json.loads(raw)
    except Exception as e:
        log.warning("Anthropic error: %s", e)
        words = text.split()
        return {"issue_title": " ".join(words[:8]), "summary": text[:300]}


def analyze_sentiment(text: str) -> tuple[str, float]:
    if not text.strip():
        return "neutral", 0.0
    try:
        results = _get_sentiment()(text[:512])[0]
        label_map = {"LABEL_0": "negative", "LABEL_1": "neutral", "LABEL_2": "positive"}
        score_map = {"negative": -1, "neutral": 0, "positive": 1}
        best = max(results, key=lambda x: x["score"])
        label = label_map.get(best["label"].upper(), best["label"].lower())
        return label, round(score_map.get(label, 0) * best["score"], 4)
    except Exception as e:
        log.warning("Sentiment error: %s", e)
        return "neutral", 0.0


def embed(text: str) -> list[float]:
    return _get_embedder().encode(text, normalize_embeddings=True).tolist()


def cosine_similarity(a: list[float], b: list[float]) -> float:
    import math
    dot = sum(x * y for x, y in zip(a, b))
    mag_a = math.sqrt(sum(x * x for x in a))
    mag_b = math.sqrt(sum(x * x for x in b))
    return dot / (mag_a * mag_b) if mag_a and mag_b else 0.0


def deduplicate_issue(conn, issue_title: str, summary: str) -> int:
    new_emb = embed(issue_title + " " + summary)
    rows = conn.execute("SELECT id, embedding FROM customer_issues").fetchall()
    best_id, best_sim = None, 0.0
    for row in rows:
        try:
            sim = cosine_similarity(new_emb, json.loads(row["embedding"]))
            if sim > best_sim:
                best_sim, best_id = sim, row["id"]
        except Exception:
            continue
    if best_sim >= SIMILARITY_THRESHOLD and best_id is not None:
        conn.execute(
            "UPDATE customer_issues SET count = count + 1, last_seen = ? WHERE id = ?",
            (datetime.utcnow().isoformat(), best_id),
        )
        return best_id
    cur = conn.execute(
        "INSERT INTO customer_issues (title, description, embedding) VALUES (?, ?, ?)",
        (issue_title, summary, json.dumps(new_emb)),
    )
    return cur.lastrowid


def run_pipeline(call_log_id: int, audio_path: str, db_path: str = "calls.db"):
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    analysis_id: Optional[int] = None
    try:
        cur = conn.execute(
            "INSERT INTO call_analysis (call_log_id, audio_path, status) VALUES (?, ?, 'processing')",
            (call_log_id, audio_path),
        )
        analysis_id = cur.lastrowid
        conn.commit()

        w_result = transcribe(audio_path)
        merged, agent_text, customer_text = label_speakers(w_result)
        full_text = " ".join(s["text"] for s in merged)

        llm_out = extract_issue_and_summary(customer_text or full_text, full_text)
        issue_title = llm_out.get("issue_title", "Unknown issue")
        summary = llm_out.get("summary", "")

        sentiment_label, sentiment_score = analyze_sentiment(customer_text or full_text)
        issue_id = deduplicate_issue(conn, issue_title, summary)

        conn.execute("""
            UPDATE call_analysis SET
                transcript=?, agent_text=?, customer_text=?,
                summary=?, issue_title=?, sentiment=?, sentiment_score=?,
                status='done', error_msg=NULL
            WHERE id=?
        """, (json.dumps(merged), agent_text, customer_text,
              summary, issue_title, sentiment_label, sentiment_score, analysis_id))
        conn.execute(
            "INSERT INTO issue_occurrences (issue_id, call_analysis_id) VALUES (?, ?)",
            (issue_id, analysis_id),
        )
        conn.commit()
        log.info("[%d] Done. Issue: '%s' | Sentiment: %s", call_log_id, issue_title, sentiment_label)

    except Exception as e:
        log.exception("[%d] Pipeline error: %s", call_log_id, e)
        if analysis_id:
            conn.execute(
                "UPDATE call_analysis SET status='error', error_msg=? WHERE id=?",
                (str(e), analysis_id),
            )
            conn.commit()
    finally:
        conn.close()