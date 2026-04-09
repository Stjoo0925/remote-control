# 세션 API 라우터

import logging
from fastapi import APIRouter, Depends, HTTPException, Request, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from app.database import get_db
from app.auth.dependencies import CurrentUser, SupportOrAbove
from app.auth.models import User
from app.sessions.models import Session, SessionStatus, CreateSessionRequest, SessionResponse

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/api/sessions", tags=["sessions"])


@router.post("", response_model=SessionResponse, status_code=status.HTTP_201_CREATED)
async def create_session(
    body: CreateSessionRequest,
    request: Request,
    current_user: SupportOrAbove,
    db: AsyncSession = Depends(get_db),
):
    """세션 생성 요청 (ROLE_SUPPORT 이상)"""
    # 대상 사용자 조회
    result = await db.execute(select(User).where(User.username == body.target_username, User.is_active == True))
    target = result.scalar_one_or_none()
    if not target:
        raise HTTPException(status_code=404, detail="대상 사용자를 찾을 수 없습니다.")

    if str(target.id) == str(current_user.id):
        raise HTTPException(status_code=400, detail="자기 자신에게 세션을 요청할 수 없습니다.")

    session = Session(
        controller_id=current_user.id,
        target_id=target.id,
        controller_ip=request.client.host if request.client else None,
    )
    db.add(session)
    await db.flush()

    logger.info("세션 생성 — id=%s controller=%s target=%s", session.id, current_user.username, target.username)
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
    result = await db.execute(select(Session).where(Session.id == session_id))
    session = result.scalar_one_or_none()
    if not session:
        raise HTTPException(status_code=404, detail="세션을 찾을 수 없습니다.")
    if str(session.controller_id) != str(current_user.id) and str(session.target_id) != str(current_user.id):
        if current_user.role.value != "admin":
            raise HTTPException(status_code=403, detail="접근 권한이 없습니다.")
    return session


@router.delete("/{session_id}", status_code=status.HTTP_204_NO_CONTENT)
async def end_session(session_id: str, current_user: CurrentUser, db: AsyncSession = Depends(get_db)):
    """세션 종료"""
    from datetime import datetime, timezone
    result = await db.execute(select(Session).where(Session.id == session_id))
    session = result.scalar_one_or_none()
    if not session:
        raise HTTPException(status_code=404, detail="세션을 찾을 수 없습니다.")
    session.status = SessionStatus.ended
    session.ended_at = datetime.now(timezone.utc)
    logger.info("세션 종료 — id=%s by=%s", session_id, current_user.username)
