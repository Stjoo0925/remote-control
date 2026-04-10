# WebRTC Signaling 서버
# Socket.IO 기반으로 SDP Offer/Answer와 ICE Candidate를 중계합니다.
# JWT를 검증해 인증된 클라이언트만 참여할 수 있습니다.

import logging
import socketio

from app.auth.jwt_service import jwt_service

logger = logging.getLogger(__name__)

# Redis Pub/Sub으로 다중 인스턴스 지원
sio = socketio.AsyncServer(
    async_mode="asgi",
    cors_allowed_origins="*",  # Nginx에서 도메인 제한
    logger=False,
    engineio_logger=False,
)

# sid → user 정보 매핑
_connected_users: dict[str, dict] = {}
# username → sid 역방향 조회
_username_to_sid: dict[str, str] = {}


@sio.event
async def connect(sid, environ, auth):
    """연결 시 JWT 검증. 일반 access 토큰과 페어링 토큰(type=pairing) 모두 허용."""
    token = (auth or {}).get("token")
    payload = jwt_service.verify_token(token) if token else None

    if not payload or payload.get("type") not in ("access", "pairing"):
        logger.warning("Signaling: 인증 실패 — sid=%s", sid)
        return False  # 연결 거부

    user_info = {
        "id": payload["sub"],
        "username": payload["username"],
        "role": payload["role"],
        # 페어링 연결일 때 Controller 정보 포함
        "controller_username": payload.get("controller_username"),
        "is_pairing": payload.get("type") == "pairing",
        "device_name": payload.get("device_name"),
    }
    _connected_users[sid] = user_info
    _username_to_sid[payload["username"]] = sid

    logger.info(
        "Signaling: 연결 — %s (sid=%s, pairing=%s)",
        payload["username"], sid, user_info["is_pairing"],
    )
    await sio.emit("connected", {"message": "Signaling 서버에 연결됐습니다."}, to=sid)

    # 페어링 연결이면 Controller에게 에이전트 입장 알림
    if user_info["is_pairing"] and user_info["controller_username"]:
        controller_sid = _username_to_sid.get(user_info["controller_username"])
        if controller_sid:
            await sio.emit("pairing_agent_connected", {
                "agent_username": payload["username"],
                "device_name": payload.get("device_name", "Unknown"),
            }, to=controller_sid)


@sio.event
async def disconnect(sid):
    user = _connected_users.pop(sid, None)
    if user:
        _username_to_sid.pop(user["username"], None)
        logger.info("Signaling: 연결 끊김 — %s", user["username"])


@sio.event
async def agent_ready(sid, data):
    """Agent가 준비됐음을 알림"""
    user = _connected_users.get(sid)
    if user:
        logger.info("Agent 준비 완료 — %s (platform=%s)", user["username"], data.get("platform"))


@sio.event
async def join_session(sid, data):
    """세션 룸 참가"""
    session_id = data.get("session_id")
    if session_id:
        await sio.enter_room(sid, session_id)
        logger.debug("세션 룸 참가 — sid=%s session=%s", sid, session_id)


@sio.event
async def offer(sid, data):
    """SDP Offer 중계 (Controller → Target)"""
    target_username = data.get("target_username")
    target_sid = _username_to_sid.get(target_username)
    if target_sid:
        await sio.emit("offer", data, to=target_sid)


@sio.event
async def answer(sid, data):
    """SDP Answer 중계 (Target → Controller)"""
    controller_username = data.get("controller_username")
    controller_sid = _username_to_sid.get(controller_username)
    if controller_sid:
        await sio.emit("answer", data, to=controller_sid)


@sio.event
async def ice_candidate(sid, data):
    """ICE Candidate 중계"""
    target_username = data.get("target_username") or data.get("controller_username")
    target_sid = _username_to_sid.get(target_username)
    if target_sid:
        await sio.emit("ice_candidate", data, to=target_sid)


@sio.event
async def session_approved(sid, data):
    """피제어측이 연결 승인"""
    session_id = data.get("session_id")
    await sio.emit("session_approved", data, room=session_id, skip_sid=sid)
    logger.info("세션 승인 — session=%s", session_id)


@sio.event
async def session_rejected(sid, data):
    """피제어측이 연결 거부"""
    session_id = data.get("session_id")
    await sio.emit("session_rejected", data, room=session_id, skip_sid=sid)
    logger.info("세션 거부 — session=%s", session_id)


@sio.event
async def session_ended(sid, data):
    """세션 종료"""
    session_id = data.get("session_id")
    await sio.emit("session_ended", data, room=session_id, skip_sid=sid)
    logger.info("세션 종료 — session=%s", session_id)


# ─────────────────────────────────────────────────────────────
# 채팅
# ─────────────────────────────────────────────────────────────

@sio.event
async def chat_message(sid, data):
    """세션 내 채팅 메시지 중계
    data: { session_id, text, sender_name, timestamp }
    """
    user = _connected_users.get(sid)
    if not user:
        return

    session_id = data.get("session_id")
    if not session_id:
        return

    payload = {
        "session_id": session_id,
        "sender_id": user["id"],
        "sender_name": user["username"],
        "text": data.get("text", ""),
        "timestamp": data.get("timestamp"),
    }
    # 같은 룸의 모든 참여자에게 전달 (발신자 포함)
    await sio.emit("chat_message", payload, room=session_id)
    logger.debug("채팅 — session=%s from=%s", session_id, user["username"])


# ─────────────────────────────────────────────────────────────
# 클립보드 동기화
# ─────────────────────────────────────────────────────────────

@sio.event
async def clipboard_sync(sid, data):
    """클립보드 내용 동기화
    data: { session_id, text, target_username | controller_username }
    """
    user = _connected_users.get(sid)
    if not user:
        return

    session_id = data.get("session_id")
    # 수신 대상 (반대쪽 참여자)
    target_username = data.get("target_username") or data.get("controller_username")
    target_sid = _username_to_sid.get(target_username)
    if target_sid:
        await sio.emit("clipboard_sync", data, to=target_sid)
        logger.debug("클립보드 동기화 — session=%s from=%s", session_id, user["username"])


# ─────────────────────────────────────────────────────────────
# 파일 전송 알림 (전송 시작 / 완료를 상대방에게 알림)
# ─────────────────────────────────────────────────────────────

@sio.event
async def file_transfer_notify(sid, data):
    """파일 전송 이벤트 알림
    data: { session_id, event: 'started'|'completed'|'failed', transfer_id, filename, file_size }
    """
    session_id = data.get("session_id")
    if session_id:
        await sio.emit("file_transfer_notify", data, room=session_id, skip_sid=sid)
        logger.debug(
            "파일 전송 알림 — session=%s event=%s file=%s",
            session_id, data.get("event"), data.get("filename"),
        )


# ─────────────────────────────────────────────────────────────
# 다중 모니터 전환 요청
# ─────────────────────────────────────────────────────────────

@sio.event
async def switch_monitor(sid, data):
    """Controller가 Agent에게 모니터 전환 요청
    data: { session_id, target_username, monitor_index }
    """
    target_username = data.get("target_username")
    target_sid = _username_to_sid.get(target_username)
    if target_sid:
        await sio.emit("switch_monitor", data, to=target_sid)
        logger.debug("모니터 전환 요청 — index=%s → %s", data.get("monitor_index"), target_username)
