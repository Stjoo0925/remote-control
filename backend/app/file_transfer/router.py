# 파일 전송 API 라우터
#
# 전송 흐름:
#   1. POST /file-transfers         → 전송 메타데이터 등록 (transfer_id 발급)
#   2. PUT  /file-transfers/{id}/chunk → 청크 업로드 (Content-Range 헤더)
#   3. POST /file-transfers/{id}/complete → 전송 완료 확정
#   4. GET  /file-transfers/{id}/download → 수신측 다운로드
#
# 보안:
#   - 세션 참여자만 접근 가능
#   - 최대 파일 크기 512 MB
#   - 임시 파일은 서버 /tmp/rc_transfers/ 에 저장, 24시간 후 자동 삭제

import logging
import os
import uuid
from datetime import datetime, timezone
from pathlib import Path

import aiofiles
from fastapi import APIRouter, Depends, HTTPException, Request, UploadFile, File, Header, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from app.database import get_db
from app.auth.dependencies import CurrentUser
from app.auth.models import User
from app.sessions.models import Session
from app.file_transfer.models import (
    FileTransfer, TransferStatus, TransferResponse, InitTransferRequest
)

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/api/file-transfers", tags=["file-transfer"])

# 서버 임시 저장 디렉토리
TRANSFER_DIR = Path("/tmp/rc_transfers")
TRANSFER_DIR.mkdir(parents=True, exist_ok=True)

MAX_FILE_SIZE = 512 * 1024 * 1024  # 512 MB
CHUNK_SIZE    = 1 * 1024 * 1024    # 1 MB


def _assert_session_participant(session: Session, user: User) -> None:
    if str(session.controller_id) != str(user.id) and str(session.target_id) != str(user.id):
        if user.role.value != "admin":
            raise HTTPException(status_code=403, detail="세션 참여자만 파일을 전송할 수 있습니다.")


# ─────────────────────────────────────────────────────────────
# 전송 초기화
# ─────────────────────────────────────────────────────────────

@router.post("", response_model=TransferResponse, status_code=status.HTTP_201_CREATED)
async def init_transfer(
    body: InitTransferRequest,
    current_user: CurrentUser,
    db: AsyncSession = Depends(get_db),
):
    """파일 전송 메타데이터 등록. transfer_id를 발급받아 청크 업로드에 사용합니다."""
    if body.file_size > MAX_FILE_SIZE:
        raise HTTPException(status_code=413, detail=f"파일 크기 제한: {MAX_FILE_SIZE // 1024 // 1024} MB")
    if body.file_size <= 0:
        raise HTTPException(status_code=400, detail="파일 크기가 올바르지 않습니다.")

    # 세션 조회 + 참여자 검증
    result = await db.execute(select(Session).where(Session.id == body.session_id))
    session = result.scalar_one_or_none()
    if not session:
        raise HTTPException(status_code=404, detail="세션을 찾을 수 없습니다.")
    _assert_session_participant(session, current_user)

    transfer_id = uuid.uuid4()
    storage_path = str(TRANSFER_DIR / str(transfer_id))

    transfer = FileTransfer(
        id=transfer_id,
        session_id=session.id,
        sender_id=current_user.id,
        direction=body.direction,
        filename=body.filename,
        mime_type=body.mime_type,
        file_size=body.file_size,
        storage_path=storage_path,
    )
    db.add(transfer)

    logger.info(
        "파일 전송 초기화 — id=%s file=%s size=%d sender=%s",
        transfer_id, body.filename, body.file_size, current_user.username,
    )
    return transfer


# ─────────────────────────────────────────────────────────────
# 청크 업로드
# ─────────────────────────────────────────────────────────────

@router.put("/{transfer_id}/chunk", response_model=TransferResponse)
async def upload_chunk(
    transfer_id: str,
    request: Request,
    current_user: CurrentUser,
    content_range: str | None = Header(default=None),
    db: AsyncSession = Depends(get_db),
):
    """
    청크 업로드. Content-Range 헤더 필수.
    예: Content-Range: bytes 0-1048575/10485760
    """
    result = await db.execute(select(FileTransfer).where(FileTransfer.id == transfer_id))
    transfer = result.scalar_one_or_none()
    if not transfer:
        raise HTTPException(status_code=404, detail="전송 정보를 찾을 수 없습니다.")
    if str(transfer.sender_id) != str(current_user.id):
        raise HTTPException(status_code=403, detail="전송 발신자만 청크를 업로드할 수 있습니다.")
    if transfer.status not in (TransferStatus.pending, TransferStatus.in_progress):
        raise HTTPException(status_code=409, detail=f"전송 상태가 {transfer.status}입니다.")

    # Content-Range 파싱
    chunk_start, chunk_end = _parse_content_range(content_range, transfer.file_size)

    # 청크 데이터 수신
    chunk_data = await request.body()
    expected_len = chunk_end - chunk_start + 1
    if len(chunk_data) != expected_len:
        raise HTTPException(status_code=400, detail="청크 크기가 Content-Range와 일치하지 않습니다.")

    # 파일에 청크 쓰기 (랜덤 액세스)
    async with aiofiles.open(transfer.storage_path, "r+b" if chunk_start > 0 else "wb") as f:
        await f.seek(chunk_start)
        await f.write(chunk_data)

    transfer.transferred_bytes = chunk_end + 1
    transfer.status = TransferStatus.in_progress

    logger.debug(
        "청크 수신 — id=%s %d-%d/%d",
        transfer_id, chunk_start, chunk_end, transfer.file_size,
    )
    return transfer


