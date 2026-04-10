# 세션 API 라우터
#
# 누구나 (인증된 사용자) 세션을 시작할 수 있습니다.
# 두 가지 연결 방식을 모두 지원합니다:
#   1. 계정 기반: target_username으로 등록된 사용자를 지정
#   2. 페어링 기반: target_identifier만 지정 (계정 불필요, 페어링 코드로 연결)

import logging
import uuid
from fastapi import APIRouter, Depends, HTTPException, Request, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from app.database import get_db
from app.auth.dependencies import CurrentUser
from app.auth.models import User
from app.sessions.models import Session, SessionStatus, CreateSessionRequest, SessionResponse

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/api/sessions", tags=["sessions"])


def _parse_uuid(value: str) -> uuid.UUID:
    try:
        return uuid.UUID(value)
    except (TypeError, ValueError):
        raise HTTPException(status_code=400, detail="잘못된 세션 ID 형식입니다.")


@router.post("", response_model=SessionResponse, status_code=status.HTTP_201_CREATED)
async def create_session(
    body: CreateSessionRequest,
    request: Request,
    current_user: CurrentUser,
    db: AsyncSession = Depends(get_db),
):
    """
    세션 생성 — 인증된 사용자라면 누구나 호출 가능합니다.

    - target_username 지정 시: DB에 등록된 사용자를 대상으로 연결 (계정 기반)
    - target_identifier 지정 시: 장치명/코드만으로 연결 (페어링 기반, 계정 불필요)
    - 둘 다 없으면 400 오류
    """
    if not body.target_username and not body.target_identifier:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="target_username 또는 target_identifier 중 하나를 입력해 주세요.",
        )

    target_id = None
    target_identifier = body.target_identifier

    # ── 계정 기반 연결 ──────────────────────────────────────────
    if body.target_username:
        result = await db.execute(
            select(User).where(User.username == body.target_username, User.is_active == True)
        )
        target = result.scalar_one_or_none()
        if not target:
            raise HTTPException(status_code=404, detail="대상 사용자를 찾을 수 없습니다.")
        if str(target.id) == str(current_user.id):
            raise HTTPException(status_code=400, detail="자기 자신에게 세션을 요청할 수 없습니다.")
        target_id = target.id
        target_identifier = target.username

    # ── 페어링 기반 연결 ────────────────────────────────────────
    # target_identifier만 있는 경우 — DB 조회 불필요, 바로 세션 생성

    session = Session(
        controller_id=current_user.id,
        target_id=target_id,
        target_identifier=target_identifier,
        controller_ip=request.client.host if request.client else None,
    )
    db.add(session)
    await db.flush()

    logger.info(
        "세션 생성 — id=%s controller=%s target=%s",
        session.id, current_user.username, target_identifier,
    )
    return session


@router.get("", response_model=list[SessionResponse])
async def list_sessions(current_user: CurrentUser, db: AsyncSession = Depends(get_db)):
    """내가 참여한 세션 목록"""
    result = await db.execute(
        select(Session).where(
            (Session.controller_id == current_user.id) | (Session.target_id == current_user.id)
        ).order_by(Session.created_at.desc()).limit(50)
    )
    return result.scalars().all()


@router.get("/{session_id}", response_model=SessionResponse)
async def get_session(session_id: str, current_user: CurrentUser, db: AsyncSession = Depends(get_db)):
    parsed_session_id = _parse_uuid(session_id)
    result = await db.execute(select(Session).where(Session.id == parsed_session_id))
    session = result.scalar_one_or_none()
    if not session:
        raise HTTPException(status_code=404, detail="세션을 찾을 수 없습니다.")
    if (
        str(session.controller_id) != str(current_user.id)
        and str(session.target_id) != str(current_user.id)
        and current_user.role.value != "admin"
    ):
        raise HTTPException(status_code=403, detail="접근 권한이 없습니다.")
    return session


@router.delete("/{session_id}", status_code=status.HTTP_204_NO_CONTENT)
async def end_session(session_id: str, current_user: CurrentUser, db: AsyncSession = Depends(get_db)):
    """세션 종료"""
    from datetime import datetime, timezone
    parsed_session_id = _parse_uuid(session_id)
    result = await db.execute(select(Session).where(Session.id == parsed_session_id))
    session = result.scalar_one_or_none()
    if not session:
        raise HTTPException(status_code=404, detail="세션을 찾을 수 없습니다.")
    if (
        str(session.controller_id) != str(current_user.id)
        and current_user.role.value != "admin"
    ):
        raise HTTPException(status_code=403, detail="접근 권한이 없습니다.")
    session.status = SessionStatus.ended
    session.ended_at = datetime.now(timezone.utc)
    logger.info("세션 종료 — id=%s by=%s", session_id, current_user.username)
