# 사내 원격 제어 프로그램 설계 계획서

> 작성일: 2026-04-09  
> 목적: 사내 전용 원격 제어 솔루션 자체 구축

---

## 아키텍처 한 줄 요약

```
Rust (핵심 엔진)  +  Flutter (UI/플랫폼 래퍼)  +  FastAPI (서버)
```

- **Rust**: 화면 캡처, 입력 제어, WebRTC, 암호화 — 성능이 중요한 부분
- **Flutter**: UI + 플랫폼 빌드 (Windows / macOS / Linux / Android) — 평소 여기만 작업
- **FastAPI**: Signaling 서버, REST API, 인증
- **연결**: `flutter_rust_bridge` 로 Dart ↔ Rust 자동 바인딩

> Rust를 몰라도 Flutter에서 함수 호출하듯 쓰면 됩니다.  
> 예: `await RustCore.captureScreen()`, `await RustCore.sendMouseEvent(x, y)`

---

## 1. 프로젝트 개요 및 목적

### 목적
- IT 지원팀의 원격 지원 업무 효율화
- 외부 서비스(TeamViewer, AnyDesk) 의존 제거 → 데이터 유출 리스크 차단
- 사내 LDAP/AD 계정 통합 인증
- 모든 세션 감사 로그 기록

### 적용 범위
- 사내 네트워크(LAN/VPN) 환경 전용
- 지원 대상 OS: Windows / macOS / Linux / Android
- iOS: 화면 공유(보기 전용)만 가능 — Apple 정책상 원격 제어 불가

---

## 2. 주요 기능

| 기능 | 설명 | 우선순위 |
|------|------|---------|
| 화면 스트리밍 | 실시간 화면 캡처 및 전송 | P0 |
| 원격 입력 제어 | 키보드/마우스 원격 전달 | P0 |
| 세션 인증 | JWT + LDAP/AD 인증 | P0 |
| 연결 승인 UI | 피제어측 승인/거부 다이얼로그 | P0 |
| 파일 전송 | 양방향 파일 전송 | P1 |
| 채팅 | 세션 내 실시간 채팅 | P1 |
| 세션 감사 로그 | 전체 세션 기록 | P1 |
| 다중 모니터 | 복수 모니터 전환 | P2 |
| 클립보드 동기화 | 양방향 클립보드 | P2 |
| 관리자 대시보드 | 세션 현황 모니터링 | P2 |

---

## 3. 기술 스택

```
┌─────────────────────────────────────────┐
│           Agent (피제어측 앱)             │
│                                         │
│  Flutter (Dart)  ←─flutter_rust_bridge─►│
│  - UI / 승인 다이얼로그                  │  Rust Core (rc-core)
│  - 트레이 앱                            │  - 화면 캡처
│  - 플랫폼 빌드                          │  - 입력 제어
│    Windows / macOS / Linux / Android    │  - WebRTC
│                                         │  - 파일 전송
│                                         │  - AES-256 암호화
└─────────────────────────────────────────┘

┌─────────────────────────────────────────┐
│           Frontend (제어측 웹)           │
│  React 18 + TypeScript                  │
│  WebRTC API + Socket.IO                 │
└─────────────────────────────────────────┘

┌─────────────────────────────────────────┐
│           Backend (서버)                 │
│  Python FastAPI                         │
│  - WebRTC Signaling (Socket.IO)         │
│  - REST API / 인증                      │
│  - LDAP/AD 연동                         │
│  PostgreSQL + Redis + coturn            │
└─────────────────────────────────────────┘
```

### Rust 사용 이유 (몰라도 되는 배경지식)
- 화면 캡처를 초당 30~60프레임으로 안정적으로 처리하려면 GC(가비지컬렉터)가 없는 언어가 필요
- Python은 GIL 때문에 멀티스레드 성능 한계
- Rust는 C++ 수준 성능 + 메모리 안전성 보장
- `flutter_rust_bridge`가 Dart ↔ Rust 코드를 자동으로 연결해줌 → Rust 몰라도 Dart에서 함수 호출만 하면 됨

