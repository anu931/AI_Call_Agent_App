import os
import psycopg2
import psycopg2.extras
from contextlib import contextmanager
from dotenv import load_dotenv

load_dotenv()

DATABASE_URL = os.getenv("DATABASE_URL")
if not DATABASE_URL:
    raise RuntimeError("DATABASE_URL is not set. Check your .env or Railway variables.")


def _parse_url(url: str) -> dict:
    url = url.replace("postgresql://", "").replace("postgres://", "")
    user_pass, rest = url.split("@", 1)
    user, password   = user_pass.split(":", 1)
    host_port, dbname = rest.split("/", 1)
    host, port = (host_port.split(":") + ["5432"])[:2]
    return dict(host=host, port=int(port), dbname=dbname,
                user=user, password=password)


_conn_kwargs = _parse_url(DATABASE_URL)


@contextmanager
def get_conn():
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
                call_log_id     INTEGER NOT NULL
                                    REFERENCES call_logs(id) ON DELETE CASCADE,
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
                issue_id         INTEGER NOT NULL
                                     REFERENCES customer_issues(id),
                call_analysis_id INTEGER NOT NULL
                                     REFERENCES call_analysis(id),
                created_at       TIMESTAMP DEFAULT NOW()
            )
        """)

        print("PostgreSQL tables ready")