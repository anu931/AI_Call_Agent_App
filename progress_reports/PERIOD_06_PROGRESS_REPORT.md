# FORMAT 4: Student's Progress Report (Every 15 Days)

**Date:** 28th Feb 2026 → 14th Mar 2026

**Dept/Division:** AI/ML – CRM Call Agent | **Activity Completed:** Python Backend — FastAPI REST API Development

**Name of HOD/Supervisor:** Industry Supervisor

---

## Work Details:

## ⚙️ Period 6 — Python Backend API Development (FastAPI)
**Date:** 28th Feb 2026 → 14th Mar 2026

---

### Backend Structure (`call_system_backend/`)
```
call_system_backend/
├── main.py              # FastAPI app entry point
├── models.py            # SQLAlchemy ORM models
├── schemas.py           # Pydantic request/response schemas
├── database.py          # PostgreSQL connection (crm_db)
├── routers/
│   ├── calls.py         # Call CRUD endpoints
│   ├── contacts.py      # Contact management endpoints
│   ├── analysis.py      # AI analysis endpoints
│   └── auth.py          # User authentication
├── services/
│   ├── ai_service.py    # LLM integration logic
│   └── sync_service.py  # SQLite → PostgreSQL sync
└── requirements.txt
```

---

### API Endpoints Developed
| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `/calls/` | Log a new call |
| GET | `/calls/` | Get all calls (paginated) |
| GET | `/calls/{id}` | Get specific call |
| GET | `/calls/contact/{phone}` | Get calls by contact |
| POST | `/contacts/` | Create contact |
| GET | `/contacts/` | List all contacts |
| POST | `/analysis/analyze/{call_id}` | Trigger AI analysis |
| GET | `/analysis/{call_id}` | Get analysis result |
| POST | `/auth/token` | Login & get JWT token |

---

### Work Done
| # | Task | Status |
|---|------|--------|
| 1 | Set up FastAPI project with folder structure | ✅ Done |
| 2 | Connected PostgreSQL using SQLAlchemy + psycopg2 | ✅ Done |
| 3 | Implemented all SQLAlchemy ORM models (calls, contacts, analysis) | ✅ Done |
| 4 | Built Pydantic schemas for request/response validation | ✅ Done |
| 5 | Implemented `/calls/` CRUD endpoints | ✅ Done |
| 6 | Implemented `/contacts/` endpoints | ✅ Done |
| 7 | Added JWT authentication with python-jose | ✅ Done |
| 8 | Set up CORS middleware for Flutter app access | ✅ Done |
| 9 | Added request logging and error handling middleware | ✅ Done |
| 10 | Tested all endpoints using Postman / FastAPI Swagger UI | ✅ Done |

---

### Challenges
- CORS configuration for Android emulator (uses 10.0.2.2 instead of localhost)
- JWT token refresh strategy for long sessions

---

### Deliverables
- ✅ FastAPI backend running on port 8000
- ✅ 9 REST API endpoints fully implemented
- ✅ JWT authentication working
- ✅ Swagger UI documentation at `/docs`
- ✅ All endpoints tested with Postman


---
*Signature of Industry Supervisor / Proprietor with Company Stamp / Seal*
