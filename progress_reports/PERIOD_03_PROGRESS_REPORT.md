# FORMAT 4: Student's Progress Report (Every 15 Days)

**Date:** 14th Jan 2026 → 28th Jan 2026

**Dept/Division:** AI/ML – CRM Call Agent | **Activity Completed:** Database Design, Schema Creation & PostgreSQL Setup

**Name of HOD/Supervisor:** Industry Supervisor

---

## Work Details:

## 🗄️ Period 3 — PostgreSQL Database Design & crm_db Setup
**Date:** 14th Jan 2026 → 28th Jan 2026

---

### Database: `crm_db` Schema Design

```sql
-- Core Tables Designed & Created:

CREATE TABLE contacts (
    id SERIAL PRIMARY KEY,
    phone_number VARCHAR(20) UNIQUE NOT NULL,
    name VARCHAR(100),
    company VARCHAR(100),
    email VARCHAR(100),
    created_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE calls (
    id SERIAL PRIMARY KEY,
    contact_id INTEGER REFERENCES contacts(id),
    call_type VARCHAR(10),       -- 'incoming' / 'outgoing' / 'missed'
    duration_seconds INTEGER,
    call_timestamp TIMESTAMP,
    notes TEXT,
    created_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE ai_analysis (
    id SERIAL PRIMARY KEY,
    call_id INTEGER REFERENCES calls(id),
    sentiment VARCHAR(20),       -- 'positive' / 'neutral' / 'negative'
    summary TEXT,
    keywords TEXT[],
    action_items TEXT[],
    confidence_score FLOAT,
    analyzed_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE users (
    id SERIAL PRIMARY KEY,
    username VARCHAR(50) UNIQUE NOT NULL,
    email VARCHAR(100) UNIQUE NOT NULL,
    role VARCHAR(20) DEFAULT 'agent',
    created_at TIMESTAMP DEFAULT NOW()
);
```

---

### Work Done
| # | Task | Status |
|---|------|--------|
| 1 | Installed PostgreSQL 17, configured psql CLI | ✅ Done |
| 2 | Created crm_db database | ✅ Done |
| 3 | Designed and created `contacts` table | ✅ Done |
| 4 | Designed and created `calls` table with foreign key | ✅ Done |
| 5 | Designed and created `ai_analysis` table | ✅ Done |
| 6 | Designed and created `users` table | ✅ Done |
| 7 | Created indexes on phone_number, call_timestamp | ✅ Done |
| 8 | Wrote seed data script for testing | ✅ Done |
| 9 | Implemented CallDatabase.kt (local SQLite) for offline caching | ✅ Done |
| 10 | Tested DB connectivity from Python backend | ✅ Done |

---

### Local SQLite (Android)
- `CallDatabase.kt` implemented using Android Room
- Schema mirrors PostgreSQL for easy sync
- Stores calls locally when offline → syncs to PostgreSQL when connected

---

### Challenges
- PostgreSQL version compatibility with Python psycopg2 (solved with psycopg2-binary)
- Designing sync strategy between SQLite and PostgreSQL

---

### Deliverables
- ✅ crm_db fully set up with 4 tables
- ✅ CallDatabase.kt (Android SQLite/Room)
- ✅ Database migration scripts
- ✅ Seed data for testing


---
*Signature of Industry Supervisor / Proprietor with Company Stamp / Seal*
