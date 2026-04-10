# JWT 토큰 발급 및 검증 서비스

from datetime import datetime, timedelta, timezone
from typing import Optional
import jwt

from app.config import settings


class JWTService:
    def create_access_token(
        self,
        user_id: str,
        username: str,
        role: str,
        extra_claims: Optional[dict] = None,
        expires_minutes: Optional[int] = None,
    ) -> str:
        minutes = expires_minutes if expires_minutes is not None else settings.JWT_ACCESS_TOKEN_EXPIRE_MINUTES
        payload = {
            "sub": user_id,
            "username": username,
            "role": role,
            "type": "access",
            "exp": datetime.now(timezone.utc) + timedelta(minutes=minutes),
            "iat": datetime.now(timezone.utc),
        }
        if extra_claims:
            payload.update(extra_claims)
        return jwt.encode(payload, settings.JWT_SECRET_KEY, algorithm=settings.JWT_ALGORITHM)

    def create_refresh_token(self, user_id: str) -> str:
        payload = {
            "sub": user_id,
            "type": "refresh",
            "exp": datetime.now(timezone.utc) + timedelta(hours=settings.JWT_REFRESH_TOKEN_EXPIRE_HOURS),
            "iat": datetime.now(timezone.utc),
        }
        return jwt.encode(payload, settings.JWT_SECRET_KEY, algorithm=settings.JWT_ALGORITHM)

    def verify_token(self, token: str) -> Optional[dict]:
        """토큰 검증. 유효하면 payload 반환, 아니면 None"""
        try:
            return jwt.decode(token, settings.JWT_SECRET_KEY, algorithms=[settings.JWT_ALGORITHM])
        except jwt.ExpiredSignatureError:
            return None
        except jwt.InvalidTokenError:
            return None


jwt_service = JWTService()
