"""
tasks.py — Celery background tasks (root level)
"""
from celery_app import celery_app
from app.ai_pipeline import run_pipeline


@celery_app.task(bind=True, max_retries=2, name="tasks.process_call")
def process_call(self, call_log_id: int, audio_path: str):
    try:
        run_pipeline(call_log_id, audio_path)
    except Exception as exc:
        raise self.retry(exc=exc, countdown=10)