import os
import ssl
from celery import Celery
from dotenv import load_dotenv

load_dotenv(dotenv_path=os.path.join(os.path.dirname(__file__), '.env'))

REDIS_URL = os.getenv("REDIS_URL", "redis://localhost:6379/0")

# Use the actual ssl constant, not the string
SSL_OPTS = {"ssl_cert_reqs": ssl.CERT_NONE} if REDIS_URL.startswith("rediss://") else {}

print(f"Celery using Redis: {REDIS_URL[:30]}...")

celery_app = Celery(
    "crm_tasks",
    broker=REDIS_URL,
    backend=REDIS_URL,
    include=["tasks"],
)

celery_app.conf.update(
    task_serializer="json",
    result_serializer="json",
    accept_content=["json"],
    timezone="UTC",
    broker_connection_retry_on_startup=True,
    broker_use_ssl=SSL_OPTS,
    redis_backend_use_ssl=SSL_OPTS,
)