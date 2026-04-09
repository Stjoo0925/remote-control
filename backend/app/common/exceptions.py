# 공통 예외 클래스 및 FastAPI 예외 핸들러

from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse


class AuthenticationError(Exception):
    def __init__(self, message: str = "인증에 실패했습니다."):
        self.message = message


class AuthorizationError(Exception):
    def __init__(self, message: str = "접근 권한이 없습니다."):
        self.message = message


class NotFoundError(Exception):
    def __init__(self, message: str = "리소스를 찾을 수 없습니다."):
        self.message = message


class RateLimitError(Exception):
    def __init__(self, message: str = "요청이 너무 많습니다. 잠시 후 다시 시도하세요."):
        self.message = message


def register_exception_handlers(app: FastAPI) -> None:
    @app.exception_handler(AuthenticationError)
    async def auth_error_handler(request: Request, exc: AuthenticationError):
        return JSONResponse(status_code=401, content={"detail": exc.message})

    @app.exception_handler(AuthorizationError)
    async def authz_error_handler(request: Request, exc: AuthorizationError):
        return JSONResponse(status_code=403, content={"detail": exc.message})

    @app.exception_handler(NotFoundError)
    async def not_found_handler(request: Request, exc: NotFoundError):
        return JSONResponse(status_code=404, content={"detail": exc.message})

    @app.exception_handler(RateLimitError)
    async def rate_limit_handler(request: Request, exc: RateLimitError):
        return JSONResponse(status_code=429, content={"detail": exc.message})
