# Story 1.4: 동네 선택 API & Flutter UI

---
baseline_commit: NO_VCS
---

Status: review

## Story

As an authenticated user,
I want to select my neighborhood from a list and have my feed filtered accordingly,
so that I see listings from my local area.

## Acceptance Criteria

1. 인증된 사용자가 동네 설정 화면에 진입할 때 `GET /api/v1/neighborhoods`를 호출하면 시/구/동 계층 구조의 동네 목록이 반환된다
2. 사용자가 목록에서 동(dong)을 선택하고 저장할 때 `PATCH /api/v1/users/me`로 `neighborhood_id`를 전송하면 DB에 저장되고 피드가 해당 동네 기준으로 즉시 필터링된다
3. 동네 미설정 사용자가 글쓰기를 시도할 때 동네 설정 화면으로 먼저 안내된다
4. 설정된 동네를 변경할 때 다른 동네를 선택하고 저장하면 인증 상태가 갱신되어 피드가 새 동네 기준으로 즉시 갱신된다

## Tasks / Subtasks

- [x] Task 1: Backend — GET /neighborhoods 엔드포인트 (AC: 1)
  - [x] `app/api/routes/neighborhoods.py` 생성 — 공개 엔드포인트
  - [x] Neighborhood 응답 스키마: flat list `{"items": [{"id", "name", "parent_id", "level"}]}`
  - [x] `app/api/main.py` 라우터 등록
  - [x] 백엔드 테스트: `tests/api/routes/test_neighborhoods.py`

- [x] Task 2: Backend — PATCH /users/me neighborhood_id 검증 (AC: 2)
  - [x] `PATCH /api/v1/users/me`에서 `neighborhood_id`가 존재하는 id인지 검증 (없는 id면 422)
  - [x] 기존 `update_user_me` 라우터 수정

- [x] Task 3: Flutter — NeighborhoodModel + Repository (AC: 1, 2)
  - [x] `lib/features/feed/data/models/neighborhood_model.dart`
  - [x] `lib/features/feed/data/neighborhood_repository.dart` — GET neighborhoods, PATCH users/me

- [x] Task 4: Flutter — NeighborhoodNotifier (AC: 1, 2, 4)
  - [x] `lib/features/feed/domain/neighborhood_notifier.dart` — 선택 상태 관리 (도시→구→동 cascade)
  - [x] 저장 후 `authNotifierProvider` 무효화 → 사용자 정보 자동 갱신

- [x] Task 5: Flutter — NeighborhoodPickerScreen (AC: 1, 2, 3, 4)
  - [x] `lib/features/feed/presentation/neighborhood_picker_screen.dart`
  - [x] 3단계 cascade picker: 도시 → 구 → 동
  - [x] 저장 버튼 비활성화 (동 미선택 시)

- [x] Task 6: Flutter — 라우팅 + 가드 (AC: 3)
  - [x] `/neighborhood` 경로 추가 (`app_router.dart`)
  - [x] `lib/features/feed/presentation/neighborhood_guard.dart` — `requireNeighborhood()` 유틸
  - [x] `UserModel.hasNeighborhood` getter 추가
  - [x] `FeedScreen` placeholder에 글쓰기 FAB + 가드 데모 추가

- [x] Task 7: 테스트 (AC: 1, 2)
  - [x] `test/features/feed/neighborhood_picker_screen_test.dart` — 위젯 3개 + 상태 단위 테스트 8개

## Dev Agent Record

### Agent Model Used

claude-sonnet-4-6

### Completion Notes List

- 백엔드 25/25 통과, Flutter 15/15 통과, flutter analyze 이슈 없음
- **GET /neighborhoods**: 공개 엔드포인트, flat list 응답, 기존 `Neighborhood` SQLModel 재사용
- **PATCH /users/me 검증**: 존재하지 않는 `neighborhood_id` → `session.get(Neighborhood, id)` 로 검증 후 422
- **Flutter 패턴**: `NeighborhoodPickerState` value object로 cascade dropdown 상태 완전 캡슐화
- **저장 후 갱신**: `ref.invalidate(authNotifierProvider)` → `_resolveInitialState` 재실행 → `getMe` 호출로 최신 UserModel 반영
- **가드 패턴**: `requireNeighborhood(context, ref, onHasNeighborhood: ...)` named parameter로 구현
- `DropdownButtonFormField.value` deprecated → `initialValue`로 교체

### File List

**Backend:**
- `backend/app/api/routes/neighborhoods.py` (신규)
- `backend/app/api/routes/users.py` (수정 — neighborhood_id 검증 추가)
- `backend/app/api/main.py` (수정 — neighborhoods 라우터 등록)
- `backend/tests/api/routes/test_neighborhoods.py` (신규)

**Flutter:**
- `mobile/lib/features/auth/data/models/user_model.dart` (수정 — hasNeighborhood getter)
- `mobile/lib/features/feed/data/models/neighborhood_model.dart` (신규)
- `mobile/lib/features/feed/data/neighborhood_repository.dart` (신규)
- `mobile/lib/features/feed/domain/neighborhood_notifier.dart` (신규)
- `mobile/lib/features/feed/presentation/neighborhood_picker_screen.dart` (신규)
- `mobile/lib/features/feed/presentation/neighborhood_guard.dart` (신규)
- `mobile/lib/features/feed/presentation/feed_screen.dart` (수정 — 글쓰기 FAB)
- `mobile/lib/core/router/app_router.dart` (수정 — /neighborhood 경로)
- `mobile/test/features/feed/neighborhood_picker_screen_test.dart` (신규)
