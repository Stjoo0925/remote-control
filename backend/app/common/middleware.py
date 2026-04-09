# 공통 미들웨어
# Rate Limiting, 요청 로깅 등을 처리합니다.

import time
import logging
from fastapi import Request, Response
from starlette.middleware.base import BaseHTTPMiddleware
import redis.asyncio as aioredis

from app.config import settings

logger = logging.getLogger(__name__)

# Rate limit 설정 (엔드포인트별)
RATE_LIMITS = {
    "/api/auth/login": (10, 60),    # 10회/60초
    "/api/sessions": (5, 60),       # 5회/60초
}


class RateLimitMiddleware(BaseHTTPMiddleware):
    def __init__(self, app):
        super().__init__(app)
        self._redis = aioredis.from_url(settings.REDIS_URL, decode_responses=True)

    async def dispatch(self, request: Request, call_next) -> Response:
        path = request.url.path
        limit_config = RATE_LIMITS.get(path)

        if limit_config and request.method == "POST":
            max_requests, window = limit_config
            client_ip = request.client.host if request.client else "unknown"
            key = f"rate_limit:{path}:{client_ip}"

            count = await self._redis.incr(key)
            if count == 1:
                await self._redis.expire(key, window)

            if count > max_requests:
                from fastapi.responses import JSONResponse
                return JSONResponse(
                    status_code=429,
                    content={"detail": "요청이 너무 많습니다. 잠시 후 다시 시도하세요."},
                )

        return await call_next(request)


class RequestLoggingMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next) -> Response:
        start = time.perf_counter()
        response = await call_next(request)
        elapsed = (time.perf_counter() - start) * 1000

        logger.info(
            "%s %s %d %.1fms",
            request.method,
            request.url.path,
            response.status_code,
            elapsed,
        )
        return response
