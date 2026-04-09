# 사내 원격 제어 시스템

외부 서비스(TeamViewer, AnyDesk) 없이 사내 네트워크에서만 동작하는 자체 원격 지원 솔루션입니다.

---

## 이 프로그램이 뭔가요?

IT 지원팀이 직원 PC를 원격으로 제어할 수 있는 프로그램입니다.  
직원 컴퓨터에 **Agent**를 설치하면, 지원팀이 웹 브라우저에서 바로 접속해 화면을 보고 마우스/키보드를 제어할 수 있습니다.

```
지원팀 (웹 브라우저)  ──────────────────────────────────►  직원 PC (Agent 설치됨)
   React 웹앱                  사내 서버 경유                Flutter 트레이 앱
```

---

## 구성 요소

| 폴더 | 역할 | 기술 |
|------|------|------|
| `backend/` | 서버 — 로그인, 세션 관리, 신호 중계 | Python FastAPI |
| `frontend/` | 제어측 웹 화면 — 원격 뷰어, 채팅, 파일 전송 | React + TypeScript |
| `agent/` | 피제어측 앱 — 직원 PC에 설치 | Flutter + Rust |
| `rc-core/` | 화면 캡처 · 입력 제어 핵심 엔진 | Rust |
| `prisma/` | 데이터베이스 스키마 · 마이그레이션 | Prisma |
| `infra/` | Nginx, coturn, PostgreSQL 설정 파일 | Docker |

---

## 시작하기 전에 — 필요한 프로그램 설치

아래 프로그램들이 없으면 아무것도 실행되지 않습니다. 하나씩 설치하세요.

| 프로그램 | 필요한 곳 | 다운로드 |
|----------|-----------|----------|
| **Docker Desktop** | 서버 전체 실행 | https://www.docker.com/products/docker-desktop |
| **Node.js 20+** | DB 마이그레이션 | https://nodejs.org |
| **Python 3.11+** | 백엔드 개발 시 | https://python.org |

> Docker Desktop 하나만 있어도 서버는 실행할 수 있습니다.

---

## 1단계 — 환경변수 설정 (딱 한 번만 하면 됩니다)

모든 설정은 루트의 `.env` 파일 하나에서 관리합니다.

```bash
# 프로젝트 루트에서 실행
cp .env.example .env
```

`.env` 파일을 메모장이나 VSCode로 열어서, `change_me` 라고 적힌 부분을 실제 값으로 바꿔주세요.

```
# 꼭 바꿔야 하는 것들
POSTGRES_PASSWORD=여기에_강력한_비밀번호
JWT_SECRET_KEY=여기에_긴_랜덤_문자열_최소32자
LDAP_BIND_PASSWORD=사내_LDAP_서비스_계정_비밀번호
TURN_PASSWORD=여기에_TURN서버_비밀번호
```

> JWT_SECRET_KEY 생성 팁: 터미널에서 `openssl rand -hex 32` 실행하면 자동으로 만들어줍니다.

---

## 2단계 — 데이터베이스 마이그레이션 (딱 한 번만)

DB 테이블을 처음 만들 때 실행합니다. 이미 만든 적 있으면 건너뛰어도 됩니다.

```bash
cd prisma
npm install       # Prisma 도구 설치 (처음 한 번만)
npm run migrate:deploy  # DB 테이블 생성
cd ..
```

> PostgreSQL이 실행 중이어야 합니다. 아직 안 켰다면 3단계 먼저 하고 돌아오세요.

---

## 3단계 — Docker로 서버 전체 실행

```bash
# 프로젝트 루트에서
docker compose up -d
```

이것 하나로 아래가 전부 실행됩니다:
- PostgreSQL (데이터베이스)
- Redis (캐시)
- Backend API 서버 (포트 8000)
- Frontend 웹 서버 (포트 3000)
- Nginx (포트 80, 443 — 두 서버 앞에서 연결 받음)
- coturn (WebRTC NAT 통과용)

실행 확인:
```bash
docker compose ps        # 모든 서비스가 Up 상태인지 확인
docker compose logs -f   # 실시간 로그 보기 (Ctrl+C로 종료)
```

멈추기:
```bash
docker compose down      # 서버 중지 (데이터 유지)
docker compose down -v   # 서버 중지 + 데이터도 전부 삭제
```

---

## 개발할 때 — 각 구성 요소 따로 실행하기

### 백엔드 (Python FastAPI)

```bash
cd backend

# 처음 한 번 — 가상환경 만들고 패키지 설치
python -m venv .venv
source .venv/bin/activate   # Windows: .venv\Scripts\activate
pip install -e ".[dev]"

# 서버 실행
uvicorn app.main:socket_app --reload --port 8000
```

API 문서는 브라우저에서 http://localhost:8000/docs 로 확인하세요.

### 프론트엔드 (React)

```bash
cd frontend

npm install   # 처음 한 번만
npm run dev   # 개발 서버 실행 → http://localhost:3000
```

### 테스트 실행

```bash
cd backend
python -m pytest tests/ -v
```

---

## Agent 빌드 — 직원 PC에 설치할 앱 만들기

Agent는 Flutter로 만들어졌습니다. Flutter SDK가 필요합니다.

### Flutter SDK 설치

https://flutter.dev/docs/get-started/install 에서 운영체제에 맞게 설치하세요.

### Agent 빌드

**Windows용 (.exe)**
```bash
cd agent
flutter pub get
flutter build windows
# 결과물: agent/build/windows/x64/runner/Release/
```

**macOS용 (.app)**
```bash
cd agent
flutter pub get
flutter build macos
# 결과물: agent/build/macos/Build/Products/Release/
```

**Linux용**
```bash
cd agent
flutter pub get
flutter build linux
# 결과물: agent/build/linux/x64/release/bundle/
```

**Android용 (.apk)**
```bash
cd agent
flutter pub get
flutter build apk --release
# 결과물: agent/build/app/outputs/flutter-apk/app-release.apk
```

> Android Studio와 Android SDK가 필요합니다: https://developer.android.com/studio

---

## 자주 묻는 질문

**Q: 브라우저에서 접속이 안 돼요**  
A: `docker compose ps` 로 모든 서비스가 `Up` 상태인지 확인하세요. 문제가 있으면 `docker compose logs backend` 로 오류 메시지를 확인하세요.

**Q: 로그인이 안 돼요**  
A: `.env`의 LDAP 설정이 올바른지 확인하세요. 개발 중에는 `APP_ENV=development`로 설정하면 LDAP 없이 테스트할 수 있습니다.

**Q: Docker가 뭔가요?**  
A: 프로그램을 컨테이너라는 상자에 담아서 어떤 컴퓨터에서든 똑같이 실행되게 해주는 도구입니다. Docker Desktop을 설치하고 `docker compose up -d` 만 입력하면 됩니다.

**Q: 포트를 변경하고 싶어요**  
A: `.env` 파일에서 `APP_PORT` 값을 바꾸세요.

---

## 보안 주의사항

- `.env` 파일은 절대 Git에 올리지 마세요. (`.gitignore`에 이미 등록되어 있습니다)
- `change_me`가 남아 있는 상태로 운영 서버에 배포하지 마세요
- SSL 인증서는 `infra/nginx/ssl/` 에 넣어야 합니다 (실제 파일은 Git에 포함 안 됨)

---

## 상세 설계 문서

전체 아키텍처, 기술 선택 이유, 개발 로드맵은 [PLAN.md](./PLAN.md) 를 참고하세요.
