# 커밋 메시지 규칙 (Conventional Commits)

버전은 커밋 메시지에 따라 **자동으로** 올라갑니다.

## 형식

```
<type>: <설명>
```

## 타입별 버전 영향

| 타입 | 설명 | 버전 변화 |
|------|------|---------|
| `feat` | 새 기능 추가 | **MINOR** ↑ (0.1.0 → 0.2.0) |
| `fix` | 버그 수정 | **PATCH** ↑ (0.1.0 → 0.1.1) |
| `perf` | 성능 개선 | **PATCH** ↑ |
| `security` | 보안 패치 | **PATCH** ↑ |
| `feat!` | 하위 호환 깨지는 변경 | **MAJOR** ↑ (0.1.0 → 1.0.0) |
| `refactor` | 리팩토링 (기능 변화 없음) | 변화 없음 |
| `docs` | 문서 수정 | 변화 없음 |
| `chore` | 기타 (설정, 빌드 등) | 변화 없음 |
| `ci` | CI/CD 수정 | 변화 없음 |

## 예시

```bash
# 새 기능 → MINOR
git commit -m "feat: 파일 전송 기능 추가"

# 버그 수정 → PATCH
git commit -m "fix: Android에서 화면 캡처 끊김 현상 수정"

# 보안 패치 → PATCH
git commit -m "security: JWT 토큰 만료 검증 로직 강화"

# 하위 호환 깨지는 변경 → MAJOR
git commit -m "feat!: Agent-서버 통신 프로토콜 v2로 변경"

# 버전에 영향 없음
git commit -m "chore: 의존성 업데이트"
git commit -m "docs: README 설치 가이드 추가"
```

## 자동화 흐름

```
main 브랜치에 push
    ↓
GitHub Actions 실행
    ↓
커밋 메시지 분석
    ↓
Release PR 자동 생성 (버전 + CHANGELOG 포함)
    ↓
PR 머지
    ↓
GitHub Release + 태그 자동 생성
```
