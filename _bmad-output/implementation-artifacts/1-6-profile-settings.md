# Story 1.6 — 프로필 편집 & 설정 화면

**Status:** review

## Summary
Implement a settings screen where authenticated users can edit their nickname and log out.

## Acceptance Criteria
1. 인증된 사용자가 설정 화면에 진입하면 현재 닉네임과 로그아웃 버튼이 표시된다
2. 사용자가 닉네임을 변경하고 저장하면 `PATCH /api/v1/users/me`로 변경된 닉네임을 전송하고 DB에 저장되며 화면에 즉시 반영된다
3. 사용자가 로그아웃 버튼을 탭하고 확인하면 JWT가 삭제되고 로그인 화면으로 이동한다
4. 인증된 사용자는 설정 화면에서 프로필 편집과 로그아웃에 접근할 수 있다

## Files Changed
- `lib/features/auth/presentation/nickname_validator.dart` — NEW: shared validation utility
- `lib/features/auth/presentation/onboarding_screen.dart` — UPDATE: use shared validator
- `lib/features/auth/presentation/settings_screen.dart` — NEW: settings/profile screen
- `lib/core/router/app_router.dart` — UPDATE: add /settings route
- `test/features/auth/settings_screen_test.dart` — NEW: widget tests
