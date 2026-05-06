"""
database.py — PostgreSQL version (Phase 3)
Replaces SQLite with PostgreSQL via psycopg2.
"""
import os
import psycopg2
import psycopg2.extras
from contextlib import contextmanager
from dotenv import load_dotenv

load_dotenv()

# ── Connection config ─────────────────────────────────────────────────────────
DATABASE_URL = os.getenv(
    "DATABASE_URL",
    "postgresql://crm_user:crm123@localhost:5433/crm_calls"
)


def _parse_url(url: str) -> dict:
    """Parse postgresql://user:pass@host:port/dbname into psycopg2 kwargs."""
    url = url.replace("postgresql://", "").replace("postgres://", "")
    user_pass, rest = url.split("@")
    user, password = user_pass.split(":")
    host_port, dbname = rest.split("/")
    if ":" in host_port:
        host, port = host_port.split(":")
    else:
        host, port = host_port, "5432"
    return dict(host=host, port=int(port), dbname=dbname, user=user, password=password)


_conn_kwargs = _parse_url(DATABASE_URL)


@contextmanager
def get_conn():
    """Context manager — yields a psycopg2 connection, auto-commits or rolls back."""
    conn = psycopg2.connect(
        **_conn_kwargs,
        cursor_factory=psycopg2.extras.RealDictCursor,
    )
    try:
        yield conn
        conn.commit()
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()


def init_db():
    """Create all tables if they don't exist."""
    with get_conn() as conn:
        cur = conn.cursor()

        cur.execute("""
            CREATE TABLE IF NOT EXISTS call_logs (
                id          SERIAL PRIMARY KEY,
                number      TEXT,
                name        TEXT DEFAULT 'Unknown',
                duration    INTEGER DEFAULT 0,
                recording   TEXT,
                date        TEXT,
                time        TEXT,
                is_incoming INTEGER DEFAULT 1,
                created_at  TIMESTAMP DEFAULT NOW()
            )
        """)

        cur.execute("""
            CREATE TABLE IF NOT EXISTS call_analysis (
                id              SERIAL PRIMARY KEY,
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
                created_at      TIMESTAMP DEFAULT NOW()
            )
        """)

        cur.execute("""
            CREATE TABLE IF NOT EXISTS customer_issues (
                id          SERIAL PRIMARY KEY,
                title       TEXT NOT NULL,
                description TEXT,
                embedding   TEXT,
                count       INTEGER DEFAULT 1,
                first_seen  TIMESTAMP DEFAULT NOW(),
                last_seen   TIMESTAMP DEFAULT NOW()
            )
        """)

        cur.execute("""
            CREATE TABLE IF NOT EXISTS issue_occurrences (
                id               SERIAL PRIMARY KEY,
                issue_id         INTEGER NOT NULL REFERENCES customer_issues(id),
                call_analysis_id INTEGER NOT NULL REFERENCES call_analysis(id),
                created_at       TIMESTAMP DEFAULT NOW()
            )
        """)

        print("✅ PostgreSQL tables ready")
