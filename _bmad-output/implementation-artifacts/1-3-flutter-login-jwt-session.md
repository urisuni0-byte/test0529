# Story 1.3: Flutter 로그인 화면 & JWT 세션 관리

---
baseline_commit: NO_VCS
---

Status: review

## Story

As an unauthenticated user,
I want to log in with Google from the Flutter app and stay logged in across restarts,
so that I don't have to authenticate every time I open the app.

## Acceptance Criteria

1. 앱을 처음 실행했을 때 저장된 유효한 JWT가 없으면 로그인 화면이 표시되고 "구글로 로그인" 버튼이 활성화된다
2. 로그인 화면에서 구글 로그인 버튼을 탭하면 Google 인증 성공 후 FastAPI에서 토큰을 받아 `flutter_secure_storage`에 저장한다. 닉네임 미설정 사용자는 닉네임 온보딩 화면으로, 설정된 사용자는 피드 화면으로 이동한다
3. 앱 재실행 시 저장된 access_token이 만료되었을 때 refresh_token이 유효하면 Dio 인터셉터가 자동으로 토큰을 갱신하고 원래 요청을 재시도한다. refresh_token도 만료된 경우 로그인 화면으로 이동한다
4. 비인증 상태에서 글쓰기·관심·채팅하기를 시도할 때 로그인 유도 팝업이 표시된다
5. 앱 시작 시 저장된 access_token이 유효하면 로그인 화면을 건너뛰고 피드 화면으로 진입한다

## Tasks / Subtasks

- [x] Task 1: pubspec.yaml 의존성 추가 (AC: all)
  - [x] 프로덕션 의존성: flutter_riverpod, riverpod_annotation, google_sign_in, flutter_secure_storage, dio, go_router, jwt_decoder
  - [x] 개발 의존성: riverpod_generator, build_runner, json_serializable, json_annotation
  - [x] `flutter pub get` 실행

- [x] Task 2: `lib/core/` 레이어 구축 (AC: 3, 5)
  - [x] `lib/core/storage/secure_storage.dart` — SecureStorageService (access/refresh 토큰 저장·조회·삭제)
  - [x] `lib/core/network/api_client.dart` — Dio 인스턴스, baseUrl, 기본 헤더
  - [x] `lib/core/network/auth_interceptor.dart` — JWT 자동 갱신 인터셉터 (401 감지 → refresh → 재시도, 동시 요청 Lock 처리)
  - [x] `lib/core/error/app_error.dart` — AppError 클래스 (DioException 변환)
  - [x] `lib/core/constants.dart` — API base URL 등 상수

- [x] Task 3: Auth Feature — Data Layer (AC: 2)
  - [x] `lib/features/auth/data/auth_repository.dart` — AuthRepository (googleLogin, refreshToken, logout)
  - [x] `lib/features/auth/data/models/auth_token.dart` — AuthToken 모델 (access_token, refresh_token)
  - [x] `lib/features/auth/data/models/user_model.dart` — UserModel (id, email, nickname, profile_image_url, role)

- [x] Task 4: Auth Feature — Domain Layer (AC: 1, 2, 3, 5)
  - [x] `lib/features/auth/domain/auth_notifier.dart` — AuthNotifier (Riverpod AsyncNotifier)
  - [x] `lib/features/auth/domain/auth_state.dart` — AuthState sealed class (Authenticated/Unauthenticated)

- [x] Task 5: Auth Feature — Presentation Layer (AC: 1, 2, 4)
  - [x] `lib/features/auth/presentation/login_screen.dart` — 구글 로그인 버튼 화면
  - [x] `lib/features/auth/presentation/widgets/google_sign_in_button.dart` — 구글 브랜드 가이드라인 버튼

- [x] Task 6: 라우팅 설정 (AC: 1, 2, 5)
  - [x] `lib/core/router/app_router.dart` — go_router + _RouterNotifier(refreshListenable)
  - [x] `lib/core/router/auth_guard.dart` — requireAuth() 유틸리티 함수

- [x] Task 7: `lib/main.dart` 전면 재작성 (AC: all)
  - [x] ProviderScope로 앱 래핑
  - [x] go_router 연결
  - [x] 앱 시작 시 토큰 유효성 체크 로직 (splash → 라우팅 결정)

- [x] Task 8: Android/iOS 네이티브 설정 (AC: 2)
  - [x] `android/app/build.gradle.kts`: minSdk = 21
  - [x] `android/app/src/main/AndroidManifest.xml`: INTERNET 권한 추가
  - [x] `android/app/google-services.json`: 플레이스홀더 생성
  - [x] `ios/Runner/Info.plist`: CFBundleURLTypes (Google Sign In URL scheme) 추가

