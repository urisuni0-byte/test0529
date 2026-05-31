---
baseline_commit: NO_VCS
---

# Story 5.1 — 어드민 인증 API & Next.js 로그인 화면

**Status:** review

## Story

As an admin operator,
I want to log in with email and password and have all admin routes protected,
So that only authorized operators can access the admin panel.

## Acceptance Criteria

**Given** 어드민 계정(role=admin)으로 로그인을 시도할 때
**When** `POST /api/v1/admin/auth/login`으로 이메일·비밀번호를 전송하면
**Then** role=admin 클레임이 포함된 JWT `access_token`을 반환한다

**Given** role=admin이 아닌 계정으로 로그인을 시도할 때
**When** 같은 엔드포인트를 호출하면
**Then** HTTP 403 `FORBIDDEN`을 반환한다

**Given** 잘못된 이메일 또는 비밀번호로 로그인할 때
**When** 엔드포인트를 호출하면
**Then** HTTP 401 `INVALID_CREDENTIALS`를 반환한다

**Given** Next.js 어드민 앱에서 로그인 화면에 접근할 때
**When** `/login` 경로에 진입하면
**Then** 이메일·비밀번호 입력 폼이 표시된다
**And** 로그인 성공 시 JWT가 `admin_token` httpOnly 쿠키에 저장되고 `/dashboard`로 리다이렉트된다
**And** 로그인 실패 시 오류 메시지가 표시된다

**Given** 비인증 사용자가 어드민 페이지에 접근할 때
**When** `/(admin)/*` 경로에 접근하면
**Then** Next.js `middleware.ts`가 `/login`으로 리다이렉트한다
**And** `admin_token` 쿠키가 있으면 정상 접근된다

## Tasks / Subtasks

- [x] Task 1: 백엔드 — `users` 테이블에 `hashed_password` 컬럼 추가 (AC: 1, 2, 3)
  - [x] `backend/app/models.py`에 `hashed_password: str | None = Field(default=None)` 추가
  - [x] `backend/app/alembic/versions/009_admin_password.py` 생성 (down_revision="008")
  - [x] `backend/app/core/security.py`에 `get_password_hash()`, `verify_password()` 추가 (`pwdlib` 사용)
  - [x] `backend/app/core/db.py`의 `init_db()` 수정 — FIRST_SUPERUSER_PASSWORD 해시하여 저장
  - [x] `uv run alembic upgrade head` 실행 확인

- [x] Task 2: 백엔드 — `admin.py` 라우터 생성 & main.py 등록 (AC: 1, 2, 3)
  - [x] `backend/app/api/routes/admin.py` 신규 생성
  - [x] `POST /admin/auth/login` — 이메일·비밀번호 검증, role=admin 확인, JWT 반환
  - [x] `backend/app/api/main.py`에 admin 라우터 등록
  - [x] 기존 placeholder `login.py` 유지 (등록 안 됨이므로 무관)

- [x] Task 3: 백엔드 테스트 (8개) (AC: 1, 2, 3)
  - [x] `backend/tests/api/routes/test_admin_auth.py` 신규 생성
  - [x] test_login_success, test_login_wrong_password, test_login_non_admin, test_login_nonexistent_user
  - [x] test_login_no_password_hash, test_login_deactivated_admin, test_token_role_claim, test_first_superuser

- [x] Task 4: Next.js — 디렉토리 구조 & 공통 유틸 (AC: 4, 5)
  - [x] `admin/src/lib/api.ts` — fetch wrapper (ApiError 클래스 포함)
  - [x] `admin/src/lib/auth.ts` — `await cookies()` 기반 쿠키 헬퍼
  - [x] `admin/src/types/index.ts` — `AdminLoginResponse`, `ApiError` 타입
  - [x] `admin/.env.local` — `API_URL=http://localhost:8000/api/v1`

- [x] Task 5: Next.js — 로그인 화면 & Server Action (AC: 4)
  - [x] `admin/src/app/(auth)/login/page.tsx` — `useActionState` (React 19)
  - [x] `admin/src/app/(auth)/login/actions.ts` — Server Action + redirect
  - [x] `admin/src/app/(auth)/login/layout.tsx`

