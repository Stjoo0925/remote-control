# 파일 전송 DB 모델 및 Pydantic 스키마
# 세션 내 양방향 파일 전송을 추적합니다.

import enum
import uuid
from datetime import datetime
from typing import Optional

from sqlalchemy import String, DateTime, Enum, ForeignKey, BigInteger
from sqlalchemy.orm import Mapped, mapped_column
from sqlalchemy.dialects.postgresql import UUID
from pydantic import BaseModel

from app.database import Base


class TransferDirection(str, enum.Enum):
    controller_to_target = "controller_to_target"
    target_to_controller = "target_to_controller"


class TransferStatus(str, enum.Enum):
    pending    = "pending"
    in_progress = "in_progress"
    completed  = "completed"
    failed     = "failed"
    cancelled  = "cancelled"


class FileTransfer(Base):
    __tablename__ = "file_transfers"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    session_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("sessions.id"), nullable=False)
    sender_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False)
    direction: Mapped[TransferDirection] = mapped_column(Enum(TransferDirection), nullable=False)
    filename: Mapped[str] = mapped_column(String(512), nullable=False)
    mime_type: Mapped[str] = mapped_column(String(256), nullable=False, default="application/octet-stream")
    file_size: Mapped[int] = mapped_column(BigInteger, nullable=False)   # bytes
    transferred_bytes: Mapped[int] = mapped_column(BigInteger, default=0)
    status: Mapped[TransferStatus] = mapped_column(Enum(TransferStatus), default=TransferStatus.pending)
    storage_path: Mapped[Optional[str]] = mapped_column(String(1024), nullable=True)  # 서버 임시 저장 경로
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=datetime.utcnow)
    completed_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), nullable=True)


# ── Pydantic ─────────────────────────────────────────────────

class InitTransferRequest(BaseModel):
    session_id: str
    filename: str
    mime_type: str = "application/octet-stream"
    file_size: int  # bytes
    direction: TransferDirection


class TransferResponse(BaseModel):
    id: uuid.UUID
    session_id: uuid.UUID
    sender_id: uuid.UUID
    direction: TransferDirection
    filename: str
    mime_type: str
    file_size: int
    transferred_bytes: int
    status: TransferStatus
    created_at: datetime
    completed_at: Optional[datetime] = None

    model_config = {"from_attributes": True}