- [x] Task 9: 기본 위젯 테스트 (AC: 1)
  - [x] `test/features/auth/login_screen_test.dart` — 3개 테스트 (렌더링, 탭, 로딩)

## Dev Agent Record

### Agent Model Used

claude-sonnet-4-6

### Debug Log References

- `__` → `_` 린트 이슈: go_router builder 파라미터 명시적 네이밍으로 해결
- `prefer_initializing_formals`: named parameter에서 private 필드는 Dart 문법상 불가 → `// ignore` 처리
- `annotate_overrides`: sealed class에서 `Authenticated.user`가 `AuthState.user` 오버라이드 → `@override final` 선언
- `body_might_complete_normally_catch_error`: `catchError` 대신 try-catch로 변경

### Completion Notes List

- 4/4 widget tests 통과, flutter analyze 이슈 없음
- **Riverpod 패턴**: `AsyncNotifierProvider` 수동 선언 (build_runner 없이 동일 기능)
- **go_router + Riverpod 브릿지**: `_RouterNotifier extends ChangeNotifier` + `refreshListenable` 패턴 사용. 라우터 재생성 없이 auth 상태 변경 시 redirect 트리거.
- **AuthInterceptor lock**: `_isRefreshing` bool + `Completer` 목록으로 동시 갱신 요청 직렬화
- **Dio 분리**: refreshDio(auth 전용, 무인터셉터) / dioProvider(인증된 API 전용) — 순환 의존성 방지
- **닉네임 체크**: 로그인 후 `GET /api/v1/users/me` 호출, `UserModel.hasNickname`으로 온보딩 필요 여부 결정
- **Placeholder 화면**: FeedScreen, OnboardingScreen — Story 2.2, 1.5에서 구현 예정

### Change Log

- 코드 리뷰 수정 (2026-05-30): 10건 수정
  - onSignedOut 잘못된 provider → authSignedOutSignalProvider 시그널 패턴
  - onRequest/onError void async → Future<void> + try/finally completer 보장
  - _signOut() deleteAll() 미await → async + await 적용
  - JwtDecoder.isExpired FormatException 미처리 → try/catch 추가
  - saveTokens Future.wait 병렬 → 순차 저장
  - redirect AsyncError 분기 누락 → hasError 가드 추가
  - GoRouter dispose 누락 → ref.onDispose 추가
  - 토큰 저장 /users/me 이전 → /users/me 성공 후 저장으로 변경

### File List

- `mobile/pubspec.yaml` (수정)
- `mobile/lib/main.dart` (전면 재작성)
- `mobile/lib/core/constants.dart` (신규)
- `mobile/lib/core/storage/secure_storage.dart` (신규)
- `mobile/lib/core/network/api_client.dart` (신규)
- `mobile/lib/core/network/auth_interceptor.dart` (신규)
- `mobile/lib/core/error/app_error.dart` (신규)
- `mobile/lib/core/router/app_router.dart` (신규)
- `mobile/lib/core/router/auth_guard.dart` (신규)
- `mobile/lib/features/auth/data/models/auth_token.dart` (신규)
- `mobile/lib/features/auth/data/models/user_model.dart` (신규)
- `mobile/lib/features/auth/data/auth_repository.dart` (신규)
- `mobile/lib/features/auth/domain/auth_state.dart` (신규)
- `mobile/lib/features/auth/domain/auth_notifier.dart` (신규)
- `mobile/lib/features/auth/presentation/login_screen.dart` (신규)
- `mobile/lib/features/auth/presentation/onboarding_screen.dart` (신규, placeholder)
- `mobile/lib/features/auth/presentation/widgets/google_sign_in_button.dart` (신규)
- `mobile/lib/features/feed/presentation/feed_screen.dart` (신규, placeholder)
- `mobile/lib/features/splash/splash_screen.dart` (신규)
- `mobile/android/app/build.gradle.kts` (수정 — minSdk 21)
- `mobile/android/app/src/main/AndroidManifest.xml` (수정 — INTERNET permission)
- `mobile/android/app/google-services.json` (신규, placeholder)
- `mobile/ios/Runner/Info.plist` (수정 — Google Sign In URL scheme)
- `mobile/test/widget_test.dart` (수정 — 기존 counter 테스트 제거)
- `mobile/test/features/auth/login_screen_test.dart` (신규)
- `mobile/lib/core/network/auth_signal.dart` (신규 — signout 시그널)