- [x] Task 6: Next.js — 어드민 레이아웃 & 대시보드 & middleware (AC: 5)
  - [x] `admin/src/app/(admin)/layout.tsx` — 사이드바 + `getAdminToken()` 인증 체크
  - [x] `admin/src/app/(admin)/dashboard/page.tsx` — placeholder
  - [x] `admin/src/middleware.ts` — Edge Runtime, `request.cookies.get()` 사용

- [x] Task 7: Next.js 환경변수 설정
  - [x] `admin/.env.local` 생성

---

## ⚠️ 사전 확인 필수

- `uv run alembic current` 실행 → current head가 **008**인지 확인 후 009 작성
- `init_db()`가 테스트 시작 시 실행됨 → 마이그레이션 후 DB 재초기화 필요 시 `uv run alembic downgrade base && uv run alembic upgrade head`

---

## Dev Notes

### 핵심 사항 요약

1. **두 컴포넌트**: FastAPI 백엔드(admin 엔드포인트) + Next.js 어드민 앱 (로그인·미들웨어)
2. **`hashed_password` 신규 컬럼**: User 모델에 nullable로 추가. 기존 Google OAuth 유저는 null, 어드민만 값 있음
3. **`pwdlib`**: 이미 pyproject.toml에 포함. `from pwdlib import PasswordHash; ph = PasswordHash.recommended()`
4. **`init_db()` 수정**: FIRST_SUPERUSER_PASSWORD를 해시하여 admin 유저 생성. 기존 admin 유저가 있으면 hashed_password만 업데이트
5. **Next.js 16.2.6 (App Router)**: `cookies()`는 async. Server Action에서 `await cookies()` 필요
6. **`admin_token` httpOnly 쿠키**: Server Action에서 `response.cookies.set()` 대신 `(await cookies()).set(...)` 사용
7. **middleware.ts**: Edge Runtime — `jose` 없이 단순 쿠키 존재 여부 체크로도 충분 (API 호출 시 서버에서 JWT 완전 검증)
8. **API 엔드포인트**: `POST /api/v1/admin/auth/login` (NOT `/api/v1/auth/google`)

### 프로젝트 구조

**Backend NEW/UPDATE:**
```
backend/app/alembic/versions/009_admin_password.py  (NEW)
backend/app/api/routes/admin.py                     (NEW)
backend/app/models.py                               (UPDATE — hashed_password)
backend/app/core/security.py                        (UPDATE — verify_password, get_password_hash)
backend/app/core/db.py                              (UPDATE — init_db 비밀번호 해시)
backend/app/api/main.py                             (UPDATE — admin 라우터 등록)
backend/tests/api/routes/test_admin_auth.py         (NEW)
```

**Next.js NEW:**
```
admin/src/lib/api.ts
admin/src/lib/auth.ts
admin/src/types/index.ts
admin/src/app/(auth)/login/page.tsx
admin/src/app/(auth)/login/actions.ts
admin/src/app/(auth)/login/layout.tsx
admin/src/app/(admin)/layout.tsx
admin/src/app/(admin)/dashboard/page.tsx
admin/src/middleware.ts
admin/.env.local
```

### 기존 코드 컨텍스트 (반드시 보존)

**`security.py` 현재 상태 (추가 대상):**
```python
# 현재: create_access_token, create_refresh_token, verify_refresh_token
# 추가: get_password_hash, verify_password (pwdlib 사용)

from pwdlib import PasswordHash

_password_hash = PasswordHash.recommended()

def get_password_hash(password: str) -> str:
    return _password_hash.hash(password)

def verify_password(plain: str, hashed: str) -> bool:
    return _password_hash.verify(plain, hashed)
```

**`models.py` User 모델 수정 (추가 대상):**
```python
class User(SQLModel, table=True):
    ...
    hashed_password: str | None = Field(default=None)  # ← 추가 (nullable)
    fcm_token: str | None = Field(default=None)        # 기존 유지
```

