# 관리자 API 라우터 (ROLE_ADMIN 전용)

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, desc
from datetime import datetime, timezone

from app.database import get_db
from app.auth.dependencies import AdminOnly
from app.auth.models import User, AuditLog, RoleUpdateRequest, UserInfo
from app.sessions.models import Session, SessionStatus, SessionResponse

router = APIRouter(prefix="/api/admin", tags=["admin"])


@router.get("/sessions", response_model=list[SessionResponse])
async def list_all_sessions(
    current_user: AdminOnly,
    status_filter: str | None = None,
    db: AsyncSession = Depends(get_db),
):
    """전체 세션 목록 (관리자 전용)"""
    query = select(Session).order_by(desc(Session.created_at)).limit(100)
    if status_filter:
        query = query.where(Session.status == status_filter)
    result = await db.execute(query)
    return result.scalars().all()


@router.delete("/sessions/{session_id}", status_code=status.HTTP_204_NO_CONTENT)
async def force_end_session(
    session_id: str,
    current_user: AdminOnly,
    db: AsyncSession = Depends(get_db),
):
    """세션 강제 종료"""
    result = await db.execute(select(Session).where(Session.id == session_id))
    session = result.scalar_one_or_none()
    if not session:
        raise HTTPException(status_code=404, detail="세션을 찾을 수 없습니다.")
    session.status = SessionStatus.ended
    session.ended_at = datetime.now(timezone.utc)


@router.get("/audit-logs")
async def get_audit_logs(
    current_user: AdminOnly,
    page: int = 1,
    size: int = 50,
    db: AsyncSession = Depends(get_db),
):
    """감사 로그 조회 (페이지네이션)"""
    offset = (page - 1) * size
    result = await db.execute(
        select(AuditLog).order_by(desc(AuditLog.created_at)).offset(offset).limit(size)
    )
    logs = result.scalars().all()
    return {"page": page, "size": size, "items": logs}


@router.get("/users", response_model=list[UserInfo])
async def list_users(current_user: AdminOnly, db: AsyncSession = Depends(get_db)):
    """사용자 목록"""
    result = await db.execute(select(User).order_by(User.username))
    return result.scalars().all()


@router.patch("/users/{user_id}/role", response_model=UserInfo)
async def update_user_role(
    user_id: str,
    body: RoleUpdateRequest,
    current_user: AdminOnly,
    db: AsyncSession = Depends(get_db),
):
    """사용자 역할 변경"""
    result = await db.execute(select(User).where(User.id == user_id))
    user = result.scalar_one_or_none()
    if not user:
        raise HTTPException(status_code=404, detail="사용자를 찾을 수 없습니다.")
    user.role = body.role
    return user
