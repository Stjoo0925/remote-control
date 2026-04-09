# [TDD] JWT 서비스 테스트
# 테스트가 명세 역할을 합니다.
# 이 파일의 모든 테스트가 통과해야 jwt_service.py 구현이 완성된 것입니다.

import time
import pytest
from app.auth.jwt_service import jwt_service


class TestCreateAccessToken:
    def test_토큰_생성_성공(self):
        token = jwt_service.create_access_token("user-123", "hong", "support")
        assert isinstance(token, str)
        assert len(token) > 0

    def test_payload에_필수_필드_포함(self):
        token = jwt_service.create_access_token("user-123", "hong", "support")
        payload = jwt_service.verify_token(token)
        assert payload["sub"] == "user-123"
        assert payload["username"] == "hong"
        assert payload["role"] == "support"
        assert payload["type"] == "access"

    def test_서로_다른_사용자는_다른_토큰(self):
        t1 = jwt_service.create_access_token("user-1", "hong", "user")
        t2 = jwt_service.create_access_token("user-2", "kim", "user")
        assert t1 != t2


class TestCreateRefreshToken:
    def test_refresh_토큰_생성(self):
        token = jwt_service.create_refresh_token("user-123")
        assert isinstance(token, str)

    def test_refresh_payload_type(self):
        token = jwt_service.create_refresh_token("user-123")
        payload = jwt_service.verify_token(token)
        assert payload["type"] == "refresh"
        assert payload["sub"] == "user-123"

    def test_access_와_refresh_토큰은_다름(self):
        access = jwt_service.create_access_token("u1", "hong", "user")
        refresh = jwt_service.create_refresh_token("u1")
        assert access != refresh


class TestVerifyToken:
    def test_유효한_토큰_검증_성공(self):
        token = jwt_service.create_access_token("u1", "hong", "user")
        payload = jwt_service.verify_token(token)
        assert payload is not None

    def test_위변조된_토큰_None_반환(self):
        token = jwt_service.create_access_token("u1", "hong", "user")
        tampered = token[:-5] + "xxxxx"
        assert jwt_service.verify_token(tampered) is None

    def test_빈_문자열_None_반환(self):
        assert jwt_service.verify_token("") is None

    def test_잘못된_형식_None_반환(self):
        assert jwt_service.verify_token("not.a.jwt") is None

    def test_만료된_토큰_None_반환(self, monkeypatch):
        """만료 시간을 과거로 설정해 만료 시나리오 테스트"""
        from datetime import datetime, timedelta, timezone
        import jwt

        from app.config import settings
        expired_payload = {
            "sub": "u1",
            "username": "hong",
            "role": "user",
            "type": "access",
            "exp": datetime.now(timezone.utc) - timedelta(seconds=1),
            "iat": datetime.now(timezone.utc) - timedelta(minutes=16),
        }
        expired_token = jwt.encode(expired_payload, settings.JWT_SECRET_KEY, algorithm=settings.JWT_ALGORITHM)
        assert jwt_service.verify_token(expired_token) is None