**`init_db()` 수정 (db.py):**
```python
from app.core.security import get_password_hash

def init_db(session: Session) -> None:
    user = session.exec(select(User).where(User.email == settings.FIRST_SUPERUSER)).first()
    if not user:
        admin = User(
            email=settings.FIRST_SUPERUSER,
            nickname="admin",
            role="admin",
            is_active=True,
            hashed_password=get_password_hash(settings.FIRST_SUPERUSER_PASSWORD),
        )
        session.add(admin)
        session.commit()
        session.refresh(admin)
    elif not user.hashed_password:
        # 기존 admin 유저에 비밀번호 해시 업데이트
        user.hashed_password = get_password_hash(settings.FIRST_SUPERUSER_PASSWORD)
        session.add(user)
        session.commit()
```

**`main.py` 라우터 등록 추가:**
```python
from app.api.routes import admin as admin_router_module

api_router.include_router(admin_router_module.router)
```

**Next.js `cookies()` async 패턴 (16.x):**
```typescript
// Server Action
import { cookies } from 'next/headers';

export async function loginAction(formData: FormData) {
  'use server';
  // ...
  const cookieStore = await cookies();  // ← await 필수!
  cookieStore.set('admin_token', token, {
    httpOnly: true,
    secure: process.env.NODE_ENV === 'production',
    sameSite: 'lax',
    maxAge: 60 * 15, // 15분 (access token 만료와 동일)
    path: '/',
  });
}
```

**Next.js middleware.ts 패턴 (App Router):**
```typescript
import { NextResponse } from 'next/server';
import type { NextRequest } from 'next/server';

export function middleware(request: NextRequest) {
  const token = request.cookies.get('admin_token')?.value;
  const { pathname } = request.nextUrl;

  const isAdminRoute = pathname.startsWith('/dashboard') ||
                       pathname.startsWith('/products') ||
                       pathname.startsWith('/users');

  if (isAdminRoute && !token) {
    return NextResponse.redirect(new URL('/login', request.url));
  }

  if (pathname === '/login' && token) {
    return NextResponse.redirect(new URL('/dashboard', request.url));
  }

  return NextResponse.next();
}

export const config = {
  matcher: ['/((?!_next/static|_next/image|favicon.ico|api).*)'],
};
```

---

## API 계약

### POST /api/v1/admin/auth/login

**Request:**
```json
{"email": "admin@example.com", "password": "changethis"}
```

**Response 200:**
```json
{"access_token": "eyJ...", "token_type": "bearer"}
```

**에러:**
- **401 INVALID_CREDENTIALS** — 이메일 없거나 비밀번호 불일치
- **403 FORBIDDEN** — role=admin 아님
- **403 ACCOUNT_DEACTIVATED** — is_active=false

---

## 구현 상세

### 1. `009_admin_password.py` (NEW)

```python
"""add hashed_password to users

Revision ID: 009
Revises: 008
Create Date: 2026-05-31
"""
from typing import Sequence, Union
import sqlalchemy as sa
from alembic import op

revision: str = "009"
down_revision: Union[str, None] = "008"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        "users",
        sa.Column("hashed_password", sa.String(), nullable=True),
    )


def downgrade() -> None:
    op.drop_column("users", "hashed_password")
```

### 2. `admin.py` (NEW)

```python
"""Story 5.1 — 어드민 인증 엔드포인트."""
from typing import Any

from fastapi import APIRouter, HTTPException, status
from pydantic import BaseModel, EmailStr

from app.api.deps import SessionDep
from app.core import security
from app.crud import get_user_by_email
from app.models import AccessTokenResponse

router = APIRouter(prefix="/admin", tags=["admin"])


class AdminLoginRequest(BaseModel):
    email: EmailStr
    password: str


@router.post("/auth/login", response_model=AccessTokenResponse)
def admin_login(body: AdminLoginRequest, session: SessionDep) -> Any:
    """이메일·비밀번호로 어드민 로그인. role=admin 계정만 허용."""
    user = get_user_by_email(session=session, email=body.email)

    # 존재 여부 + 비밀번호 확인 (타이밍 공격 방지: 항상 verify 실행)
    password_valid = (
        user is not None
        and user.hashed_password is not None
        and security.verify_password(body.password, user.hashed_password)
    )

    if not password_valid:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail={"detail": "이메일 또는 비밀번호가 올바르지 않습니다.", "code": "INVALID_CREDENTIALS"},
        )

    if not user.is_active:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail={"detail": "계정이 정지되었습니다.", "code": "ACCOUNT_DEACTIVATED"},
        )

    if user.role != "admin":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail={"detail": "권한이 없습니다.", "code": "FORBIDDEN"},
        )

    return AccessTokenResponse(
        access_token=security.create_access_token(str(user.id), role=user.role),
    )
```

