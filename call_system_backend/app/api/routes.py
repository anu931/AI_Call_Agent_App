import json
import os
import shutil
from pathlib import Path
from datetime import datetime

from fastapi import APIRouter, BackgroundTasks, HTTPException, UploadFile, File
from pydantic import BaseModel

from app.models.database import get_conn
from app.ai_pipeline import run_pipeline

router = APIRouter(prefix="/calls", tags=["Calls"])

UPLOAD_DIR = Path("uploads")
UPLOAD_DIR.mkdir(exist_ok=True)


class CallLog(BaseModel):
    number: str
    name: str = "Unknown"
    duration: int = 0
    recording: str = ""
    date: str
    time: str


@router.post("/log")
def save_call(log: CallLog):
    with get_conn() as conn:
        conn.execute(
            "INSERT INTO call_logs (number, name, duration, recording, date, time) VALUES (?,?,?,?,?,?)",
            (log.number, log.name, log.duration, log.recording, log.date, log.time),
        )
    return {"status": "saved"}


@router.get("/log")
def get_calls():
    with get_conn() as conn:
        rows = conn.execute(
            "SELECT id, number, name, duration, recording, date, time FROM call_logs ORDER BY created_at DESC"
        ).fetchall()
    return {"calls": [dict(r) for r in rows]}


@router.delete("/log/{call_id}")
def delete_call(call_id: int):
    with get_conn() as conn:
        conn.execute("DELETE FROM call_logs WHERE id=?", (call_id,))
    return {"status": "deleted"}


@router.post("/upload")
async def upload_audio(
    background_tasks: BackgroundTasks,
    file: UploadFile = File(...),
    number: str = "Unknown",
    duration: int = 0,
    is_incoming: int = 1,
):
    dest = UPLOAD_DIR / file.filename
    with dest.open("wb") as buf:
        shutil.copyfileobj(file.file, buf)

    now = datetime.utcnow()

    with get_conn() as conn:
        cur = conn.execute(
            "INSERT INTO call_logs (number, duration, recording, date, time, is_incoming) VALUES (?,?,?,?,?,?)",
            (number, duration, str(dest), now.strftime("%Y-%m-%d"), now.strftime("%H:%M:%S"), is_incoming),
        )
        call_log_id = cur.lastrowid

    background_tasks.add_task(run_pipeline, call_log_id, str(dest))

    return {"call_log_id": call_log_id, "status": "queued"}


@router.get("/analysis/{call_log_id}")
def get_analysis(call_log_id: int):
    with get_conn() as conn:
        analysis = conn.execute(
            "SELECT * FROM call_analysis WHERE call_log_id = ? ORDER BY id DESC LIMIT 1",
            (call_log_id,),
        ).fetchone()

        if not analysis:
            raise HTTPException(404, "Analysis not found or still pending")

        result = dict(analysis)

        if result.get("transcript"):
            try:
                result["transcript"] = json.loads(result["transcript"])
            except Exception:
                pass

        occ = conn.execute("""
            SELECT ci.id, ci.title, ci.description, ci.count, ci.first_seen, ci.last_seen
            FROM issue_occurrences io
            JOIN customer_issues ci ON ci.id = io.issue_id
            WHERE io.call_analysis_id = ?
        """, (result["id"],)).fetchone()

        result["issue"] = dict(occ) if occ else None

    return result


@router.get("/issues")
def list_issues():
    with get_conn() as conn:
        rows = conn.execute(
            "SELECT id, title, description, count, first_seen, last_seen FROM customer_issues ORDER BY count DESC"
        ).fetchall()
    return {"issues": [dict(r) for r in rows]}