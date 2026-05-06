"""
celery_app.py — Celery configuration
"""
import os
from celery import Celery
from dotenv import load_dotenv

load_dotenv()

REDIS_URL = os.getenv("REDIS_URL", "redis://localhost:6379/0")

celery_app = Celery(
    "crm_pipeline",
    broker=REDIS_URL,
    backend=REDIS_URL,
)

celery_app.conf.update(
    imports=("tasks",),             # tasks.py at root level, not app.tasks
    task_serializer="json",
    accept_content=["json"],
    result_serializer="json",
    timezone="UTC",
    enable_utc=True,
    task_track_started=True,
    worker_prefetch_multiplier=1,
    task_acks_late=True,
)