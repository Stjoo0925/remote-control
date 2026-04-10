# 페어링 코드 라우터
#
# 외부 IP를 가진 기기(다른 네트워크의 PC, 스마트폰 등)가 계정 없이 세션에
# 참여할 수 있도록 하는 일회성 초대 코드 시스템입니다.
#
# 흐름:
#   1. Controller(지원자)가 POST /api/pairing/generate 호출 → 6자리 코드 + 10분 만료
#   2. 피제어 기기가 코드를 에이전트 앱에 입력
#   3. 에이전트가 POST /api/pairing/redeem 호출 → 단기 JWT 수신
#   4. 해당 JWT로 Signaling 서버에 WebSocket 연결
#   5. 일반 WebRTC 세션 흐름 진행
#
# POST /api/pairing/generate — 코드 발급 (인증 필요)
# POST /api/pairing/redeem   — 코드 교환 → 임시 JWT (인증 불필요)
# GET  /api/pairing/status   — 코드 상태 확인 (인증 필요)

import logging
import random
import string
import uuid
from datetime import datetime, timezone, timedelta

import redis.asyncio as aioredis
from fastapi import APIRouter, Depends, HTTPException, Request, status
from pydantic import BaseModel
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from app.config import settings
from app.database import get_db
from app.auth.dependencies import CurrentUser
from app.auth.jwt_service import jwt_service
from app.auth.models import User

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/api/pairing", tags=["pairing"])
_redis = aioredis.from_url(settings.REDIS_URL, decode_responses=True)

_PAIRING_TTL_SECONDS = 600  # 10분
_CODE_PREFIX = "pairing:"


def _generate_code(length: int = 6) -> str:
    """대문자+숫자 조합의 읽기 쉬운 코드 생성 (혼동 문자 제외)"""
    charset = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
    return "".join(random.SystemRandom().choice(charset) for _ in range(length))


# ── Pydantic 스키마 ──────────────────────────────────────────────────────

class GenerateResponse(BaseModel):
    code: str
    expires_in: int   # 초
    expires_at: str   # ISO8601


class RedeemRequest(BaseModel):
    code: str
    device_name: str = "Unknown Device"


class RedeemResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
    expires_in: int   # 초
    controller_username: str
    session_note: str


class CodeStatusResponse(BaseModel):
    code: str
    valid: bool
    used: bool
    expires_at: str | None


# ── 엔드포인트 ───────────────────────────────────────────────────────────

@router.post("/generate", response_model=GenerateResponse)
async def generate_pairing_code(current_user: CurrentUser):
    """
    인증된 사용자(Controller)가 페어링 코드를 발급합니다.
    코드는 10분 후 자동 만료되며 1회만 사용 가능합니다.
    """
    # 기존 코드가 있으면 삭제 (중복 방지)
    old_key = await _redis.get(f"pairing_user:{current_user.username}")
    if old_key:
        await _redis.delete(old_key)

    code = _generate_code()
    redis_key = f"{_CODE_PREFIX}{code}"
    expires_at = datetime.now(timezone.utc) + timedelta(seconds=_PAIRING_TTL_SECONDS)

    await _redis.setex(
        redis_key,
        _PAIRING_TTL_SECONDS,
        f"{current_user.username}|{current_user.id}|{current_user.role.value}|{expires_at.isoformat()}",
    )
    # 사용자 → 코드 역방향 인덱스 (재발급 시 이전 코드 삭제용)
    await _redis.setex(f"pairing_user:{current_user.username}", _PAIRING_TTL_SECONDS, redis_key)

    logger.info("페어링 코드 발급 — user=%s code=%s", current_user.username, code)
    return GenerateResponse(
        code=code,
        expires_in=_PAIRING_TTL_SECONDS,
        expires_at=expires_at.isoformat(),
    )


@router.post("/redeem", response_model=RedeemResponse)
async def redeem_pairing_code(body: RedeemRequest, request: Request):
    """
    외부 기기(에이전트)가 페어링 코드를 제출해 임시 JWT를 교환합니다.
    인증이 필요 없으며 LDAP/계정 없이도 호출 가능합니다.
    임시 JWT는 1시간 유효하고 role=user로 발급됩니다.
    """
    redis_key = f"{_CODE_PREFIX}{body.code.upper().strip()}"
    raw = await _redis.get(redis_key)
    if not raw:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="유효하지 않거나 만료된 코드입니다.")

    parts = raw.split("|")
    controller_username, controller_id, controller_role, expires_at_str = parts[0], parts[1], parts[2], parts[3]

    # 코드 즉시 삭제 (1회용)
    await _redis.delete(redis_key)
    await _redis.delete(f"pairing_user:{controller_username}")

    # 에이전트용 임시 사용자 ID (재사용하지 않는 세션 전용 UUID)
    agent_id = str(uuid.uuid4())
    agent_username = f"agent_{body.device_name.replace(' ', '_')}_{agent_id[:8]}"

    # role=user, type=pairing 클레임 포함 단기 토큰
    access_token = jwt_service.create_access_token(
        agent_id,
        agent_username,
        "user",
        extra_claims={
            "type": "pairing",
            "controller_username": controller_username,
            "device_name": body.device_name,
        },
        expires_minutes=60,
    )

    client_ip = request.client.host if request.client else "unknown"
    logger.info(
        "페어링 코드 교환 — code=%s device=%s ip=%s controller=%s",
        body.code, body.device_name, client_ip, controller_username,
    )
    return RedeemResponse(
        access_token=access_token,
        expires_in=3600,
        controller_username=controller_username,
        session_note=f"{body.device_name} connected via pairing code",
    )


@router.get("/status/{code}", response_model=CodeStatusResponse)
async def check_code_status(code: str, current_user: CurrentUser):
    """발급한 코드의 유효 여부를 조회합니다."""
    redis_key = f"{_CODE_PREFIX}{code.upper().strip()}"
    raw = await _redis.get(redis_key)
    if not raw:
        return CodeStatusResponse(code=code, valid=False, used=True, expires_at=None)

    parts = raw.split("|")
    return CodeStatusResponse(
        code=code,
        valid=True,
        used=False,
        expires_at=parts[3] if len(parts) > 3 else None,
    )
