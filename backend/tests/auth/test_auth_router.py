# [TDD] 인증 API 라우터 테스트
# POST /api/auth/login, /api/auth/refresh, /api/auth/logout, GET /api/auth/me

import pytest
from httpx import AsyncClient
from unittest.mock import patch

from app.auth.models import User
from tests.conftest import auth_header


class TestLogin:
    @pytest.mark.asyncio
    async def test_LDAP_인증_성공시_토큰_반환(self, client: AsyncClient, monkeypatch):
        """LDAP 인증 성공 → access_token + refresh_token 반환"""
        mock_user_info = {
            "username": "hong",
            "email": "hong@corp.local",
            "display_name": "홍길동",
            "groups": [],
        }
        with patch("app.auth.router.ldap_provider.authenticate", return_value=mock_user_info):
            res = await client.post("/api/auth/login", json={"username": "hong", "password": "pass"})

        assert res.status_code == 200
        data = res.json()
        assert "access_token" in data
        assert "refresh_token" in data
        assert data["token_type"] == "bearer"
        assert data["expires_in"] > 0

    @pytest.mark.asyncio
    async def test_LDAP_인증_실패시_401(self, client: AsyncClient):
        with patch("app.auth.router.ldap_provider.authenticate", return_value=None):
            res = await client.post("/api/auth/login", json={"username": "hong", "password": "wrong"})
        assert res.status_code == 401

    @pytest.mark.asyncio
    async def test_빈_비밀번호_401(self, client: AsyncClient):
        with patch("app.auth.router.ldap_provider.authenticate", return_value=None):
            res = await client.post("/api/auth/login", json={"username": "hong", "password": ""})
        assert res.status_code == 401

    @pytest.mark.asyncio
    async def test_로그인_성공시_사용자_DB_생성(self, client: AsyncClient, db, monkeypatch):
        """처음 로그인하는 사용자는 DB에 자동 생성"""
        from sqlalchemy import select
        mock_user_info = {"username": "newuser", "email": "new@corp.local", "display_name": "신규", "groups": []}
        with patch("app.auth.router.ldap_provider.authenticate", return_value=mock_user_info):
            await client.post("/api/auth/login", json={"username": "newuser", "password": "pass"})

        from app.auth.models import User
        result = await db.execute(select(User).where(User.username == "newuser"))
        user = result.scalar_one_or_none()
        assert user is not None
        assert user.email == "new@corp.local"


class TestMe:
    @pytest.mark.asyncio
    async def test_인증된_사용자_정보_반환(self, client: AsyncClient, normal_user: User):
        res = await client.get("/api/auth/me", headers=auth_header(normal_user))
        assert res.status_code == 200
        data = res.json()
        assert data["username"] == normal_user.username
        assert data["role"] == normal_user.role.value

    @pytest.mark.asyncio
    async def test_토큰_없으면_401(self, client: AsyncClient):
        res = await client.get("/api/auth/me")
        assert res.status_code == 401  # FastAPI 0.135+ HTTPBearer returns 401

    @pytest.mark.asyncio
    async def test_잘못된_토큰_401(self, client: AsyncClient):
        res = await client.get("/api/auth/me", headers={"Authorization": "Bearer invalid.token.here"})
        assert res.status_code == 401
