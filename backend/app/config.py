# 환경 설정 모듈
# pydantic-settings 기반으로 .env 파일과 환경변수를 읽어 설정 객체를 생성합니다.

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8", extra="ignore")

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

    # LDAP
    LDAP_SERVER: str = "ldap://ldap.corp.local"
    LDAP_BASE_DN: str = "DC=corp,DC=local"
    LDAP_BIND_DN: str = "CN=svc-remote,OU=ServiceAccounts,DC=corp,DC=local"
    LDAP_BIND_PASSWORD: str = "change_me"

    # TURN
    TURN_SERVER: str = "turn:turn.corp.local:3478"
    TURN_USERNAME: str = "remote_user"
    TURN_PASSWORD: str = "change_me"

    # CORS 허용 도메인
    CORS_ORIGINS: list[str] = ["https://remote.corp.local", "http://localhost:3000"]


settings = Settings()