# ─────────────────────────────────────────────────────────────
# 전송 완료
# ─────────────────────────────────────────────────────────────

@router.post("/{transfer_id}/complete", response_model=TransferResponse)
async def complete_transfer(
    transfer_id: str,
    current_user: CurrentUser,
    db: AsyncSession = Depends(get_db),
):
    """모든 청크 업로드 완료 후 호출. 수신측 다운로드 가능 상태로 전환."""
    result = await db.execute(select(FileTransfer).where(FileTransfer.id == transfer_id))
    transfer = result.scalar_one_or_none()
    if not transfer:
        raise HTTPException(status_code=404, detail="전송 정보를 찾을 수 없습니다.")
    if str(transfer.sender_id) != str(current_user.id):
        raise HTTPException(status_code=403, detail="전송 발신자만 완료 처리할 수 있습니다.")

    # 실제 파일 크기 검증
    actual_size = Path(transfer.storage_path).stat().st_size if Path(transfer.storage_path).exists() else 0
    if actual_size != transfer.file_size:
        transfer.status = TransferStatus.failed
        raise HTTPException(
            status_code=409,
            detail=f"파일 크기 불일치: 예상 {transfer.file_size}B, 실제 {actual_size}B",
        )

    transfer.status = TransferStatus.completed
    transfer.transferred_bytes = transfer.file_size
    transfer.completed_at = datetime.now(timezone.utc)

    logger.info("파일 전송 완료 — id=%s file=%s", transfer_id, transfer.filename)
    return transfer


# ─────────────────────────────────────────────────────────────
# 다운로드
# ─────────────────────────────────────────────────────────────

@router.get("/{transfer_id}/download")
async def download_file(
    transfer_id: str,
    current_user: CurrentUser,
    db: AsyncSession = Depends(get_db),
):
    """수신측이 파일을 다운로드합니다. 세션 참여자만 가능."""
    from fastapi.responses import FileResponse

    result = await db.execute(select(FileTransfer).where(FileTransfer.id == transfer_id))
    transfer = result.scalar_one_or_none()
    if not transfer:
        raise HTTPException(status_code=404, detail="전송 정보를 찾을 수 없습니다.")

    # 세션 참여자 검증
    sess_result = await db.execute(select(Session).where(Session.id == str(transfer.session_id)))
    session = sess_result.scalar_one_or_none()
    if session:
        _assert_session_participant(session, current_user)

    if transfer.status != TransferStatus.completed:
        raise HTTPException(status_code=409, detail="아직 전송이 완료되지 않았습니다.")
    if not transfer.storage_path or not Path(transfer.storage_path).exists():
        raise HTTPException(status_code=410, detail="파일이 만료되었습니다.")

    return FileResponse(
        path=transfer.storage_path,
        filename=transfer.filename,
        media_type=transfer.mime_type,
    )


# ─────────────────────────────────────────────────────────────
# 목록 조회
# ─────────────────────────────────────────────────────────────

@router.get("/session/{session_id}", response_model=list[TransferResponse])
async def list_session_transfers(
    session_id: str,
    current_user: CurrentUser,
    db: AsyncSession = Depends(get_db),
):
    """세션에 속한 파일 전송 목록"""
    sess_result = await db.execute(select(Session).where(Session.id == session_id))
    session = sess_result.scalar_one_or_none()
    if not session:
        raise HTTPException(status_code=404, detail="세션을 찾을 수 없습니다.")
    _assert_session_participant(session, current_user)

    result = await db.execute(
        select(FileTransfer)
        .where(FileTransfer.session_id == session_id)
        .order_by(FileTransfer.created_at.desc())
    )
    return result.scalars().all()


# ─────────────────────────────────────────────────────────────
# 내부 유틸리티
# ─────────────────────────────────────────────────────────────

def _parse_content_range(header: str | None, total: int) -> tuple[int, int]:
    """
    Content-Range: bytes 0-1048575/10485760 → (0, 1048575)
    """
    if not header:
        raise HTTPException(status_code=400, detail="Content-Range 헤더가 필요합니다.")
    try:
        _, range_total = header.split(" ", 1)
        range_part, _ = range_total.split("/")
        start_str, end_str = range_part.split("-")
        start, end = int(start_str), int(end_str)
    except (ValueError, AttributeError):
        raise HTTPException(status_code=400, detail="Content-Range 형식이 올바르지 않습니다.")

    if start > end or end >= total or start < 0:
        raise HTTPException(status_code=416, detail="Content-Range 범위가 올바르지 않습니다.")

    return start, end
