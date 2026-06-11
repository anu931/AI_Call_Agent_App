"""
routes.py — PostgreSQL + Celery version (Phase 3)
"""
import json
import shutil
from pathlib import Path
from datetime import datetime

from fastapi import APIRouter, HTTPException, UploadFile, File
from pydantic import BaseModel

from app.models.database import get_conn
from tasks import process_call

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
        cur = conn.cursor()
        cur.execute(
            """INSERT INTO call_logs (number, name, duration, recording, date, time)
               VALUES (%s, %s, %s, %s, %s, %s)""",
            (log.number, log.name, log.duration, log.recording, log.date, log.time),
        )
    return {"status": "saved"}


@router.get("/log")
def get_calls():
    with get_conn() as conn:
        cur = conn.cursor()
        cur.execute(
            "SELECT id, number, name, duration, recording, date, time FROM call_logs ORDER BY created_at DESC"
        )
        rows = cur.fetchall()
    return {"calls": [dict(r) for r in rows]}


@router.delete("/log/{call_id}")
def delete_call(call_id: int):
    with get_conn() as conn:
        cur = conn.cursor()
        cur.execute("DELETE FROM call_logs WHERE id = %s", (call_id,))
    return {"status": "deleted"}


@router.post("/upload")
async def upload_audio(
    file: UploadFile = File(...),
    number: str = "Unknown",
    duration: int = 0,
    is_incoming: int = 1,
):
    # Save the uploaded .m4a file first
    dest = UPLOAD_DIR / file.filename
    with dest.open("wb") as buf:
        shutil.copyfileobj(file.file, buf)

    # ── Convert .m4a → .wav ──────────────────────────────────────────────────
    wav_dest = dest.with_suffix(".wav")
    try:
        from pydub import AudioSegment
        audio = AudioSegment.from_file(str(dest), format="m4a")
        audio.export(str(wav_dest), format="wav")
        dest.unlink()          # delete the original .m4a
        final_path = wav_dest
    except Exception as e:
        # If conversion fails, fall back to original file
        final_path = dest
        print(f"⚠️  WAV conversion failed: {e} — keeping original")
    # ────────────────────────────────────────────────────────────────────────

    now = datetime.utcnow()

    with get_conn() as conn:
        cur = conn.cursor()
        cur.execute(
            """INSERT INTO call_logs (number, duration, recording, date, time, is_incoming)
               VALUES (%s, %s, %s, %s, %s, %s)
               RETURNING id""",
            (number, duration, str(final_path), now.strftime("%Y-%m-%d"), now.strftime("%H:%M:%S"), is_incoming),
        )
        call_log_id = cur.fetchone()["id"]

    task = process_call.delay(call_log_id, str(final_path))

    return {
        "call_log_id": call_log_id,
        "task_id": task.id,
        "status": "queued",
    }

@router.get("/task/{task_id}")
def get_task_status(task_id: str):
    from celery_app import celery_app
    task = celery_app.AsyncResult(task_id)
    return {
        "task_id": task_id,
        "status": task.status,
        "result": str(task.result) if task.failed() else None,
    }


@router.get("/analysis/{call_log_id}")
def get_analysis(call_log_id: int):
    with get_conn() as conn:
        cur = conn.cursor()
        cur.execute(
            "SELECT * FROM call_analysis WHERE call_log_id = %s ORDER BY id DESC LIMIT 1",
            (call_log_id,),
        )
        analysis = cur.fetchone()

        if not analysis:
            raise HTTPException(404, "Analysis not found or still processing")

        result = dict(analysis)

        if result.get("transcript"):
            try:
                result["transcript"] = json.loads(result["transcript"])
            except Exception:
                pass

        cur.execute("""
            SELECT ci.id, ci.title, ci.description, ci.count, ci.first_seen, ci.last_seen
            FROM issue_occurrences io
            JOIN customer_issues ci ON ci.id = io.issue_id
            WHERE io.call_analysis_id = %s
        """, (result["id"],))
        occ = cur.fetchone()
        result["issue"] = dict(occ) if occ else None

    return result


@router.get("/issues")
def list_issues():
    with get_conn() as conn:
        cur = conn.cursor()
        cur.execute(
            "SELECT id, title, description, count, first_seen, last_seen FROM customer_issues ORDER BY count DESC"
        )
        rows = cur.fetchall()
    return {"issues": [dict(r) for r in rows]}


@router.get("/stats")
def get_stats():
    """Single endpoint for dashboard — returns all stats in one call."""
    with get_conn() as conn:
        cur = conn.cursor()

        cur.execute("SELECT COUNT(*) as total FROM call_logs")
        total_calls = cur.fetchone()["total"]

        cur.execute("SELECT COUNT(*) as total FROM customer_issues")
        total_issues = cur.fetchone()["total"]

        cur.execute("SELECT COUNT(*) as total FROM call_analysis WHERE sentiment = 'positive'")
        positive = cur.fetchone()["total"]

        cur.execute("SELECT COUNT(*) as total FROM call_analysis WHERE sentiment = 'neutral'")
        neutral = cur.fetchone()["total"]

        cur.execute("SELECT COUNT(*) as total FROM call_analysis WHERE sentiment = 'negative'")
        negative = cur.fetchone()["total"]

        cur.execute(
            "SELECT id, title, description, count, first_seen, last_seen FROM customer_issues ORDER BY count DESC LIMIT 10"
        )
        top_issues = [dict(r) for r in cur.fetchall()]

    return {
        "total_calls":  total_calls,
        "total_issues": total_issues,
        "positive":     positive,
        "neutral":      neutral,
        "negative":     negative,
        "top_issues":   top_issues,
    }
    
@router.post("/upload-recording")
async def upload_recording_from_app(
    audio_file: UploadFile = File(...),
    contact_name: str = "Unknown",
    phone_number: str = "Unknown",
):
    """
    Called by Flutter app when user manually picks a recording file.
    Accepts any format (m4a, mp3, amr, ogg, aac, 3gp) → converts to WAV → Celery processes it.
    """
    import shutil
    from pydub import AudioSegment

    # Save original file
    original_path = UPLOAD_DIR / audio_file.filename
    with original_path.open("wb") as buf:
        shutil.copyfileobj(audio_file.file, buf)

    # Convert ANY format → WAV
    wav_path = original_path.with_suffix(".wav")
    try:
        AudioSegment.from_file(str(original_path)).set_frame_rate(16000).set_channels(1).export(str(wav_path), format="wav")
        original_path.unlink()  # delete original after conversion
        final_path = wav_path
    except Exception as e:
        final_path = original_path  # fallback: keep original
        print(f"⚠️ Conversion failed: {e}")

    now = datetime.utcnow()

    # Save to DB
    with get_conn() as conn:
        cur = conn.cursor()
        cur.execute(
            """INSERT INTO call_logs (number, name, duration, recording, date, time, is_incoming)
               VALUES (%s, %s, %s, %s, %s, %s, %s)
               RETURNING id""",
            (phone_number, contact_name, 0, str(final_path),
             now.strftime("%Y-%m-%d"), now.strftime("%H:%M:%S"), 1),
        )
        call_log_id = cur.fetchone()["id"]

    # Queue AI processing via Celery (same as your existing /upload route)
    task = process_call.delay(call_log_id, str(final_path))

    return {
        "call_log_id": call_log_id,
        "task_id": task.id,
        "status": "queued",
        "message": f"Recording received for {contact_name}, processing started"
    }