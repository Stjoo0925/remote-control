# Remote Control — 사내 원격 제어 시스템

사내 전용 원격 지원 플랫폼입니다. 외부 서비스 의존 없이 사내 네트워크(LAN/VPN) 환경에서 안전하게 운영됩니다.

## 구성 요소

| 디렉토리 | 설명 |
|----------|------|
| `backend/` | FastAPI Signaling & REST API 서버 |
| `frontend/` | React + TypeScript 웹 클라이언트 |
| `agent/` | Python 데스크탑 에이전트 (피제어측 설치) |
| `infra/` | Nginx, coturn, PostgreSQL 설정 |

## 빠른 시작 (개발 환경)

```bash
cp .env.example .env
# .env 파일 편집 후

docker compose -f docker-compose.yml -f docker-compose.dev.yml up
```

## 상세 계획서

[PLAN.md](./PLAN.md) 참조
