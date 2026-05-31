# Story 1.2: Google OAuth 로그인 API

---
baseline_commit: NO_VCS
---

Status: review

## Story

As an unauthenticated user,
I want to sign in with my Google account via the FastAPI backend,
so that I receive a JWT token pair (access + refresh) to access protected features.

## Acceptance Criteria

1. `POST /api/v1/auth/google`에 Google id_token을 전송하면 FastAPI가 Google에서 사용자 정보를 검증하고 `users` 테이블에 upsert 후, `access_token`(15분)과 `refresh_token`(30일)을 JSON으로 반환한다
2. `POST /api/v1/auth/refresh`에 유효한 refresh_token을 전송하면 새로운 access_token을 반환한다
3. 보호된 엔드포인트에 유효하지 않거나 만료된 access_token을 사용하면 HTTP 401과 `{"detail": "인증이 필요합니다.", "code": "UNAUTHORIZED"}`를 반환한다
4. role=admin이 아닌 사용자가 `/api/v1/admin/*` 엔드포인트에 요청하면 HTTP 403을 반환한다
5. 비활성화된 사용자(is_active=false)가 인증 시도 시 HTTP 403과 `{"detail": "계정이 정지되었습니다.", "code": "ACCOUNT_DEACTIVATED"}`를 반환한다

## Tasks / Subtasks

- [x] Task 1: SQLModel User 모델을 새 DB 스키마에 맞게 업데이트 (AC: 1, 3)
  - [x] `app/models.py`의 `User` 클래스를 001_initial_schema.py의 실제 컬럼에 맞게 수정 (nickname, role, profile_image_url, neighborhood_id, fcm_token — hashed_password/full_name/is_superuser/items 제거)
  - [x] `Item`/`ItemBase`/`ItemCreate`/`ItemUpdate`/`ItemPublic`/`ItemsPublic` 모델은 나중 스토리에서 사용되지 않으므로 이 스토리에서 제거 (app/api/routes/items.py, app/api/routes/private.py도 연동 제거 필요)
  - [x] `TokenPayload` 스키마에 `role: str | None = None` 추가 (어드민 체크용)
  - [x] 새 응답 스키마 추가: `AuthTokenResponse`, `RefreshRequest`

- [x] Task 2: `core/config.py`에 새 환경변수 추가 (AC: 1)
  - [x] `GOOGLE_CLIENT_ID: str` 추가
  - [x] `ACCESS_TOKEN_EXPIRE_MINUTES: int = 15` (현재 `60 * 24 * 8`에서 변경)
  - [x] `REFRESH_TOKEN_EXPIRE_DAYS: int = 30` 추가

- [x] Task 3: `core/security.py`에 refresh token 지원 추가 (AC: 2)
  - [x] `create_refresh_token(subject: str) -> str` 함수 추가 (type="refresh" 클레임 포함)
  - [x] `verify_refresh_token(token: str) -> str | None` 함수 추가 (type 클레임 검증)

- [x] Task 4: `services/oauth.py` 생성 — Google id_token 검증 (AC: 1)
  - [x] `verify_google_id_token(id_token: str) -> dict` 구현 (httpx로 Google tokeninfo 엔드포인트 호출)
  - [x] 반환값: `{"sub": "google_uid", "email": "...", "name": "..."}`
  - [x] 검증 실패 시 `HTTPException(400, {"detail": "유효하지 않은 Google 토큰입니다.", "code": "INVALID_GOOGLE_TOKEN"})` raise

- [x] Task 5: `crud/user.py` 생성 — 사용자 CRUD (AC: 1, 5)
  - [x] `get_user_by_email(session, email) -> User | None`
  - [x] `get_user_by_id(session, user_id) -> User | None`
  - [x] `upsert_google_user(session, email, google_sub, name) -> User` — 신규면 create, 기존이면 return

- [x] Task 6: `api/routes/auth.py` 생성 — 인증 라우터 (AC: 1, 2)
  - [x] `POST /auth/google` — id_token 수신 → Google 검증 → upsert → 토큰 쌍 반환
  - [x] `POST /auth/refresh` — refresh_token 수신 → 검증 → 새 access_token 반환

- [x] Task 7: `api/deps.py` 업데이트 — 에러 형식 수정 (AC: 3, 4)
  - [x] `get_current_user` 에러를 `{"detail": "인증이 필요합니다.", "code": "UNAUTHORIZED"}` 형식으로 변경
  - [x] `get_current_admin` dependency 추가 (`role == "admin"` 검사, 403 반환)
  - [x] `CurrentUser`, `CurrentAdmin` 타입 별칭 업데이트