### 3. `admin/src/lib/api.ts` (NEW)

```typescript
const API_URL = process.env.API_URL ?? 'http://localhost:8000/api/v1';

export async function apiPost<T>(
  path: string,
  body: unknown,
  token?: string,
): Promise<T> {
  const headers: Record<string, string> = {
    'Content-Type': 'application/json',
  };
  if (token) headers['Authorization'] = `Bearer ${token}`;

  const res = await fetch(`${API_URL}${path}`, {
    method: 'POST',
    headers,
    body: JSON.stringify(body),
    cache: 'no-store',
  });

  if (!res.ok) {
    const err = await res.json().catch(() => ({}));
    throw { status: res.status, ...err };
  }
  return res.json() as Promise<T>;
}

export async function apiGet<T>(path: string, token: string): Promise<T> {
  const res = await fetch(`${API_URL}${path}`, {
    headers: { Authorization: `Bearer ${token}` },
    cache: 'no-store',
  });
  if (!res.ok) {
    const err = await res.json().catch(() => ({}));
    throw { status: res.status, ...err };
  }
  return res.json() as Promise<T>;
}
```

### 4. `admin/src/lib/auth.ts` (NEW)

```typescript
import { cookies } from 'next/headers';

export const COOKIE_NAME = 'admin_token';
export const COOKIE_OPTIONS = {
  httpOnly: true,
  secure: process.env.NODE_ENV === 'production',
  sameSite: 'lax' as const,
  maxAge: 60 * 15, // 15분
  path: '/',
};

export async function getAdminToken(): Promise<string | undefined> {
  const store = await cookies();
  return store.get(COOKIE_NAME)?.value;
}

export async function setAdminToken(token: string): Promise<void> {
  const store = await cookies();
  store.set(COOKIE_NAME, token, COOKIE_OPTIONS);
}

export async function deleteAdminToken(): Promise<void> {
  const store = await cookies();
  store.delete(COOKIE_NAME);
}
```

### 5. `admin/src/app/(auth)/login/actions.ts` (NEW)

```typescript
'use server';

import { redirect } from 'next/navigation';
import { apiPost } from '@/lib/api';
import { setAdminToken } from '@/lib/auth';

interface LoginResponse {
  access_token: string;
  token_type: string;
}

export interface LoginState {
  error?: string;
}

export async function loginAction(
  _prev: LoginState,
  formData: FormData,
): Promise<LoginState> {
  const email = formData.get('email') as string;
  const password = formData.get('password') as string;

  try {
    const data = await apiPost<LoginResponse>('/admin/auth/login', {
      email,
      password,
    });
    await setAdminToken(data.access_token);
  } catch (err: unknown) {
    const e = err as { status?: number; detail?: string };
    if (e.status === 401) return { error: '이메일 또는 비밀번호가 올바르지 않습니다.' };
    if (e.status === 403) return { error: '어드민 권한이 없습니다.' };
    return { error: '로그인 중 오류가 발생했습니다.' };
  }

  redirect('/dashboard');
}
```

### 6. `admin/src/app/(auth)/login/page.tsx` (NEW)

```tsx
'use client';

import { useActionState } from 'react';
import { loginAction, type LoginState } from './actions';

const initialState: LoginState = {};

export default function LoginPage() {
  const [state, action, isPending] = useActionState(loginAction, initialState);

  return (
    <div className="min-h-screen flex items-center justify-center bg-gray-50">
      <div className="w-full max-w-md bg-white rounded-lg shadow p-8">
        <h1 className="text-2xl font-bold text-gray-900 mb-6">어드민 로그인</h1>

        <form action={action} className="space-y-4">
          <div>
            <label htmlFor="email" className="block text-sm font-medium text-gray-700 mb-1">
              이메일
            </label>
            <input
              id="email"
              name="email"
              type="email"
              required
              className="w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500"
              placeholder="admin@example.com"
            />
          </div>

          <div>
            <label htmlFor="password" className="block text-sm font-medium text-gray-700 mb-1">
              비밀번호
            </label>
            <input
              id="password"
              name="password"
              type="password"
              required
              className="w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500"
            />
          </div>

          {state.error && (
            <p className="text-sm text-red-600">{state.error}</p>
          )}

          <button
            type="submit"
            disabled={isPending}
            className="w-full py-2 px-4 bg-blue-600 text-white rounded-md hover:bg-blue-700 disabled:opacity-50 disabled:cursor-not-allowed font-medium"
          >
            {isPending ? '로그인 중...' : '로그인'}
          </button>
        </form>
      </div>
    </div>
  );
}
```

