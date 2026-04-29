import sqlite3

DB = "calls.db"


def get_conn():
    conn = sqlite3.connect(DB)
    conn.row_factory = sqlite3.Row
    return conn


def init_db():
    with get_conn() as conn:
        conn.execute("""
            CREATE TABLE IF NOT EXISTS call_logs (
                id          INTEGER PRIMARY KEY AUTOINCREMENT,
                number      TEXT,
                name        TEXT DEFAULT 'Unknown',
                duration    INTEGER DEFAULT 0,
                recording   TEXT,
                date        TEXT,
                time        TEXT,
                is_incoming INTEGER DEFAULT 1,
                created_at  TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        """)

        conn.execute("""
            CREATE TABLE IF NOT EXISTS call_analysis (
                id              INTEGER PRIMARY KEY AUTOINCREMENT,
                call_log_id     INTEGER NOT NULL REFERENCES call_logs(id) ON DELETE CASCADE,
                audio_path      TEXT,
                transcript      TEXT,
                agent_text      TEXT,
                customer_text   TEXT,
                summary         TEXT,
                issue_title     TEXT,
                sentiment       TEXT,
                sentiment_score REAL,
                status          TEXT DEFAULT 'pending',
                error_msg       TEXT,
                created_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        """)

        conn.execute("""
            CREATE TABLE IF NOT EXISTS customer_issues (
                id          INTEGER PRIMARY KEY AUTOINCREMENT,
                title       TEXT NOT NULL,
                description TEXT,
                embedding   TEXT,
                count       INTEGER DEFAULT 1,
                first_seen  TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                last_seen   TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        """)

        conn.execute("""
            CREATE TABLE IF NOT EXISTS issue_occurrences (
                id               INTEGER PRIMARY KEY AUTOINCREMENT,
                issue_id         INTEGER NOT NULL REFERENCES customer_issues(id),
                call_analysis_id INTEGER NOT NULL REFERENCES call_analysis(id),
                created_at       TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        """)
        conn.commit()