- [x] Task 8: `api/main.py`에 auth 라우터 등록 (AC: 1)
  - [x] 새 `auth` 라우터를 `api_router`에 추가
  - [x] 기존 `login`, `items`, `private` 라우터 정리 (아키텍처에 없는 템플릿 잔재 제거)

- [x] Task 9: `.env` 및 `.env.example` 업데이트 (AC: 1)
  - [x] `GOOGLE_CLIENT_ID=` 추가 (루트 `.env` 및 `.env.example` 둘 다)

- [x] Task 10: 기본 pytest 테스트 작성 (AC: 1, 2, 3)
  - [x] `tests/api/test_auth.py` — `/auth/google` mock 테스트, `/auth/refresh` 테스트, 만료 토큰 401 테스트

## Dev Notes

### 구현 중 발견된 추가 사항

- **`__tablename__ = "users"` 필수**: SQLModel은 `User` 클래스명을 `user` (단수)로 추론하지만 실제 Alembic 마이그레이션은 `users` (복수) 테이블을 생성. `__tablename__` 명시 필수.
- **`Neighborhood` 모델 추가 필요**: `users.neighborhood_id` FK를 SQLAlchemy가 해석하려면 `Neighborhood` SQLModel도 `models.py`에 정의해야 함.
- **커스텀 HTTPException 핸들러**: 아키텍처 표준 에러 형식 `{"detail":"...","code":"..."}` (flat)을 달성하려면 FastAPI의 기본 래핑 동작을 오버라이드하는 `@app.exception_handler(HTTPException)` 필요.
- **`create_access_token` 시그니처 변경**: `expires_delta` 파라미터 제거, `role` 파라미터 추가. 호출부 전부 업데이트됨.
- **`auto_error=False`**: OAuth2PasswordBearer에 `auto_error=False` 설정하여 토큰 없을 때 FastAPI가 자동으로 422 반환하는 대신 `None`을 전달하도록 변경. deps.py의 `get_current_user`에서 직접 401 처리.

## Dev Agent Record

### Agent Model Used

claude-sonnet-4-6

### Debug Log References

- `__tablename__` 누락 → users 테이블 찾지 못하는 오류 수정
- `Neighborhood` 모델 누락 → FK 해석 실패 오류 수정
- FastAPI 응답 래핑 → 커스텀 예외 핸들러로 flat 형식 구현

### Completion Notes List

- 18/18 테스트 통과 (회귀 없음)
- AC 1~5 모두 충족
- `app/models.py`: User + Neighborhood 테이블 모델, Auth/Response 스키마
- `app/core/security.py`: create_refresh_token, verify_refresh_token 추가, create_access_token role 파라미터 추가
- `app/services/oauth.py`: httpx 기반 Google tokeninfo 검증
- `app/api/routes/auth.py`: POST /auth/google, POST /auth/refresh
- `app/api/deps.py`: 표준 에러 형식, CurrentAdmin dependency 추가
- `app/main.py`: 커스텀 HTTPException 핸들러 추가
- 기존 copier 템플릿 잔재(items, private, login, password 관련) 전면 정리

### Change Log

- 코드 리뷰 수정 (2026-05-30): audience 우회, UUID ValueError, TOCTOU, KeyError, whitespace IndexError, httpx timeout, google_sub 저장, WWW-Authenticate 헤더 10건 수정

### File List

- `backend/app/models.py` (수정)
- `backend/app/crud.py` (수정)
- `backend/app/core/config.py` (수정)
- `backend/app/core/security.py` (수정)
- `backend/app/core/db.py` (수정)
- `backend/app/main.py` (수정)
- `backend/app/api/deps.py` (수정)
- `backend/app/api/main.py` (수정)
- `backend/app/api/routes/auth.py` (신규)
- `backend/app/api/routes/users.py` (수정)
- `backend/app/api/routes/items.py` (정리)
- `backend/app/api/routes/private.py` (정리)
- `backend/app/api/routes/login.py` (정리)
- `backend/app/services/__init__.py` (신규)
- `backend/app/services/oauth.py` (신규)
- `backend/.env` (수정)
- `backend/tests/conftest.py` (수정)
- `backend/tests/api/routes/test_auth.py` (신규)
- `backend/tests/api/routes/test_users.py` (수정)
- `backend/tests/api/routes/test_items.py` (정리)
- `backend/tests/api/routes/test_login.py` (정리)
- `backend/tests/api/routes/test_private.py` (정리)
- `backend/tests/crud/test_user.py` (수정)
- `backend/tests/utils/user.py` (수정)
- `backend/tests/utils/utils.py` (수정)
- `backend/tests/utils/item.py` (정리)
- `backend/app/alembic/versions/003_add_google_sub.py` (신규)