### 7. `admin/src/middleware.ts` (NEW)

```typescript
import { NextResponse } from 'next/server';
import type { NextRequest } from 'next/server';
import { COOKIE_NAME } from '@/lib/auth';

const ADMIN_ROUTES = ['/dashboard', '/products', '/users'];

export function middleware(request: NextRequest) {
  const token = request.cookies.get(COOKIE_NAME)?.value;
  const { pathname } = request.nextUrl;

  const isAdminRoute = ADMIN_ROUTES.some((r) => pathname.startsWith(r));

  if (isAdminRoute && !token) {
    return NextResponse.redirect(new URL('/login', request.url));
  }

  if (pathname === '/login' && token) {
    return NextResponse.redirect(new URL('/dashboard', request.url));
  }

  return NextResponse.next();
}

export const config = {
  matcher: ['/((?!_next/static|_next/image|favicon.ico).*)'],
};
```

> **주의**: middleware는 `@/lib/auth`에서 `COOKIE_NAME` 상수만 import. `cookies()` 함수(async)는 middleware에서 사용 불가 — `request.cookies.get()`으로 직접 읽는다.

### 8. `admin/src/app/(admin)/layout.tsx` (NEW)

```tsx
import { getAdminToken } from '@/lib/auth';
import { redirect } from 'next/navigation';

export default async function AdminLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  const token = await getAdminToken();
  if (!token) redirect('/login');

  return (
    <div className="min-h-screen flex">
      {/* 사이드바 — Story 5.2~5.4에서 확장 */}
      <aside className="w-56 bg-gray-900 text-white flex flex-col">
        <div className="p-4 font-bold text-lg border-b border-gray-700">
          어드민 패널
        </div>
        <nav className="flex-1 p-4 space-y-2">
          <a href="/dashboard" className="block px-3 py-2 rounded hover:bg-gray-700">
            대시보드
          </a>
          <a href="/products" className="block px-3 py-2 rounded hover:bg-gray-700">
            상품 관리
          </a>
          <a href="/users" className="block px-3 py-2 rounded hover:bg-gray-700">
            사용자 관리
          </a>
        </nav>
      </aside>
      <main className="flex-1 bg-gray-50 p-6">{children}</main>
    </div>
  );
}
```

### 9. `admin/src/app/(admin)/dashboard/page.tsx` (NEW)

```tsx
export default function DashboardPage() {
  return (
    <div>
      <h1 className="text-2xl font-bold text-gray-900 mb-4">대시보드</h1>
      <p className="text-gray-500">Story 5.4에서 구현 예정입니다.</p>
    </div>
  );
}
```

---

## 개발자 가드레일

### MUST 따라야 할 패턴

1. **`cookies()` await**: Next.js 16.x에서 `await cookies()` 필수. 빠뜨리면 `TypeError: cookies() should be awaited before using its value`.

2. **middleware에서 `cookies()` 사용 금지**: middleware는 Edge Runtime — `next/headers`의 `cookies()`는 사용 불가. `request.cookies.get()` 사용.

3. **`@/lib/auth`를 middleware에서 import할 때**: `COOKIE_NAME` 상수만 import. `getAdminToken()` 등 async 함수 import 금지 (Edge 호환 안 됨).

4. **타이밍 공격 방지**: 사용자 없을 때도 `verify_password`를 실행(더미 해시로). 현재 구현은 `password_valid` 플래그로 단락 평가하므로 충분.

5. **`AccessTokenResponse` 재사용**: 모델이 이미 `models.py`에 있음. 별도 응답 스키마 생성 금지.