---

## 4. Rust Core 모듈 (rc-core)

> 이 모듈은 한 번 구현해두면 Flutter에서 블랙박스처럼 사용

```
rc-core/
├── src/
│   ├── capture/          # 화면 캡처
│   │   ├── mod.rs
│   │   ├── windows.rs    # DXGI Desktop Duplication API
│   │   ├── macos.rs      # CGDisplayStream
│   │   ├── linux.rs      # PipeWire / X11 XShmGetImage
│   │   └── android.rs    # MediaProjection (JNI)
│   │
│   ├── input/            # 입력 제어
│   │   ├── mod.rs
│   │   ├── windows.rs    # SendInput API
│   │   ├── macos.rs      # CGEvent
│   │   ├── linux.rs      # uinput / X11 XTest
│   │   └── android.rs    # AccessibilityService (JNI)
│   │
│   ├── webrtc/           # WebRTC 연결
│   │   └── mod.rs        # webrtc-rs 크레이트
│   │
│   ├── crypto/           # 암호화
│   │   └── mod.rs        # AES-256-GCM (ring 크레이트)
│   │
│   └── bridge.rs         # flutter_rust_bridge 공개 API
                           # Flutter에서 호출하는 함수들 정의
```

### Flutter에서 사용 예시 (Dart 코드)

```dart
// Rust 함수를 그냥 호출하면 됨 — Rust 몰라도 OK
final frame = await RustCore.captureScreen(monitorIndex: 0);
await RustCore.sendMouseMove(x: 500, y: 300);
await RustCore.sendKeyEvent(keyCode: 65, pressed: true); // 'A' 키
```

---

## 5. Flutter Agent 구조

```
agent/
├── lib/
│   ├── main.dart
│   ├── src/
│   │   ├── tray/               # 시스템 트레이
│   │   │   └── tray_app.dart
│   │   │
│   │   ├── consent/            # 연결 승인 다이얼로그
│   │   │   └── consent_dialog.dart
│   │   │
│   │   ├── session/            # 세션 관리
│   │   │   ├── session_manager.dart
│   │   │   └── signaling_client.dart  # 서버 WebSocket 연결
│   │   │
│   │   ├── stream/             # 화면 스트리밍 (Rust 호출)
│   │   │   └── screen_streamer.dart
│   │   │
│   │   └── settings/           # 서버 주소, 계정 설정 UI
│   │       └── settings_page.dart
│   │
│   └── bridge/                 # 자동 생성됨 (flutter_rust_bridge)
│       └── rust_core.dart      # ← 여기 함수들만 호출하면 됨
│
├── rust/                       # rc-core Rust 코드
│   └── (심볼릭 링크 or 서브모듈)
│
└── pubspec.yaml
```

---

## 6. 시스템 아키텍처

```
┌──────────────────────────────────────────────────────────────┐
│                     사내 네트워크 (VPN 포함)                   │
│                                                              │
│  ┌─────────────────┐   WebRTC P2P   ┌────────────────────┐  │
│  │  Controller     │◄──────────────►│  Agent             │  │
│  │  (웹 브라우저)   │                │  Flutter + Rust     │  │
│  │  React Web App  │                │  Win/Mac/Linux/Android│ │
│  └────────┬────────┘                └─────────┬──────────┘  │
│           │ HTTPS/WSS                         │ HTTPS/WSS   │
│           ▼                                   ▼             │
│  ┌──────────────────────────────────────────────────────┐   │
│  │               Nginx (TLS 1.3 종단)                    │   │
│  └──────────────────────┬───────────────────────────────┘   │
│                         │                                    │
│              ┌──────────▼──────────┐                        │
│              │    FastAPI Server    │                        │
│              │  Signaling / Auth   │◄──► Redis              │
│              │  REST API           │◄──► PostgreSQL         │
│              │  LDAP 연동          │◄──► LDAP/AD            │
│              └─────────────────────┘                        │
│                                                              │
│              ┌──────────────────────┐                       │
│              │  coturn (TURN/STUN)  │  ← NAT 통과용         │
│              └──────────────────────┘                       │
└──────────────────────────────────────────────────────────────┘
```

