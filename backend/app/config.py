# 환경 설정 모듈
# pydantic-settings 기반으로 .env 파일과 환경변수를 읽어 설정 객체를 생성합니다.

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=["../../.env", ".env"],  # Root .env first, then backend/.env as fallback
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
    DATABASE_URL: str = ""  # Optional: For Prisma migrations

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

    # 인증 모드
    # "ldap"  — 사내 Active Directory만 사용 (기본)
    # "local" — 이메일/비밀번호 로컬 계정만 사용
    # "both"  — LDAP 우선, 실패 시 로컬 계정 시도
    AUTH_MODE: str = "both"

    # 로컬 계정 자유 가입 허용 여부 (AUTH_MODE가 local/both일 때만 적용)
    # False이면 관리자가 계정을 직접 생성해야 함
    ALLOW_REGISTRATION: bool = True

    # LDAP
    LDAP_SERVER: str = "ldap://ldap.corp.local"
    LDAP_BASE_DN: str = "DC=corp,DC=local"
    LDAP_BIND_DN: str = "CN=svc-remote,OU=ServiceAccounts,DC=corp,DC=local"
    LDAP_BIND_PASSWORD: str = "change_me"

    # TURN / STUN 서버 설정
    # 단일 서버 주소 또는 쉼표로 구분된 복수 주소 지원
    # 예) "turn:my-server.example.com:3478,stun:stun.l.google.com:19302"
    TURN_SERVERS: str = "turn:turn.corp.local:3478"
    TURN_USERNAME: str = "remote_user"
    TURN_PASSWORD: str = "change_me"

    # coturn 공개 IP (인터넷 배포 시 설정)
    # 비워 두면 coturn이 자동 감지 시도
    TURN_PUBLIC_IP: str = ""

    # CORS 허용 도메인 (쉼표 없이 list로 관리)
    # 인터넷 서비스 시 실제 도메인 또는 "*"로 설정
    CORS_ORIGINS: list[str] = [
        "https://remote.corp.local",
        "http://localhost:3000",
        "http://localhost:5173",
    ]


settings = Settings()