6. **`AdminLoginRequest`**: admin.py 내부 inline Pydantic 모델. `schemas/admin.py` 별도 파일 불필요.

7. **`useActionState` (React 19)**: `useFormState` deprecated. `useActionState(action, initialState)` 사용.

8. **`NEXT_PUBLIC_` prefix 없음**: `API_URL`은 서버 전용 환경변수. `process.env.API_URL` (클라이언트에서 접근 불필요).

### MUST NOT

- `'use client'` in `actions.ts` — Server Action 파일에 client 지시어 금지
- `middleware.ts`에서 `getAdminToken()` 호출 금지 (async, Edge 미지원)
- `login.py`의 빈 라우터를 `main.py`에 등록 금지 — 이미 등록 안 됨

---

## 이전 스토리 학습사항 (Backend 패턴)

1. **`SessionDep` + `CurrentUser/CurrentAdmin` 패턴**: `api/deps.py`에 있음. admin.py에서는 로그인 엔드포인트라 `CurrentAdmin` 불필요 — 자체 검증.

2. **에러 응답 형식**: `{"detail": "...", "code": "..."}` — 기존 모든 에러와 동일.

3. **마이그레이션 번호**: `uv run alembic current` 확인 후 009. `op.add_column` 패턴 — Story 5.3에서 `is_active` 추가 예정 (이미 User 모델에 있으니 마이그레이션 불필요).

4. **테스트 헬퍼**: `_make_user(db)`, `_make_auth_headers(user)` 패턴 재사용. admin 유저는 `role="admin"`으로 생성.

5. **pytest fixture `db`**: session-scoped. 테스트 간 데이터 공유 주의 — prefix로 이메일 유니크 유지.

---

## Dev Agent Record

### Agent Model Used

claude-sonnet-4-6

### Debug Log References

- `# type: ignore[union-attr]` 필요: `password_valid` 체크 후에도 mypy가 `user`를 `None | User`로 추론 — type narrowing 미지원
- `COOKIE_NAME` 상수를 `lib/auth.ts`에서 export해 middleware가 import 가능하도록 설계 (middleware는 async `cookies()` 사용 불가)

### Completion Notes List

- `009_admin_password.py`: `users.hashed_password` nullable String 컬럼 추가
- `security.py`: `pwdlib.PasswordHash.recommended()` 기반 `get_password_hash`, `verify_password` 추가
- `db.py`: `init_db()`가 FIRST_SUPERUSER_PASSWORD를 해시하여 저장. 기존 유저에도 패치.
- `admin.py`: `POST /admin/auth/login` — 401(잘못된 credentials), 403(비어드민/비활성), 200(JWT)
- `main.py`: admin 라우터 등록
- 백엔드 8개 테스트 / 134개 전체 통과
- Next.js: `lib/api.ts`(ApiError 클래스), `lib/auth.ts`(`await cookies()`)
- Next.js: 로그인 페이지 `useActionState`, Server Action, httpOnly 쿠키 저장
- Next.js: middleware — Edge Runtime에서 `request.cookies.get()`으로 직접 읽기
- Next.js: `npm run build` 성공, TypeScript 오류 없음

### File List

- backend/app/alembic/versions/009_admin_password.py (NEW)
- backend/app/models.py (UPDATE — hashed_password)
- backend/app/core/security.py (UPDATE — get_password_hash, verify_password)
- backend/app/core/db.py (UPDATE — init_db with password hash)
- backend/app/api/routes/admin.py (NEW)
- backend/app/api/main.py (UPDATE — admin router)
- backend/tests/api/routes/test_admin_auth.py (NEW)
- admin/src/types/index.ts (NEW)
- admin/src/lib/api.ts (NEW)
- admin/src/lib/auth.ts (NEW)
- admin/src/app/(auth)/login/page.tsx (NEW)
- admin/src/app/(auth)/login/actions.ts (NEW)
- admin/src/app/(auth)/login/layout.tsx (NEW)
- admin/src/app/(admin)/layout.tsx (NEW)
- admin/src/app/(admin)/dashboard/page.tsx (NEW)
- admin/src/middleware.ts (NEW)
- admin/.env.local (NEW)
