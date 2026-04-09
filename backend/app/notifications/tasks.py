"""Celery worker entrypoint for background tasks."""

from celery import Celery

celery_app = Celery("remote_control")
celery_app.conf.update(
    broker_url="redis://redis:6379/0",
    result_backend="redis://redis:6379/0",
)