---

## 7. 보안

### 인증
- LDAP/AD 연동 (기존 사내 계정 사용)
- JWT Access Token 15분 / Refresh Token 8시간
- 피제어측 명시적 승인 없이 연결 불가
- Ctrl+Alt+F12: 즉시 강제 종료

### 암호화
| 구간 | 방식 |
|------|------|
| 전송 전체 | TLS 1.3 |
| WebRTC 미디어 | DTLS-SRTP (기본 내장) |
| 파일 전송 | AES-256-GCM (Rust crypto 모듈) |

### 감사 로그
- 로그인, 세션 시작/종료, 파일 전송 전량 기록
- 보관 1년, 해시 체인 위변조 감지

---

## 8. 개발 로드맵

### Phase 1 — 서버 + 인증 (4주)
- [ ] Docker Compose 환경 (PostgreSQL, Redis, coturn, Nginx)
- [ ] FastAPI + LDAP/AD 인증 + JWT
- [ ] WebRTC Signaling (Socket.IO)
- [ ] React 로그인 + 세션 UI

### Phase 2 — Rust Core 구현 (6주)
- [ ] `rc-core` 크레이트 기반 구조
- [ ] 화면 캡처 (Windows DXGI → 우선, 타 플랫폼 순차)
- [ ] 입력 제어 (Windows SendInput → 우선)
- [ ] WebRTC 연결 (webrtc-rs)
- [ ] `flutter_rust_bridge` 바인딩 생성

### Phase 3 — Flutter Agent UI (4주)
- [ ] 트레이 앱, 승인 다이얼로그
- [ ] 세션 설정 화면 (서버 주소, 계정)
- [ ] Android 빌드 검증
- [ ] 긴급 종료 단축키

### Phase 4 — 부가 기능 (4주)
- [ ] 파일 전송 + 채팅 + 클립보드
- [ ] 관리자 대시보드, 감사 로그 뷰어
- [ ] 다중 모니터 지원

### Phase 5 — QA & 배포 (4주)
- [ ] 보안 점검, 부하 테스트
- [ ] 플랫폼별 빌드 패키지 (installer)
- [ ] 사용자/관리자 매뉴얼

> **총 기간: 약 22주**  
> MVP 전략: Phase 1-2-3 완료 후 Windows 우선 출시 → 타 플랫폼 순차 추가

---

## 9. 디렉토리 구조

```
remote-control/
├── PLAN.md
├── docker-compose.yml
├── .env.example
│
├── rc-core/                        # Rust 핵심 엔진
│   ├── Cargo.toml
│   └── src/
│       ├── lib.rs
│       ├── bridge.rs               # Flutter 공개 API
│       ├── capture/                # 화면 캡처 (플랫폼별)
│       ├── input/                  # 입력 제어 (플랫폼별)
│       ├── webrtc/                 # WebRTC 연결
│       └── crypto/                 # AES-256-GCM
│
├── agent/                          # Flutter Agent 앱
│   ├── pubspec.yaml
│   ├── lib/
│   │   ├── main.dart
│   │   └── src/
│   │       ├── tray/
│   │       ├── consent/
│   │       ├── session/
│   │       ├── stream/
│   │       └── settings/
│   └── bridge/                     # 자동 생성 (flutter_rust_bridge)
│
├── backend/                        # FastAPI 서버
│   ├── Dockerfile
│   ├── pyproject.toml
│   └── app/
│       ├── main.py
│       ├── auth/
│       ├── sessions/
│       ├── file_transfer/
│       ├── admin/
│       └── common/
│
├── frontend/                       # React 웹 (제어측)
│   ├── package.json
│   └── src/
│       ├── features/
│       │   ├── auth/
│       │   ├── session/
│       │   ├── viewer/
│       │   ├── file-transfer/
│       │   ├── chat/
│       │   └── admin/
│       └── shared/
│
└── infra/
    ├── nginx/
    ├── coturn/
    └── postgres/
```
