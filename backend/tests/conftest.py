# pytest 공용 픽스처
# 테스트용 DB, HTTP 클라이언트, 인증 토큰 등을 제공합니다.

import pytest
import pytest_asyncio
from httpx import AsyncClient, ASGITransport
from sqlalchemy.ext.asyncio import create_async_engine, async_sessionmaker, AsyncSession

from app.main import socket_app
from app.database import Base, get_db
from app.auth.models import User, UserRole
from app.auth.jwt_service import jwt_service

# 테스트용 인메모리 SQLite (PostgreSQL 없이도 테스트 가능)
TEST_DB_URL = "sqlite+aiosqlite:///:memory:"

test_engine = create_async_engine(TEST_DB_URL, echo=False)
TestSession = async_sessionmaker(test_engine, class_=AsyncSession, expire_on_commit=False)


@pytest_asyncio.fixture(autouse=True)
async def setup_db():
    """각 테스트 전 테이블 생성, 후 삭제"""
    async with test_engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    yield
    async with test_engine.begin() as conn:
        await conn.run_sync(Base.metadata.drop_all)


@pytest_asyncio.fixture
async def db() -> AsyncSession:
    """테스트용 DB 세션"""
    async with TestSession() as session:
        yield session


@pytest_asyncio.fixture
async def client(db: AsyncSession) -> AsyncClient:
    """테스트용 HTTP 클라이언트 (DB 세션 주입)"""
    async def override_get_db():
        yield db

    from app.main import app
    app.dependency_overrides[get_db] = override_get_db

    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as c:
        yield c

    app.dependency_overrides.clear()


@pytest_asyncio.fixture
async def admin_user(db: AsyncSession) -> User:
    """관리자 계정 픽스처"""
    import uuid
    user = User(
        id=uuid.uuid4(),
        username="admin",
        email="admin@corp.local",
        display_name="관리자",
        role=UserRole.admin,
        is_active=True,
    )
    db.add(user)
    await db.commit()
    return user


@pytest_asyncio.fixture
async def support_user(db: AsyncSession) -> User:
    """지원 담당자 계정 픽스처"""
    import uuid
    user = User(
        id=uuid.uuid4(),
        username="support1",
        email="support1@corp.local",
        display_name="지원담당자",
        role=UserRole.support,
        is_active=True,
    )
    db.add(user)
    await db.commit()
    return user


@pytest_asyncio.fixture
async def normal_user(db: AsyncSession) -> User:
    """일반 사용자 계정 픽스처"""
    import uuid
    user = User(
        id=uuid.uuid4(),
        username="user1",
        email="user1@corp.local",
        display_name="일반사용자",
        role=UserRole.user,
        is_active=True,
    )
    db.add(user)
    await db.commit()
    return user


def make_token(user: User) -> str:
    """테스트용 JWT 액세스 토큰 생성"""
    return jwt_service.create_access_token(str(user.id), user.username, user.role.value)


def auth_header(user: User) -> dict:
    """Authorization 헤더 딕셔너리 반환"""
    return {"Authorization": f"Bearer {make_token(user)}"}
