import uuid
from pathlib import Path

import pytest
from httpx import AsyncClient
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth.models import User, UserRole
from app.file_transfer.models import FileTransfer, TransferDirection, TransferStatus
from tests.conftest import auth_header


async def _create_session(client: AsyncClient, actor: User, target: User) -> str:
    response = await client.post(
        "/api/sessions",
        json={"target_username": target.username},
        headers=auth_header(actor),
    )
    assert response.status_code == 201
    return response.json()["id"]


def _transfer_dir(name: str) -> Path:
    path = Path("C:/Users/yusco/workdir/remote-control/.test-temp") / name
    path.mkdir(parents=True, exist_ok=True)
    return path


@pytest.mark.asyncio
async def test_file_transfer_upload_complete_and_list(
    client: AsyncClient,
    support_user: User,
    normal_user: User,
    db: AsyncSession,
    monkeypatch: pytest.MonkeyPatch,
):
    from app.file_transfer import router as file_transfer_router

    monkeypatch.setattr(file_transfer_router, "TRANSFER_DIR", _transfer_dir("upload-complete"))

    session_id = await _create_session(client, support_user, normal_user)
    init_response = await client.post(
        "/api/file-transfers",
        json={
            "session_id": session_id,
            "filename": "hello.txt",
            "mime_type": "text/plain",
            "file_size": 5,
            "direction": TransferDirection.controller_to_target.value,
        },
        headers=auth_header(support_user),
    )

    assert init_response.status_code == 201
    transfer_id = init_response.json()["id"]

    upload_response = await client.put(
        f"/api/file-transfers/{transfer_id}/chunk",
        content=b"hello",
        headers={
            **auth_header(support_user),
            "Content-Range": "bytes 0-4/5",
        },
    )
    assert upload_response.status_code == 200
    assert upload_response.json()["status"] == TransferStatus.in_progress.value

    complete_response = await client.post(
        f"/api/file-transfers/{transfer_id}/complete",
        headers=auth_header(support_user),
    )
    assert complete_response.status_code == 200
    assert complete_response.json()["status"] == TransferStatus.completed.value

    list_response = await client.get(
        f"/api/file-transfers/session/{session_id}",
        headers=auth_header(normal_user),
    )
    assert list_response.status_code == 200
    assert [item["id"] for item in list_response.json()] == [transfer_id]

    download_response = await client.get(
        f"/api/file-transfers/{transfer_id}/download",
        headers=auth_header(normal_user),
    )
    assert download_response.status_code == 200
    assert download_response.content == b"hello"

    result = await db.execute(select(FileTransfer).where(FileTransfer.id == uuid.UUID(transfer_id)))
    transfer = result.scalar_one()
    assert transfer.transferred_bytes == 5
    assert transfer.status == TransferStatus.completed


@pytest.mark.asyncio
async def test_file_transfer_rejects_chunk_length_mismatch(
    client: AsyncClient,
    support_user: User,
    normal_user: User,
    monkeypatch: pytest.MonkeyPatch,
):
    from app.file_transfer import router as file_transfer_router

    monkeypatch.setattr(file_transfer_router, "TRANSFER_DIR", _transfer_dir("chunk-mismatch"))

    session_id = await _create_session(client, support_user, normal_user)
    init_response = await client.post(
        "/api/file-transfers",
        json={
            "session_id": session_id,
            "filename": "bad.txt",
            "mime_type": "text/plain",
            "file_size": 5,
            "direction": TransferDirection.controller_to_target.value,
        },
        headers=auth_header(support_user),
    )
    transfer_id = init_response.json()["id"]

    upload_response = await client.put(
        f"/api/file-transfers/{transfer_id}/chunk",
        content=b"nope",
        headers={
            **auth_header(support_user),
            "Content-Range": "bytes 0-4/5",
        },
    )

    assert upload_response.status_code == 400


@pytest.mark.asyncio
async def test_file_transfer_download_requires_session_participant(
    client: AsyncClient,
    support_user: User,
    normal_user: User,
    admin_user: User,
    db: AsyncSession,
    monkeypatch: pytest.MonkeyPatch,
):
    from app.file_transfer import router as file_transfer_router

    monkeypatch.setattr(file_transfer_router, "TRANSFER_DIR", _transfer_dir("participant-check"))

    session_id = await _create_session(client, support_user, normal_user)
    init_response = await client.post(
        "/api/file-transfers",
        json={
            "session_id": session_id,
            "filename": "secret.txt",
            "mime_type": "text/plain",
            "file_size": 6,
            "direction": TransferDirection.controller_to_target.value,
        },
        headers=auth_header(support_user),
    )
    transfer_id = init_response.json()["id"]

    await client.put(
        f"/api/file-transfers/{transfer_id}/chunk",
        content=b"secret",
        headers={
            **auth_header(support_user),
            "Content-Range": "bytes 0-5/6",
        },
    )
    await client.post(
        f"/api/file-transfers/{transfer_id}/complete",
        headers=auth_header(support_user),
    )

    outsider = User(
        id=uuid.uuid4(),
        username="outsider-ft",
        email="outsider-ft@corp.local",
        display_name="Outsider",
        role=UserRole.user,
        is_active=True,
    )
    db.add(outsider)
    await db.commit()

    response = await client.get(
        f"/api/file-transfers/{transfer_id}/download",
        headers=auth_header(outsider),
    )
    assert response.status_code == 403


@pytest.mark.asyncio
async def test_file_transfer_init_allows_admin_even_if_not_participant(
    client: AsyncClient,
    support_user: User,
    normal_user: User,
    admin_user: User,
):
    session_id = await _create_session(client, support_user, normal_user)

    response = await client.post(
        "/api/file-transfers",
        json={
            "session_id": session_id,
            "filename": "blocked.txt",
            "mime_type": "text/plain",
            "file_size": 7,
            "direction": TransferDirection.controller_to_target.value,
        },
        headers=auth_header(admin_user),
    )

    assert response.status_code == 201
