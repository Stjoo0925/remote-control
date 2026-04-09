import pytest

from app.sessions import signaling


@pytest.fixture(autouse=True)
def reset_signaling_state():
    signaling._connected_users.clear()
    signaling._username_to_sid.clear()


@pytest.mark.asyncio
async def test_chat_message_emits_to_session_room(monkeypatch: pytest.MonkeyPatch):
    signaling._connected_users["sid-controller"] = {
        "id": "user-1",
        "username": "controller",
        "role": "support",
    }
    emitted: list[tuple[str, dict, dict]] = []

    async def fake_emit(event, payload, **kwargs):
        emitted.append((event, payload, kwargs))

    monkeypatch.setattr(signaling.sio, "emit", fake_emit)

    await signaling.chat_message(
        "sid-controller",
        {"session_id": "session-1", "text": "hello", "timestamp": "2026-04-09T00:00:00Z"},
    )

    assert emitted == [
        (
            "chat_message",
            {
                "session_id": "session-1",
                "sender_id": "user-1",
                "sender_name": "controller",
                "text": "hello",
                "timestamp": "2026-04-09T00:00:00Z",
            },
            {"room": "session-1"},
        )
    ]


@pytest.mark.asyncio
async def test_clipboard_sync_emits_only_to_target(monkeypatch: pytest.MonkeyPatch):
    signaling._connected_users["sid-controller"] = {
        "id": "user-1",
        "username": "controller",
        "role": "support",
    }
    signaling._username_to_sid["target"] = "sid-target"
    emitted: list[tuple[str, dict, dict]] = []

    async def fake_emit(event, payload, **kwargs):
        emitted.append((event, payload, kwargs))

    monkeypatch.setattr(signaling.sio, "emit", fake_emit)

    payload = {"session_id": "session-1", "text": "copied", "target_username": "target"}
    await signaling.clipboard_sync("sid-controller", payload)

    assert emitted == [("clipboard_sync", payload, {"to": "sid-target"})]


@pytest.mark.asyncio
async def test_file_transfer_notify_skips_sender(monkeypatch: pytest.MonkeyPatch):
    emitted: list[tuple[str, dict, dict]] = []

    async def fake_emit(event, payload, **kwargs):
        emitted.append((event, payload, kwargs))

    monkeypatch.setattr(signaling.sio, "emit", fake_emit)

    payload = {
        "session_id": "session-1",
        "event": "completed",
        "transfer_id": "transfer-1",
        "filename": "hello.txt",
        "file_size": 5,
    }
    await signaling.file_transfer_notify("sid-controller", payload)

    assert emitted == [("file_transfer_notify", payload, {"room": "session-1", "skip_sid": "sid-controller"})]


@pytest.mark.asyncio
async def test_switch_monitor_emits_to_target_agent(monkeypatch: pytest.MonkeyPatch):
    signaling._username_to_sid["target"] = "sid-target"
    emitted: list[tuple[str, dict, dict]] = []

    async def fake_emit(event, payload, **kwargs):
        emitted.append((event, payload, kwargs))

    monkeypatch.setattr(signaling.sio, "emit", fake_emit)

    payload = {"session_id": "session-1", "target_username": "target", "monitor_index": 1}
    await signaling.switch_monitor("sid-controller", payload)

    assert emitted == [("switch_monitor", payload, {"to": "sid-target"})]
