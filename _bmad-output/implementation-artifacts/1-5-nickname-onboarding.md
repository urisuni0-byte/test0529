# Story 1.5: 닉네임 온보딩

---
baseline_commit: NO_VCS
---

Status: review

## Story

As a new user who just logged in for the first time,
I want to set my nickname before entering the app,
so that other users can identify me.

## Acceptance Criteria

1. 소셜 로그인 후 닉네임이 없는 신규 사용자 → 닉네임 입력 화면 표시 (go_router `/onboarding` redirect 처리함)
2. 닉네임 입력 화면에서 2자 미만/15자 초과/특수문자 입력 시 → 완료 버튼 비활성화 + 오류 메시지
3. 유효한 닉네임 + 완료 탭 → `PATCH /api/v1/users/me` 전송 → DB 저장 → 피드 화면 이동
4. 닉네임 이미 설정된 사용자 → 온보딩 화면 건너뜀 (router redirect로 이미 처리)

## Tasks / Subtasks

- [x] Task 1: Backend — UserUpdate.nickname에 min_length=2 추가 (AC: 3)
  - [x] `backend/app/models.py` UserUpdate.nickname Field에 `min_length=2` 추가
  - [x] 백엔드 테스트: `test_patch_nickname_too_short` — 422 반환 확인
  - [x] 백엔드 테스트: `test_patch_nickname_too_long` — 422 반환 확인
  - [x] 백엔드 테스트: `test_patch_nickname_valid` — 200 반환 + 저장 확인

- [x] Task 2: Flutter — OnboardingScreen 구현 (AC: 1, 2, 3)
  - [x] `lib/features/auth/presentation/onboarding_screen.dart` 재작성
  - [x] TextFormField + 실시간 유효성 검사 (정규식: `^[가-힣a-zA-Z0-9]{2,15}$`)
  - [x] 완료 버튼 비활성화/활성화 상태 관리
  - [x] 유효성 오류 메시지 표시
  - [x] dioProvider로 PATCH /users/me 호출
  - [x] 저장 후 ref.invalidate(authNotifierProvider) → go_router 자동 /feed 이동
  - [x] API 실패 시 스낵바 표시

- [x] Task 3: Flutter 테스트 (AC: 2)
  - [x] `test/features/auth/onboarding_screen_test.dart` 작성
  - [x] 초기 상태: 입력 필드 렌더링, 완료 버튼 비활성화
  - [x] 짧은 닉네임(1자) 입력 → 오류 메시지 + 버튼 비활성화
  - [x] 특수문자 입력 → 오류 메시지 + 버튼 비활성화
  - [x] 유효한 닉네임 입력 → 버튼 활성화
  - [x] 16자 닉네임 입력 → 오류 메시지 + 버튼 비활성화

## Dev Notes

- `dioProvider`: 인증된 Dio (Story 1.3에서 구현)
- `authNotifierProvider`: invalidate 후 needsOnboarding이 false로 변경 → go_router가 /feed로 자동 이동
- 별도 Notifier 불필요 — ConsumerStatefulWidget의 로컬 상태로 충분
- 유효성 검사 정규식: `^[가-힣a-zA-Z0-9]{2,15}$` (한글, 영문자, 숫자만 허용, 2~15자)
