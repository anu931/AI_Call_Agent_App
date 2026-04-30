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

init_db()

with get_conn() as conn:
    cols = [r[1] for r in conn.execute("PRAGMA table_info(call_logs)").fetchall()]
    if "is_incoming" not in cols:
        conn.execute("ALTER TABLE call_logs ADD COLUMN is_incoming INTEGER DEFAULT 1")

app.include_router(router)