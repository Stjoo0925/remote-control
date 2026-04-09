# 인증 API 라우터
# POST /api/auth/login  — LDAP 인증 후 JWT 발급
# POST /api/auth/refresh — 토큰 갱신
# POST /api/auth/logout  — 로그아웃 (Redis blacklist)
# GET  /api/auth/me      — 현재 사용자 정보

import logging
from datetime import datetime, timezone
from fastapi import APIRouter, Depends, HTTPException, Request, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
import redis.asyncio as aioredis

from app.database import get_db
from app.config import settings
from app.auth.models import LoginRequest, TokenResponse, UserInfo, User
from app.auth.ldap_provider import ldap_provider
from app.auth.jwt_service import jwt_service
from app.auth.dependencies import CurrentUser

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/api/auth", tags=["auth"])
_redis = aioredis.from_url(settings.REDIS_URL, decode_responses=True)


@router.post("/login", response_model=TokenResponse)
async def login(body: LoginRequest, request: Request, db: AsyncSession = Depends(get_db)):
    client_ip = request.client.host if request.client else "unknown"

    # LDAP 인증
    user_info = ldap_provider.authenticate(body.username, body.password)
    if not user_info:
        logger.warning("로그인 실패 — username=%s ip=%s", body.username, client_ip)
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="아이디 또는 비밀번호가 올바르지 않습니다.")

    # DB에 사용자 upsert
    result = await db.execute(select(User).where(User.username == body.username))
    user = result.scalar_one_or_none()
    if not user:
        user = User(
            username=user_info["username"],
            email=user_info["email"],
            display_name=user_info["display_name"],
        )
        db.add(user)

    user.last_login = datetime.now(timezone.utc)
    await db.flush()

    access_token = jwt_service.create_access_token(str(user.id), user.username, user.role.value)
    refresh_token = jwt_service.create_refresh_token(str(user.id))

    logger.info("로그인 성공 — username=%s ip=%s", body.username, client_ip)
    return TokenResponse(
        access_token=access_token,
        refresh_token=refresh_token,
        expires_in=settings.JWT_ACCESS_TOKEN_EXPIRE_MINUTES * 60,
    )


@router.post("/refresh", response_model=TokenResponse)
async def refresh(refresh_token: str, db: AsyncSession = Depends(get_db)):
    payload = jwt_service.verify_token(refresh_token)
    if not payload or payload.get("type") != "refresh":
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="유효하지 않은 refresh token입니다.")

    # blacklist 확인
    if await _redis.get(f"blacklist:{refresh_token}"):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="만료된 토큰입니다.")

    result = await db.execute(select(User).where(User.id == payload["sub"], User.is_active == True))
    user = result.scalar_one_or_none()
    if not user:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="사용자를 찾을 수 없습니다.")

    access_token = jwt_service.create_access_token(str(user.id), user.username, user.role.value)
    new_refresh = jwt_service.create_refresh_token(str(user.id))
    return TokenResponse(
        access_token=access_token,
        refresh_token=new_refresh,
        expires_in=settings.JWT_ACCESS_TOKEN_EXPIRE_MINUTES * 60,
    )


@router.post("/logout", status_code=status.HTTP_204_NO_CONTENT)
async def logout(refresh_token: str):
    payload = jwt_service.verify_token(refresh_token)
    if payload:
        import time
        ttl = int(payload["exp"] - time.time())
        if ttl > 0:
            await _redis.setex(f"blacklist:{refresh_token}", ttl, "1")


@router.get("/me", response_model=UserInfo)
async def me(current_user: CurrentUser):
    return UserInfo(
        id=str(current_user.id),
        username=current_user.username,
        email=current_user.email,
        display_name=current_user.display_name,
        role=current_user.role,
    )
