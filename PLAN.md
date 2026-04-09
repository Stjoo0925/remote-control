# 사내 원격 제어 프로그램 설계 계획서

> 작성일: 2026-04-09  
> 목적: 사내 전용 원격 제어 솔루션 자체 구축

---

## 1. 프로젝트 개요 및 목적

### 개요
사내 전용 원격 제어 솔루션으로, 외부 상용 서비스(TeamViewer, AnyDesk 등)에 대한 의존성을 제거하고 기업 내부 보안 정책에 완전히 부합하는 자체 원격 지원 플랫폼을 구축합니다.

### 목적
- IT 지원팀의 원격 지원 업무 효율화
- 외부 서비스 사용에 따른 데이터 유출 리스크 제거
- 사내 Active Directory / LDAP 계정과 통합된 단일 인증 체계 구축
- 모든 원격 세션 로그 기록 및 감사(Audit) 추적 가능

### 적용 범위
- 사내 네트워크(LAN/VPN) 환경에서만 동작
- IT 지원 담당자(Controller) ↔ 일반 직원(Target) 간 원격 세션
- Windows / macOS / Linux 크로스 플랫폼 지원

---

## 2. 주요 기능 목록

| 기능 | 설명 | 우선순위 |
|------|------|---------|
| 화면 공유 | 실시간 대상 PC 화면 스트리밍 (WebRTC) | P0 |
| 원격 입력 제어 | 키보드/마우스 이벤트 원격 전달 | P0 |
| 세션 인증 | JWT + LDAP/AD 기반 사용자 인증 | P0 |
| 파일 전송 | 컨트롤러 ↔ 대상 간 양방향 파일 전송 | P1 |
| 채팅 | 세션 내 실시간 텍스트 채팅 | P1 |
| 세션 기록 | 모든 세션 메타데이터 로깅 및 감사 | P1 |
| 다중 모니터 | 복수 모니터 전환 지원 | P2 |
| 클립보드 동기화 | 양방향 클립보드 공유 | P2 |
| 세션 녹화 | 화면 세션 영상 녹화 및 저장 | P2 |
| 관리자 대시보드 | 세션 현황 모니터링 및 사용자 관리 | P2 |

### 보조 기능
- 원격 재부팅 (권한 필요)
- 화면 전용 관람 모드 (제어 없이 화면만 공유)
- 연결 요청/승인 알림
- 세션 강제 종료 (관리자 권한)

---

## 3. 기술 스택

```
[Frontend]
- React 18 + TypeScript 5
- Vite (빌드 도구)
- TailwindCSS + shadcn/ui (UI 컴포넌트)
- Zustand (클라이언트 상태 관리)
- WebRTC API (화면 스트리밍)
- Socket.IO Client (WebSocket)

[Backend - Signaling & API Server]
- Python 3.11 + FastAPI
- SQLAlchemy 2.0 + Alembic (ORM/마이그레이션)
- python-socketio (WebSocket)
- python-ldap3 (LDAP/AD 연동)
- PyJWT + passlib (인증/암호화)
- Redis (세션 캐시, Pub/Sub)
- Celery (비동기 작업)

[Desktop Agent]
- Python + PyInstaller (크로스플랫폼 실행파일)
- mss (화면 캡처)
- pynput (키보드/마우스 제어)
- aiortc (WebRTC)

[Database]
- PostgreSQL 15 (주 데이터베이스)
- Redis 7 (세션/캐시)

[Infrastructure]
- TURN/STUN Server: coturn (사내 전용)
- Nginx (리버스 프록시, TLS 종단)
- Docker + Docker Compose

[보안]
- TLS 1.3 (전송 암호화)
- DTLS-SRTP (WebRTC 미디어 암호화)
- AES-256-GCM (파일 전송 추가 암호화)
```

---

## 4. 시스템 아키텍처

```
┌─────────────────────────────────────────────────────────────────┐
│                        사내 네트워크 (VPN 포함)                    │
│                                                                  │
│  ┌──────────────┐    WebRTC P2P    ┌──────────────────────────┐  │
│  │  Controller  │◄────(직접연결)───►│    Target Desktop Agent  │  │
│  │  (Web Browser│                  │    (Python Agent)        │  │
│  │  React App)  │                  │    - 화면 캡처           │  │
│  └──────┬───────┘                  │    - 입력 이벤트 처리    │  │
│         │                          └──────────┬───────────────┘  │
│         │ HTTPS/WSS                           │ HTTPS/WSS        │
│         ▼                                     ▼                  │
│  ┌──────────────────────────────────────────────────────────┐    │
│  │                    Nginx (TLS 종단)                       │    │
│  │                 내부 도메인: remote.corp.local            │    │
│  └──────────────┬─────────────────────────────┬────────────┘    │
│                 │                             │                  │
│         ┌───────▼────────┐          ┌────────▼────────┐         │
│         │  FastAPI       │          │   coturn         │         │
│         │  Signaling &   │          │   TURN/STUN      │         │
│         │  API Server    │          │   (NAT 통과용)   │         │
│         └───────┬────────┘          └─────────────────┘         │
│                 │                                                 │
│         ┌───────▼────────┐          ┌─────────────────┐         │
│         │  PostgreSQL    │          │  LDAP/AD 서버    │         │
│         │  (영구 저장)   │◄────────►│  (사내 계정 연동)│         │
│         └────────────────┘          └─────────────────┘         │
└─────────────────────────────────────────────────────────────────┘
```

### WebRTC 연결 흐름

