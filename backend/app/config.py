# 환경 설정 모듈
# pydantic-settings 기반으로 .env 파일과 환경변수를 읽어 설정 객체를 생성합니다.

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=["../../.env", ".env"],
        env_file_encoding="utf-8",
        extra="ignore"
    )

    # 앱
    APP_ENV: str = "development"
    APP_HOST: str = "0.0.0.0"
    APP_PORT: int = 8000

    # DB
    POSTGRES_HOST: str = "localhost"
    POSTGRES_PORT: int = 5432
    POSTGRES_DB: str = "remote_control"
    POSTGRES_USER: str = "rc_user"
    POSTGRES_PASSWORD: str = "change_me"
    DATABASE_URL: str = ""

    @property
    def database_url(self) -> str:
        return (
            f"postgresql+asyncpg://{self.POSTGRES_USER}:{self.POSTGRES_PASSWORD}"
            f"@{self.POSTGRES_HOST}:{self.POSTGRES_PORT}/{self.POSTGRES_DB}"
        )

    # Redis
    REDIS_URL: str = "redis://localhost:6379/0"

    # JWT
    JWT_SECRET_KEY: str = "change_me_to_strong_random_secret"
    JWT_ALGORITHM: str = "HS256"
    JWT_ACCESS_TOKEN_EXPIRE_MINUTES: int = 15
    JWT_REFRESH_TOKEN_EXPIRE_HOURS: int = 8

    # ── 인증 모드 ────────────────────────────────────────────────────────────
    # "local" — 이메일/비밀번호 (기본값, 인터넷 배포 권장)
    # "ldap"  — 사내 Active Directory만 사용
    # "both"  — 로컬 우선, 실패 시 LDAP 시도
    AUTH_MODE: str = "local"

    # 로컬 계정 자유 가입 허용 여부
    ALLOW_REGISTRATION: bool = True

    # ── LDAP (AUTH_MODE=ldap/both 일 때만 사용, 없어도 앱은 정상 동작) ───────
    LDAP_SERVER: str = ""
    LDAP_BASE_DN: str = ""
    LDAP_BIND_DN: str = ""
    LDAP_BIND_PASSWORD: str = ""

    # ── TURN / STUN 서버 ─────────────────────────────────────────────────────
    # 기본값: 구글 공개 STUN (무료, 인터넷 어디서나 사용 가능)
    # 실제 TURN 릴레이가 필요하면 자체 coturn 서버 주소로 변경
    # 예) "turn:my-server.com:3478,stun:stun.l.google.com:19302"
    TURN_SERVERS: str = "stun:stun.l.google.com:19302,stun:stun1.l.google.com:19302"
    TURN_USERNAME: str = ""
    TURN_PASSWORD: str = ""
    TURN_PUBLIC_IP: str = ""

    # ── CORS ────────────────────────────────────────────────────────────────
    # 기본값: 모든 오리진 허용 (TeamViewer처럼 어디서나 접속)
    # 운영 환경에서 도메인을 고정하려면: ["https://your-domain.com"]
    CORS_ORIGINS: list[str] = ["*"]


settings = Settings()
