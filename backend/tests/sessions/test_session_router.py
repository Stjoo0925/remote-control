# [TDD] 세션 API 라우터 테스트
# POST /api/sessions, GET /api/sessions, GET /api/sessions/{id}, DELETE /api/sessions/{id}

import uuid
import pytest
from httpx import AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth.models import User
from app.sessions.models import Session, SessionStatus
from tests.conftest import auth_header


# ─────────────────────────────────────────────────────────────
# 헬퍼
# ─────────────────────────────────────────────────────────────

async def _create_session_via_api(
    client: AsyncClient,
    actor: User,
    target: User,
) -> dict:
    """API를 통해 세션 생성 후 응답 dict 반환"""
    res = await client.post(
        "/api/sessions",
        json={"target_username": target.username},
        headers=auth_header(actor),
    )
    return res


# ─────────────────────────────────────────────────────────────
# POST /api/sessions — 세션 생성
# ─────────────────────────────────────────────────────────────

class TestCreateSession:

    @pytest.mark.asyncio
    async def test_SUPPORT_계정이_세션_생성_성공(
        self, client: AsyncClient, support_user: User, normal_user: User
    ):
        res = await _create_session_via_api(client, support_user, normal_user)

        assert res.status_code == 201
        data = res.json()
        assert "id" in data
        assert data["status"] == "pending"
        assert data["controller_id"] == str(support_user.id)
        assert data["target_id"] == str(normal_user.id)

    @pytest.mark.asyncio
    async def test_ADMIN_계정이_세션_생성_성공(
        self, client: AsyncClient, admin_user: User, normal_user: User
    ):
        res = await _create_session_via_api(client, admin_user, normal_user)
        assert res.status_code == 201

    @pytest.mark.asyncio
    async def test_일반_사용자는_세션_생성_불가(
        self, client: AsyncClient, normal_user: User, support_user: User
    ):
        res = await _create_session_via_api(client, normal_user, support_user)
        assert res.status_code == 403

    @pytest.mark.asyncio
    async def test_자기_자신에게_세션_생성_불가(
        self, client: AsyncClient, support_user: User
    ):
        res = await client.post(
            "/api/sessions",
            json={"target_username": support_user.username},
            headers=auth_header(support_user),
        )
        assert res.status_code == 400

    @pytest.mark.asyncio
    async def test_존재하지_않는_대상_사용자_404(
        self, client: AsyncClient, support_user: User
    ):
        res = await client.post(
            "/api/sessions",
            json={"target_username": "ghost_user_xyz"},
            headers=auth_header(support_user),
        )
        assert res.status_code == 404

    @pytest.mark.asyncio
    async def test_인증_없이_세션_생성_불가(self, client: AsyncClient, normal_user: User):
        res = await client.post(
            "/api/sessions",
            json={"target_username": normal_user.username},
        )
        # HTTPBearer는 헤더 없으면 403
        assert res.status_code in (401, 403)

    @pytest.mark.asyncio
    async def test_세션_생성시_DB에_저장됨(
        self, client: AsyncClient, support_user: User, normal_user: User, db: AsyncSession
    ):
        from sqlalchemy import select

        res = await _create_session_via_api(client, support_user, normal_user)
        assert res.status_code == 201
        session_id = res.json()["id"]

        result = await db.execute(select(Session).where(Session.id == uuid.UUID(session_id)))
        db_session = result.scalar_one_or_none()
        assert db_session is not None
        assert db_session.status == SessionStatus.pending


# ─────────────────────────────────────────────────────────────
# GET /api/sessions — 세션 목록
# ─────────────────────────────────────────────────────────────

class TestListSessions:

    @pytest.mark.asyncio
    async def test_내가_참여한_세션만_반환(
        self, client: AsyncClient, support_user: User, normal_user: User, admin_user: User
    ):
        # support_user → normal_user 세션 생성
        await _create_session_via_api(client, support_user, normal_user)
        # admin_user → support_user 세션 생성 (normal_user는 미참여)
        await _create_session_via_api(client, admin_user, support_user)

        # normal_user 입장에서는 자신이 target인 세션 1개만 보여야 함
        res = await client.get("/api/sessions", headers=auth_header(normal_user))
        assert res.status_code == 200
        sessions = res.json()
        assert len(sessions) == 1
        assert sessions[0]["target_id"] == str(normal_user.id)

    @pytest.mark.asyncio
    async def test_세션_없으면_빈_배열(self, client: AsyncClient, normal_user: User):
        res = await client.get("/api/sessions", headers=auth_header(normal_user))
        assert res.status_code == 200
        assert res.json() == []

    @pytest.mark.asyncio
    async def test_인증_없이_목록_조회_불가(self, client: AsyncClient):
        res = await client.get("/api/sessions")
        assert res.status_code in (401, 403)