```
Controller(Browser)          Signaling Server          Target(Agent)
      │                            │                        │
      │── 로그인 (JWT 발급) ───────►│                        │
      │── 세션 생성 요청 ──────────►│                        │
      │                            │── 연결 요청 알림 ──────►│
      │                            │                        │── 사용자 승인
      │                            │◄─ 승인 응답 ────────────│
      │◄─ 세션 승인 알림 ──────────│                        │
      │── SDP Offer ───────────────►│── SDP Offer ──────────►│
      │◄─ SDP Answer ──────────────│◄─ SDP Answer ───────────│
      │── ICE Candidate ───────────►│── ICE Candidate ──────►│
      │◄══════════ WebRTC P2P 직접 연결 (DTLS-SRTP 암호화) ══►│
```

---

## 5. 핵심 모듈 구성

### Backend
- **auth**: LDAP/AD 연동, JWT 발급, RBAC
- **sessions**: 세션 생명주기, WebRTC Signaling, 감사 로그
- **file_transfer**: 청크 전송, AES-256-GCM 암호화
- **admin**: 대시보드, 사용자 관리, 감사 로그 조회
- **notifications**: 실시간 알림, 이메일 알림 (Celery)

### Frontend
- **auth**: 로그인 페이지, AuthContext, JWT 자동 갱신
- **session**: 세션 목록, 연결 요청 승인 모달
- **viewer**: 화면 렌더러(Canvas), 입력 캡처, 툴바
- **file-transfer**: 드래그앤드롭, 진행률 표시
- **chat**: DataChannel 기반 실시간 채팅
- **admin**: 세션 모니터링, 감사 로그, 역할 관리

### Desktop Agent
- **capture**: mss 화면 캡처, 델타 압축, 동적 품질 조절
- **input**: pynput 입력 처리, 좌표 정규화
- **webrtc**: Peer Connection, DataChannel 관리
- **security**: 승인 다이얼로그, 긴급 종료 단축키(Ctrl+Alt+F12)
- **tray**: 시스템 트레이 앱, 연결 상태 표시

---

## 6. 보안 고려사항

### 인증 레이어
1. **네트워크**: 사내 IP 대역 허용 + VPN 필수
2. **사용자 인증**: LDAP/AD + JWT (Access 15분 / Refresh 8시간)
3. **세션 인증**: 단회용 세션 토큰 + 대상 사용자 명시적 동의
4. **RBAC**: ROLE_ADMIN / ROLE_SUPPORT / ROLE_USER

### 암호화

| 구간 | 방식 |
|------|------|
| 브라우저 ↔ Nginx | TLS 1.3 |
| WebRTC 미디어 | DTLS 1.2 + SRTP |
| 파일 전송 페이로드 | AES-256-GCM (추가 레이어) |
| DB 민감 데이터 | pgcrypto 컬럼 암호화 |

### 감사 로그
- 로그인 시도, 세션 시작/종료, 파일 전송, 관리자 작업 전량 기록
- 보관 기간: 1년
- 해시 체인 방식 위변조 감지

### 기타
- CSRF, XSS, Rate Limiting 방어
- 세션 화면 워터마크 (사용자 ID 오버레이)
- 에이전트 코드 서명 (내부 CA)
- Ctrl+Alt+F12: Target 즉시 강제 종료

---

## 7. 개발 로드맵

### Phase 1 — 기반 인프라 (4주)
- [ ] 모노레포 구조, Docker Compose 환경
- [ ] Nginx TLS, coturn TURN 서버
- [ ] LDAP/AD 연동 + JWT 인증 시스템
- [ ] React 로그인 페이지

### Phase 2 — 핵심 기능 (8주)
- [ ] WebRTC Signaling 서버 (Socket.IO)
- [ ] 화면 스트리밍 (mss → VideoTrack → Canvas)
- [ ] 원격 입력 제어 (pynput → DataChannel → Browser)
- [ ] 연결 승인 UI (트레이 앱 다이얼로그)

### Phase 3 — 부가 기능 (4주)
- [ ] 파일 전송 + 채팅 + 클립보드 동기화
- [ ] 관리자 대시보드 + 감사 로그 뷰어
- [ ] 세션 녹화 (FFmpeg)

### Phase 4 — QA & 배포 (4주)
- [ ] 단위/통합/보안/부하 테스트
- [ ] PyInstaller 에이전트 빌드 패키지
- [ ] 운영 모니터링 (Prometheus + Grafana)
- [ ] 사용자/관리자 매뉴얼

> **총 기간: 약 20주 (5개월)**  
> MVP 전략: Phase 1-2만 12주에 출시 후 Phase 3-4 순차 추가

---

## 8. 디렉토리 구조

```
remote-control/
├── docker-compose.yml
├── docker-compose.dev.yml
├── .env.example
├── PLAN.md
│
├── infra/
│   ├── nginx/
│   ├── coturn/
│   └── postgres/
│
├── backend/                        # FastAPI
│   ├── Dockerfile
│   ├── pyproject.toml
│   ├── alembic/
│   └── app/
│       ├── main.py
│       ├── config.py
│       ├── auth/
│       ├── sessions/
│       ├── file_transfer/
│       ├── admin/
│       ├── notifications/
│       └── common/
│
├── frontend/                       # React + TypeScript
│   ├── Dockerfile
│   ├── package.json
│   ├── vite.config.ts
│   └── src/
│       ├── features/
│       │   ├── auth/
│       │   ├── session/
│       │   ├── viewer/
│       │   ├── file-transfer/
│       │   ├── chat/
│       │   └── admin/
│       ├── shared/
│       └── store/
│
├── agent/                          # Python Desktop Agent
│   ├── pyproject.toml
│   ├── build.py
│   └── src/
│       ├── main.py
│       ├── capture/
│       ├── input/
│       ├── webrtc/
│       ├── security/
│       └── tray/
│
└── scripts/
    ├── deploy/
    └── dev/
```
