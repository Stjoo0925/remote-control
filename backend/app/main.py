# FastAPI 애플리케이션 진입점
# REST API와 Socket.IO Signaling 서버를 하나의 ASGI 앱으로 통합합니다.

import logging
import socketio
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.config import settings
from app.common.exceptions import register_exception_handlers
from app.common.middleware import RateLimitMiddleware, RequestLoggingMiddleware
from app.auth.router import router as auth_router
from app.sessions.router import router as sessions_router
from app.sessions.signaling import sio
from app.admin.router import router as admin_router
from app.file_transfer.router import router as file_transfer_router
from app.pairing.router import router as pairing_router

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s — %(message)s")

app = FastAPI(
    title="Remote Control API",
    version="0.1.0",
    docs_url="/api/docs" if settings.APP_ENV == "development" else None,
    redoc_url=None,
)

# 미들웨어
app.add_middleware(CORSMiddleware, allow_origins=settings.CORS_ORIGINS, allow_credentials=True, allow_methods=["*"], allow_headers=["*"])
app.add_middleware(RateLimitMiddleware)
app.add_middleware(RequestLoggingMiddleware)

# 예외 핸들러
register_exception_handlers(app)

# 라우터
app.include_router(auth_router)
app.include_router(sessions_router)
app.include_router(admin_router)
app.include_router(file_transfer_router)
app.include_router(pairing_router)


@app.get("/health")
async def health():
    return {"status": "ok", "env": settings.APP_ENV}


# Socket.IO를 /socket.io 경로에 마운트
socket_app = socketio.ASGIApp(sio, other_asgi_app=app)

# uvicorn은 socket_app을 직접 실행:
# uvicorn app.main:socket_app --host 0.0.0.0 --port 8000
