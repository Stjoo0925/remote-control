# 세션 DB 모델 및 Pydantic 스키마

import enum
import uuid
from datetime import datetime
from typing import Optional

from sqlalchemy import String, DateTime, Enum, ForeignKey, JSON
from sqlalchemy.orm import Mapped, mapped_column
from sqlalchemy.dialects.postgresql import UUID
from pydantic import BaseModel

from app.database import Base
from app.auth.models import UserInfo


class SessionStatus(str, enum.Enum):
    pending = "pending"
    active = "active"
    ended = "ended"
    rejected = "rejected"


class Session(Base):
    __tablename__ = "sessions"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    controller_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False)

    # 계정 기반 연결: target_id 사용 (기존)
    # 디바이스/페어링 기반 연결: target_id=NULL, target_identifier에 장치명 저장
    target_id: Mapped[Optional[uuid.UUID]] = mapped_column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=True)
    target_identifier: Mapped[Optional[str]] = mapped_column(String(200), nullable=True)

    status: Mapped[SessionStatus] = mapped_column(Enum(SessionStatus), default=SessionStatus.pending)
    started_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), nullable=True)
    ended_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), nullable=True)
    controller_ip: Mapped[Optional[str]] = mapped_column(String(50), nullable=True)
    target_ip: Mapped[Optional[str]] = mapped_column(String(50), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=datetime.utcnow)


class SessionEvent(Base):
    __tablename__ = "session_events"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    session_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("sessions.id"), nullable=False)
    event_type: Mapped[str] = mapped_column(String(50), nullable=False)
    payload: Mapped[Optional[dict]] = mapped_column(JSON, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=datetime.utcnow)


# ── Pydantic 스키마 ─────────────────────────────────────

class CreateSessionRequest(BaseModel):
    # 계정 기반 연결 (기존 사용자)
    target_username: Optional[str] = None
    # 페어링/디바이스 기반 연결 (계정 불필요)
    target_identifier: Optional[str] = None


class SessionResponse(BaseModel):
    id: uuid.UUID
    status: SessionStatus
    controller_id: uuid.UUID
    target_id: Optional[uuid.UUID]
    target_identifier: Optional[str]
    started_at: Optional[datetime]
    created_at: datetime

    model_config = {"from_attributes": True}
