from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from app.api.routes import router
from app.models.database import init_db, get_conn

from dotenv import load_dotenv
load_dotenv()

app = FastAPI(title="CRM Call Logger + AI Pipeline")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

# Initialize PostgreSQL tables
init_db()

# PostgreSQL version of the column check (replaces SQLite PRAGMA)
with get_conn() as conn:
    cur = conn.cursor()
    cur.execute("""
        SELECT column_name FROM information_schema.columns
        WHERE table_name = 'call_logs' AND column_name = 'is_incoming'
    """)
    if not cur.fetchone():
        cur.execute("ALTER TABLE call_logs ADD COLUMN is_incoming INTEGER DEFAULT 1")

app.include_router(router)