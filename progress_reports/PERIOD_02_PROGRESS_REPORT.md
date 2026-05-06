# FORMAT 4: Student's Progress Report (Every 15 Days)

**Date:** 30th Dec 2025 → 13th Jan 2026

**Dept/Division:** AI/ML – CRM Call Agent | **Activity Completed:** System Architecture & Tech Stack Design

**Name of HOD/Supervisor:** Industry Supervisor

---

## Work Details:

## 🏗️ Period 2 — System Architecture Design & Tech Stack Finalization
**Date:** 30th Dec 2025 → 13th Jan 2026

---

### Architecture Overview
```
┌─────────────────────────────────────────────────────┐
│                   Flutter UI (Dart)                  │
│         Call Logs | AI Insights | Dashboard          │
└─────────────────┬───────────────────────────────────┘
                  │ MethodChannel / REST API
┌─────────────────▼───────────────────────────────────┐
│          Android Native Layer (Kotlin)               │
│   CallReceiver | CallMonitorService | CallDatabase   │
└─────────────────┬───────────────────────────────────┘
                  │ HTTP REST
┌─────────────────▼───────────────────────────────────┐
│         Python Backend (FastAPI)                     │
│    AI Pipeline | Transcription | Sentiment Analysis  │
└─────────────────┬───────────────────────────────────┘
                  │ SQLAlchemy ORM
┌─────────────────▼───────────────────────────────────┐
│              PostgreSQL (crm_db)                     │
│       calls | contacts | ai_analysis | users         │
└─────────────────────────────────────────────────────┘
```

---

### Work Done
| # | Task | Status |
|---|------|--------|
| 1 | Designed full system architecture (4-layer diagram) | ✅ Done |
| 2 | Finalized tech stack: Flutter + Kotlin + Python FastAPI + PostgreSQL | ✅ Done |
| 3 | Created GitHub repository: AI_Call_Agent_App | ✅ Done |
| 4 | Set up project folder structure (android/, lib/, call_system_backend/) | ✅ Done |
| 5 | Initialized Flutter project with required packages | ✅ Done |
| 6 | Defined API contract between Android layer and Python backend | ✅ Done |
| 7 | Designed database ER diagram for crm_db | ✅ Done |
| 8 | Set up Git version control with .gitignore | ✅ Done |
| 9 | Installed and configured PostgreSQL 17 locally | ✅ Done |
| 10 | Created development, staging environment plan | ✅ Done |

---

### Tech Stack Finalized
| Component | Technology | Version |
|-----------|-----------|---------|
| Mobile UI | Flutter + Dart | 3.x |
| Android Native | Kotlin | 1.9.x |
| Backend | Python FastAPI | 0.100+ |
| Database | PostgreSQL | 17 |
| Local DB | SQLite (calls.db) | 3.x |
| AI/LLM | OpenAI / local LLM | GPT-4 / Ollama |
| Build Tool | Gradle | 8.x |

---

### Deliverables
- ✅ System architecture diagram
- ✅ ER diagram for crm_db
- ✅ GitHub repo initialized with proper structure
- ✅ pubspec.yaml with all dependencies defined


---
*Signature of Industry Supervisor / Proprietor with Company Stamp / Seal*
