import uuid
from datetime import datetime, timezone

import pytest
from httpx import AsyncClient
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth.models import AuditLog, User
from app.sessions.models import Session, SessionStatus
from tests.conftest import auth_header


async def _create_session(client: AsyncClient, actor: User, target: User) -> dict:
    response = await client.post(
        "/api/sessions",
        json={"target_username": target.username},
        headers=auth_header(actor),
    )
    assert response.status_code == 201
    return response.json()


@pytest.mark.asyncio
async def test_admin_lists_and_filters_sessions(
    client: AsyncClient,
    admin_user: User,
    support_user: User,
    normal_user: User,
    db: AsyncSession,
):
    active_session = await _create_session(client, support_user, normal_user)

    ended = Session(
        id=uuid.uuid4(),
        controller_id=admin_user.id,
        target_id=normal_user.id,
        status=SessionStatus.ended,
        ended_at=datetime.now(timezone.utc),
    )
    db.add(ended)
    await db.commit()

    response = await client.get("/api/admin/sessions", headers=auth_header(admin_user))
    assert response.status_code == 200
    assert {item["id"] for item in response.json()} >= {active_session["id"], str(ended.id)}

    filtered = await client.get(
        "/api/admin/sessions",
        params={"status_filter": "ended"},
        headers=auth_header(admin_user),
    )
    assert filtered.status_code == 200
    assert [item["status"] for item in filtered.json()] == ["ended"]


@pytest.mark.asyncio
async def test_admin_force_ends_session(
    client: AsyncClient,
    admin_user: User,
    support_user: User,
    normal_user: User,
    db: AsyncSession,
):
    created = await _create_session(client, support_user, normal_user)

    response = await client.delete(
        f"/api/admin/sessions/{created['id']}",
        headers=auth_header(admin_user),
    )
    assert response.status_code == 204

    result = await db.execute(select(Session).where(Session.id == uuid.UUID(created["id"])))
    session = result.scalar_one()
    assert session.status == SessionStatus.ended
    assert session.ended_at is not None


@pytest.mark.asyncio
async def test_admin_lists_audit_logs_with_paging(
    client: AsyncClient,
    admin_user: User,
    db: AsyncSession,
):
    logs = [
        AuditLog(action=f"action-{index}", target=f"target-{index}", user_id=admin_user.id)
        for index in range(3)
    ]
    db.add_all(logs)
    await db.commit()

    response = await client.get(
        "/api/admin/audit-logs",
        params={"page": 1, "size": 2},
        headers=auth_header(admin_user),
    )
    assert response.status_code == 200
    payload = response.json()
    assert payload["page"] == 1
    assert payload["size"] == 2
    assert len(payload["items"]) == 2


@pytest.mark.asyncio
async def test_admin_lists_users_and_updates_role(
    client: AsyncClient,
    admin_user: User,
    support_user: User,
    normal_user: User,
):
    users_response = await client.get("/api/admin/users", headers=auth_header(admin_user))
    assert users_response.status_code == 200
    usernames = [item["username"] for item in users_response.json()]
    assert usernames == sorted(usernames)

    update_response = await client.patch(
        f"/api/admin/users/{normal_user.id}/role",
        json={"role": "support"},
        headers=auth_header(admin_user),
    )
    assert update_response.status_code == 200
    assert update_response.json()["role"] == "support"


@pytest.mark.asyncio
async def test_non_admin_cannot_access_admin_routes(
    client: AsyncClient,
    support_user: User,
):
    response = await client.get("/api/admin/users", headers=auth_header(support_user))
    assert response.status_code == 403
