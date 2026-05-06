# FORMAT 4: Student's Progress Report (Every 15 Days)

**Date:** 15th Mar 2026 → 29th Mar 2026

**Dept/Division:** AI/ML – CRM Call Agent | **Activity Completed:** AI Pipeline — LLM Integration, Call Analysis & Sentiment Detection

**Name of HOD/Supervisor:** Industry Supervisor

---

## Work Details:

## 🤖 Period 7 — AI Pipeline Integration (LLM Call Analysis)
**Date:** 15th Mar 2026 → 29th Mar 2026

---

### AI Pipeline Architecture
```
Call Ends (Android)
    ↓
POST /calls/ → Backend stores call metadata
    ↓
POST /analysis/analyze/{call_id}
    ↓
ai_service.py
    ├── Prepare prompt with call metadata + notes
    ├── Send to LLM (OpenAI GPT-4 / local Ollama)
    ├── Parse structured JSON response
    └── Store in ai_analysis table
    ↓
Flutter UI shows: Sentiment | Summary | Action Items | Keywords
```

---

### AI Analysis Output Schema
```json
{
  "sentiment": "positive",
  "confidence_score": 0.87,
  "summary": "Customer inquired about product pricing and showed interest in Q2 purchase.",
  "keywords": ["pricing", "Q2", "purchase", "discount"],
  "action_items": [
    "Send pricing proposal by Friday",
    "Schedule follow-up call in 2 weeks"
  ]
}
```

---

### Work Done
| # | Task | Status |
|---|------|--------|
| 1 | Designed AI prompt template for call analysis | ✅ Done |
| 2 | Integrated OpenAI API (GPT-4) in ai_service.py | ✅ Done |
| 3 | Implemented sentiment analysis (positive/neutral/negative) | ✅ Done |
| 4 | Built call summary generation pipeline | ✅ Done |
| 5 | Implemented keyword extraction from call notes | ✅ Done |
| 6 | Implemented action item detection | ✅ Done |
| 7 | Added confidence scoring for analysis results | ✅ Done |
| 8 | Built async analysis queue to avoid blocking API | ✅ Done |
| 9 | Displayed AI results in Flutter Call Detail Screen | ✅ Done |
| 10 | Tested with 20+ sample call scenarios | ✅ Done |

---

### Sample Prompt Template
```
You are a CRM AI assistant. Analyze the following sales call:
- Caller: {contact_name} ({phone_number})
- Duration: {duration} seconds
- Call Type: {call_type}
- Agent Notes: {notes}

Respond ONLY with a JSON object containing:
sentiment, confidence_score, summary, keywords[], action_items[]
```

---

### Challenges
- Handling LLM API rate limits → added exponential backoff retry
- Parsing inconsistent LLM JSON output → added strict Pydantic validation
- Cost management for OpenAI API → added caching for repeated analysis

---

### Deliverables
- ✅ ai_service.py with full LLM pipeline
- ✅ Sentiment analysis working (87%+ accuracy on test data)
- ✅ Action items and keywords extraction working
- ✅ Results displayed in Flutter UI


---
*Signature of Industry Supervisor / Proprietor with Company Stamp / Seal*