# ─────────────────────────────────────────────────────────────
# GET /api/sessions/{id} — 세션 상세
# ─────────────────────────────────────────────────────────────

class TestGetSession:

    @pytest.mark.asyncio
    async def test_참여자가_세션_조회_성공(
        self, client: AsyncClient, support_user: User, normal_user: User
    ):
        create_res = await _create_session_via_api(client, support_user, normal_user)
        session_id = create_res.json()["id"]

        # controller (support_user)
        res = await client.get(f"/api/sessions/{session_id}", headers=auth_header(support_user))
        assert res.status_code == 200
        assert res.json()["id"] == session_id

        # target (normal_user)
        res = await client.get(f"/api/sessions/{session_id}", headers=auth_header(normal_user))
        assert res.status_code == 200

    @pytest.mark.asyncio
    async def test_비참여_일반_사용자는_403(
        self,
        client: AsyncClient,
        support_user: User,
        normal_user: User,
        db: AsyncSession,
    ):
        """세션에 참여하지 않은 user가 조회하면 403"""
        import uuid
        # DB에 직접 세션 생성 (normal_user는 미참여)
        outsider = User(
            id=uuid.uuid4(),
            username="outsider",
            email="out@corp.local",
            display_name="외부인",
            role=__import__("app.auth.models", fromlist=["UserRole"]).UserRole.user,
            is_active=True,
        )
        db.add(outsider)
        await db.commit()

        create_res = await _create_session_via_api(client, support_user, normal_user)
        session_id = create_res.json()["id"]

        res = await client.get(f"/api/sessions/{session_id}", headers=auth_header(outsider))
        assert res.status_code == 403

    @pytest.mark.asyncio
    async def test_admin은_모든_세션_조회_가능(
        self, client: AsyncClient, support_user: User, normal_user: User, admin_user: User
    ):
        create_res = await _create_session_via_api(client, support_user, normal_user)
        session_id = create_res.json()["id"]

        res = await client.get(f"/api/sessions/{session_id}", headers=auth_header(admin_user))
        assert res.status_code == 200

    @pytest.mark.asyncio
    async def test_존재하지_않는_세션_404(self, client: AsyncClient, support_user: User):
        fake_id = str(uuid.uuid4())
        res = await client.get(f"/api/sessions/{fake_id}", headers=auth_header(support_user))
        assert res.status_code == 404


# ─────────────────────────────────────────────────────────────
# DELETE /api/sessions/{id} — 세션 종료
# ─────────────────────────────────────────────────────────────

class TestEndSession:

    @pytest.mark.asyncio
    async def test_controller가_세션_종료_성공(
        self,
        client: AsyncClient,
        support_user: User,
        normal_user: User,
        db: AsyncSession,
    ):
        from sqlalchemy import select

        create_res = await _create_session_via_api(client, support_user, normal_user)
        session_id = create_res.json()["id"]

        res = await client.delete(
            f"/api/sessions/{session_id}",
            headers=auth_header(support_user),
        )
        assert res.status_code == 204

        # DB 상태 확인
        await db.reset()  # 세션 캐시 초기화
        result = await db.execute(select(Session).where(Session.id == uuid.UUID(session_id)))
        db_session = result.scalar_one_or_none()
        assert db_session is not None
        assert db_session.status == SessionStatus.ended
        assert db_session.ended_at is not None

    @pytest.mark.asyncio
    async def test_target이_세션_종료_가능(
        self, client: AsyncClient, support_user: User, normal_user: User
    ):
        create_res = await _create_session_via_api(client, support_user, normal_user)
        session_id = create_res.json()["id"]

        res = await client.delete(
            f"/api/sessions/{session_id}",
            headers=auth_header(normal_user),
        )
        assert res.status_code == 204

    @pytest.mark.asyncio
    async def test_존재하지_않는_세션_종료_404(
        self, client: AsyncClient, support_user: User
    ):
        fake_id = str(uuid.uuid4())
        res = await client.delete(
            f"/api/sessions/{fake_id}",
            headers=auth_header(support_user),
        )
        assert res.status_code == 404

    @pytest.mark.asyncio
    async def test_인증_없이_세션_종료_불가(self, client: AsyncClient):
        res = await client.delete(f"/api/sessions/{uuid.uuid4()}")
        assert res.status_code in (401, 403)
