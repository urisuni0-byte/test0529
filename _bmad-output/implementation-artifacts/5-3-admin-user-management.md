---
baseline_commit: NO_VCS
---

# Story 5.3 — 어드민 사용자 관리

**Status:** review

## Story

As an admin operator,
I want to view all users and deactivate accounts when necessary,
So that I can handle policy violations and maintain platform integrity.

## Acceptance Criteria

**Given** 어드민이 사용자 목록 API를 호출할 때
**When** `GET /api/v1/admin/users`를 호출하면
**Then** 전체 사용자 목록이 반환된다 (닉네임·이메일·가입일·is_active 포함)

**Given** 어드민이 특정 사용자를 비활성화할 때
**When** `PATCH /api/v1/admin/users/{id}/deactivate`를 호출하면
**Then** `is_active=false`로 업데이트되고 HTTP 200을 반환한다

**Given** 비활성화된 사용자가 로그인을 시도할 때
**When** 인증 엔드포인트를 호출하면
**Then** HTTP 403과 `{"detail": "계정이 정지되었습니다.", "code": "ACCOUNT_DEACTIVATED"}`를 반환한다

**Given** 일반 사용자 JWT로 어드민 엔드포인트를 호출할 때
**When** `GET` 또는 `PATCH /api/v1/admin/users/*`를 호출하면
**Then** HTTP 403 `FORBIDDEN`을 반환한다

**Given** 어드민이 Next.js 사용자 관리 페이지에 접근할 때
**When** `/users` 페이지가 로드되면
**Then** 사용자 목록이 테이블로 표시된다 (닉네임·이메일·가입일·상태 컬럼)
**And** 비활성화 버튼 클릭 후 확인 시 API가 호출되고 상태가 즉시 반영된다 (revalidatePath)

## Tasks / Subtasks

- [x] Task 1: 백엔드 — `admin.py`에 사용자 엔드포인트 추가 (AC: 1, 2, 3, 4)
  - [x] `AdminUserItem` BaseModel 스키마 정의 (id, email, nickname, is_active, created_at)
  - [x] `GET /admin/users` — 전체 사용자 목록, `created_at` 내림차순 정렬, `CurrentAdmin` 필수
  - [x] `PATCH /admin/users/{user_id}/deactivate` — `is_active=False`, HTTP 200 반환, `CurrentAdmin` 필수
  - [x] 자기 자신 비활성화 방지 (400 `CANNOT_DEACTIVATE_SELF`)

- [x] Task 2: 백엔드 테스트 12개 (AC: 1, 2, 3, 4)
  - [x] `backend/tests/api/routes/test_admin_users.py` 신규 생성
  - [x] 목록 성공·필수필드(id, email, nickname, is_active, created_at) 포함·어드민필수·미인증
  - [x] 비활성화 성공(is_active=false 확인)·없는유저404·어드민필수·미인증·자기자신400·멱등성
  - [x] 비활성화 사용자 Google 로그인 시도 → 403 ACCOUNT_DEACTIVATED (auth.py 검증)
  - [x] 비활성화 사용자 JWT로 API 접근 시 → 403 ACCOUNT_DEACTIVATED (deps.py 검증)

- [x] Task 3: Next.js — `lib/api.ts` + `types/index.ts` 업데이트 (AC: 5)
  - [x] `apiPatch<T>(path, token, body?)` 추가 (PATCH 요청, 응답 바디 있음 — 200 반환)
  - [x] `AdminUserItem`, `AdminUserListResponse` 타입 추가

- [x] Task 4: Next.js — 사용자 관리 페이지 (AC: 5)
  - [x] `page.tsx` — Server Component, apiGet → UsersTable
  - [x] `actions.ts` — `deactivateUserAction(userId)` + `revalidatePath('/users')`
  - [x] `UsersTable.tsx` — Client Component, confirm dialog, is_active 상태 배지

---

## Dev Notes

### 🚨 핵심 사전 정보 — 반드시 읽을 것

**`is_active` 이미 구현됨 — 마이그레이션 불필요:**

`is_active BOOLEAN DEFAULT TRUE`는 이미 `migration 001_initial_schema.py`(line 45)에서 생성됨.
`User` 모델(`backend/app/models.py` line 48)에도 이미 `is_active: bool = Field(default=True)` 존재.

**`is_active` 체크 이미 구현됨 — 중복 구현 금지:**

| 파일 | 위치 | 역할 |
|---|---|---|
| `backend/app/api/routes/auth.py` | line 35-38 | Google 로그인 시 403 |
| `backend/app/api/routes/auth.py` | line 68 | 리프레시 토큰 시 401 |
| `backend/app/api/routes/admin.py` | line 41-45 | 어드민 로그인 시 403 |
| `backend/app/api/deps.py` | line 60-64 | JWT 인증 미들웨어에서 403 |

→ AC "비활성화된 사용자가 로그인 시 403" 는 이미 구현된 동작임. 추가 구현 없이 테스트만 작성하면 됨.

**사이드바 네비게이션 이미 존재:**

`admin/src/app/(admin)/layout.tsx` line 39-42에 `/users` 링크가 이미 있음 — 사이드바 수정 불필요.

---

### 프로젝트 구조

**Backend UPDATE:**
```
backend/app/api/routes/admin.py     ← GET /admin/users + PATCH /admin/users/{id}/deactivate 추가
backend/tests/api/routes/test_admin_users.py   (NEW)
```

**Next.js NEW/UPDATE:**
```
admin/src/lib/api.ts                (UPDATE — apiPatch 추가)
admin/src/types/index.ts            (UPDATE — AdminUserItem, AdminUserListResponse 추가)
admin/src/app/(admin)/users/page.tsx        (NEW — Server Component)
admin/src/app/(admin)/users/actions.ts      (NEW — Server Action)
admin/src/app/(admin)/users/UsersTable.tsx  (NEW — Client Component)
```

---

### 기존 코드 컨텍스트 — 반드시 준수

**`admin.py` 현재 상태 (Story 5.1 + 5.2 구현 완료):**

```python
# 현재 엔드포인트:
#   POST /admin/auth/login
#   GET  /admin/products
#   DELETE /admin/products/{product_id}
#
# 추가할 것:
#   GET  /admin/users
#   PATCH /admin/users/{user_id}/deactivate

# 현재 import 상태 (이미 있음):
from app.api.deps import CurrentAdmin, SessionDep
from app.models import AccessTokenResponse, Product, User

# 추가 필요 (이미 있는지 확인 후 없으면 추가):
# from sqlmodel import col, select  ← 이미 있음 (products에서 사용 중)
# import uuid                       ← 이미 있음
# from datetime import datetime     ← 이미 있음
```

**`User` 모델 필드 (backend/app/models.py):**

```python
class User(SQLModel, table=True):
    id: uuid.UUID                    # PK
    email: str                       # unique, max_length=255
    nickname: str | None             # max_length=15
    profile_image_url: str | None
    neighborhood_id: int | None
    google_sub: str | None
    role: str                        # "user" | "admin"
    is_active: bool                  # Field(default=True) — 비활성화 대상 필드
    fcm_token: str | None
    hashed_password: str | None
    created_at: datetime
```

**`CurrentAdmin` dep:**
```python
CurrentAdmin = Annotated[User, Depends(get_current_admin)]
# 내부: get_current_user + role == "admin" 체크
# role != admin → 403 FORBIDDEN
# is_active == False → 403 ACCOUNT_DEACTIVATED (get_current_user에서 처리됨)
```

**`lib/api.ts` 현재 상태:**
```typescript
// 현재: apiPost, apiGet, apiDelete
// 추가:
export async function apiPatch<T>(
  path: string,
  token: string,
  body?: unknown,
): Promise<T> {
  const headers: Record<string, string> = {
    Authorization: `Bearer ${token}`,
  };
  if (body !== undefined) {
    headers['Content-Type'] = 'application/json';
  }
  const res = await fetch(`${API_URL}${path}`, {
    method: 'PATCH',
    headers,
    body: body !== undefined ? JSON.stringify(body) : undefined,
    cache: 'no-store',
  });
  return handleResponse<T>(res);
}
```

**Next.js Server Action 패턴 (Story 5.2에서 확립):**
```typescript
'use server';
import { revalidatePath } from 'next/cache';

export async function deactivateUserAction(userId: string): Promise<{ error?: string }> {
  const token = await getAdminToken();
  if (!token) return { error: '인증이 필요합니다.' };
  try {
    await apiPatch<AdminUserItem>(`/admin/users/${userId}/deactivate`, token);
    revalidatePath('/users');
    return {};
  } catch (err) {
    if (err instanceof ApiError) return { error: err.message };
    return { error: '처리 중 오류가 발생했습니다.' };
  }
}
```

---

## API 계약

### GET /api/v1/admin/users

**인증**: `Authorization: Bearer {admin_jwt}` 필수

**Response 200:**
```json
{
  "items": [
    {
      "id": "uuid",
      "email": "user@example.com",
      "nickname": "홍길동",
      "is_active": true,
      "created_at": "2026-05-29T10:00:00Z"
    }
  ],
  "total": 42
}
```

---

### PATCH /api/v1/admin/users/{user_id}/deactivate

**인증**: `Authorization: Bearer {admin_jwt}` 필수

**Request Body**: 없음 (empty body 허용)

**Response 200:**
```json
{
  "id": "uuid",
  "email": "user@example.com",
  "nickname": "홍길동",
  "is_active": false,
  "created_at": "2026-05-29T10:00:00Z"
}
```

**Error Responses:**
- **404 USER_NOT_FOUND** — 사용자 없음
- **400 CANNOT_DEACTIVATE_SELF** — 자기 자신 비활성화 시도
- **403 FORBIDDEN** — 일반 유저 접근

---

## 구현 상세

### 1. `admin.py` — 사용자 관리 엔드포인트 추가

기존 `class AdminProductItem(BaseModel)` 아래에 추가:

```python
class AdminUserItem(BaseModel):
    id: uuid.UUID
    email: str
    nickname: str | None
    is_active: bool
    created_at: datetime


@router.get("/users")
def list_admin_users(
    session: SessionDep,
    current_admin: CurrentAdmin,
) -> Any:
    """전체 사용자 목록. created_at 내림차순."""
    users = session.exec(
        select(User).order_by(col(User.created_at).desc())
    ).all()
    items = [
        AdminUserItem(
            id=u.id,
            email=u.email,
            nickname=u.nickname,
            is_active=u.is_active,
            created_at=u.created_at,
        )
        for u in users
    ]
    return {"items": items, "total": len(items)}


@router.patch("/users/{user_id}/deactivate")
def deactivate_admin_user(
    user_id: uuid.UUID,
    session: SessionDep,
    current_admin: CurrentAdmin,
) -> Any:
    """사용자 비활성화. is_active=False 설정."""
    if user_id == current_admin.id:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail={"detail": "자신의 계정은 비활성화할 수 없습니다.", "code": "CANNOT_DEACTIVATE_SELF"},
        )
    user = session.get(User, user_id)
    if not user:
        raise HTTPException(
            status_code=404,
            detail={"detail": "사용자를 찾을 수 없습니다.", "code": "USER_NOT_FOUND"},
        )
    user.is_active = False
    session.add(user)
    session.commit()
    session.refresh(user)
    return AdminUserItem(
        id=user.id,
        email=user.email,
        nickname=user.nickname,
        is_active=user.is_active,
        created_at=user.created_at,
    )
```

**주의:** `status` import가 이미 있는지 확인. `admin.py` line 6에 `from fastapi import APIRouter, HTTPException, Query, status`로 이미 있음. 추가 불필요.

### 2. `admin/src/types/index.ts` — 타입 추가

기존 `AdminProductListResponse` 인터페이스 아래에 추가:

```typescript
export interface AdminUserItem {
  id: string;
  email: string;
  nickname: string | null;
  is_active: boolean;
  created_at: string;
}

export interface AdminUserListResponse {
  items: AdminUserItem[];
  total: number;
}
```

### 3. `admin/src/lib/api.ts` — `apiPatch` 추가

기존 `apiDelete` 함수 아래에 추가:

```typescript
export async function apiPatch<T>(
  path: string,
  token: string,
  body?: unknown,
): Promise<T> {
  const headers: Record<string, string> = {
    Authorization: `Bearer ${token}`,
  };
  if (body !== undefined) {
    headers['Content-Type'] = 'application/json';
  }
  const res = await fetch(`${API_URL}${path}`, {
    method: 'PATCH',
    headers,
    body: body !== undefined ? JSON.stringify(body) : undefined,
    cache: 'no-store',
  });
  return handleResponse<T>(res);
}
```

### 4. `admin/src/app/(admin)/users/actions.ts`

```typescript
'use server';

import { revalidatePath } from 'next/cache';
import { apiPatch, ApiError } from '@/lib/api';
import { getAdminToken } from '@/lib/auth';
import type { AdminUserItem } from '@/types';

export interface ActionResult {
  error?: string;
}

export async function deactivateUserAction(
  userId: string,
): Promise<ActionResult> {
  const token = await getAdminToken();
  if (!token) return { error: '인증이 필요합니다.' };

  try {
    await apiPatch<AdminUserItem>(
      `/admin/users/${userId}/deactivate`,
      token,
    );
    revalidatePath('/users');
    return {};
  } catch (err) {
    if (err instanceof ApiError) {
      return { error: err.message };
    }
    return { error: '처리 중 오류가 발생했습니다.' };
  }
}
```

### 5. `admin/src/app/(admin)/users/page.tsx`

```tsx
import { getAdminToken } from '@/lib/auth';
import { apiGet } from '@/lib/api';
import type { AdminUserListResponse } from '@/types';
import UsersTable from './UsersTable';

export default async function UsersPage() {
  const token = await getAdminToken();

  const data = await apiGet<AdminUserListResponse>('/admin/users', token!);

  return (
    <div>
      <div className="flex items-center justify-between mb-4">
        <h1 className="text-2xl font-bold text-gray-900">사용자 관리</h1>
        <span className="text-sm text-gray-500">총 {data.total}명</span>
      </div>
      <UsersTable users={data.items} />
    </div>
  );
}
```

### 6. `admin/src/app/(admin)/users/UsersTable.tsx`

```tsx
'use client';

import { useState } from 'react';
import { deactivateUserAction } from './actions';
import type { AdminUserItem } from '@/types';

interface UsersTableProps {
  users: AdminUserItem[];
}

export default function UsersTable({ users }: UsersTableProps) {
  const [processingId, setProcessingId] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  const handleDeactivate = async (user: AdminUserItem) => {
    if (!confirm(`"${user.nickname ?? user.email}" 계정을 비활성화하시겠습니까?`)) return;

    setProcessingId(user.id);
    setError(null);
    const result = await deactivateUserAction(user.id);
    setProcessingId(null);
    if (result.error) setError(result.error);
  };

  if (users.length === 0) {
    return (
      <div className="text-center py-12 text-gray-500">
        등록된 사용자가 없습니다.
      </div>
    );
  }

  return (
    <>
      {error && (
        <p className="mb-3 text-sm text-red-600 bg-red-50 px-3 py-2 rounded">
          {error}
        </p>
      )}
      <div className="bg-white rounded-lg shadow overflow-hidden">
        <table className="w-full text-sm">
          <thead className="bg-gray-50 border-b">
            <tr>
              <th className="text-left px-4 py-3 font-medium text-gray-600">닉네임</th>
              <th className="text-left px-4 py-3 font-medium text-gray-600">이메일</th>
              <th className="text-left px-4 py-3 font-medium text-gray-600">가입일</th>
              <th className="text-left px-4 py-3 font-medium text-gray-600">상태</th>
              <th className="px-4 py-3" />
            </tr>
          </thead>
          <tbody className="divide-y divide-gray-100">
            {users.map((u) => (
              <tr key={u.id} className="hover:bg-gray-50">
                <td className="px-4 py-3 font-medium text-gray-900">
                  {u.nickname ?? '–'}
                </td>
                <td className="px-4 py-3 text-gray-600">{u.email}</td>
                <td className="px-4 py-3 text-gray-500">
                  {new Date(u.created_at).toLocaleDateString('ko-KR')}
                </td>
                <td className="px-4 py-3">
                  <span
                    className={`px-2 py-1 rounded text-xs font-medium ${
                      u.is_active
                        ? 'bg-green-100 text-green-700'
                        : 'bg-red-100 text-red-700'
                    }`}
                  >
                    {u.is_active ? '활성' : '비활성'}
                  </span>
                </td>
                <td className="px-4 py-3 text-right">
                  {u.is_active && (
                    <button
                      onClick={() => handleDeactivate(u)}
                      disabled={processingId === u.id}
                      className="px-3 py-1 bg-red-600 text-white rounded text-xs hover:bg-red-700 disabled:opacity-50"
                    >
                      {processingId === u.id ? '처리 중...' : '비활성화'}
                    </button>
                  )}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </>
  );
}
```

---

## 개발자 가드레일

### MUST 따라야 할 패턴

1. **`admin.py`에 추가**: 새 `admin_users.py` 파일 생성 금지. 기존 `admin.py`에 추가 (같은 router, prefix `/admin`).

2. **`CurrentAdmin` dep 필수**: `GET /admin/users`와 `PATCH /admin/users/{id}/deactivate` 모두 `CurrentAdmin` 필수. 어드민 아닌 사용자 → 403 자동 처리됨.

3. **`col()` 래퍼 사용**: `col(User.created_at).desc()` — SQLModel/SQLAlchemy 2.0 패턴. 이미 products에서 `col()` 사용 중, 동일 import.

4. **`revalidatePath('/users')`**: 비활성화 Server Action에서 Next.js 캐시 무효화.

5. **`await searchParams` 패턴**: 이 페이지는 searchParams 없으나, 향후 필터 추가 시를 위해 인지할 것. 현재 page.tsx는 단순 구조.

6. **자기 자신 비활성화 방지**: `user_id == current_admin.id` 체크 → 400. 어드민 계정 잠금 방지.

7. **`PATCH /deactivate`는 200 반환**: `apiDelete`(204 No Content)와 달리 `PATCH /deactivate`는 업데이트된 사용자 객체를 200으로 반환. `apiPatch<AdminUserItem>` 사용.

8. **`npm run build`**: TypeScript 검증 + Next.js 빌드 성공 필수.

9. **admin/AGENTS.md 준수**: `admin/` 폴더에 `AGENTS.md`(→ `CLAUDE.md`) 존재. "This is NOT the Next.js you know" 경고 있음. `node_modules/next/dist/docs/` 참조 필요 시 확인.

### MUST NOT

- 새 Alembic 마이그레이션 파일 생성 금지 — `is_active` 컬럼은 `001_initial_schema.py`에 이미 있음
- `auth.py`, `deps.py`의 `is_active` 체크 수정 금지 — 이미 올바르게 구현됨
- `admin.py` 외부에 `/admin/users` 엔드포인트 생성 금지
- `layout.tsx` 사이드바 수정 금지 — `/users` 링크 이미 있음

---

## 이전 스토리 학습사항 (Story 5.2)

1. **`admin.py`에 추가하는 패턴**: router prefix `/admin`이므로 함수 내 경로는 `/products`, `/users`로만 작성.

2. **`col()` 래퍼**: `col(User.created_at).desc()`, `col(User.nickname).ilike(...)` — SQLModel 2.0 필수.

3. **`await searchParams`**: Next.js 16.x에서 searchParams는 Promise. 현재 users 페이지는 searchParams 불필요하나 패턴 인지.

4. **Server Component + Client Component 분리**: `page.tsx`는 Server Component (데이터 페칭), `UsersTable.tsx`는 Client Component (버튼 상호작용).

5. **Server Action에서 `getAdminToken()`**: 인증 없으면 `{ error: '...' }` 반환. `redirect('/login')` 아님.

6. **`type: ignore[union-attr]` 패턴**: user가 None일 수 없으나 mypy 추론 실패 시 사용.

7. **`npm run build` 필수**: TypeScript 오류 없음 확인 후 완료.

8. **테스트 helper 패턴**: `_make_user`, `_make_admin`, `_admin_headers`, `_user_headers` 함수를 `test_admin_users.py`에 동일하게 복사해서 사용 (conftest에 없음). `test_admin_products.py`의 helper 참조.

---

## Dev Agent Record

### Agent Model Used

claude-sonnet-4-6

### Debug Log References

- `is_active` 컬럼 및 체크 로직이 이전 스토리에서 이미 구현됨 — 새 마이그레이션 불필요
- `col()` 래퍼: `col(User.created_at).desc()` — SQLModel 2.0 필수
- `PATCH /deactivate`는 200 반환 (204 아님) — `apiPatch` 사용
- 자기 자신 비활성화 방지 400 체크는 `session.get()` 이전에 수행 (DB 조회 불필요)

### Completion Notes List

- `admin.py`: `AdminUserItem` 스키마 + `GET /admin/users` + `PATCH /admin/users/{id}/deactivate` 추가
- `GET /admin/users`: role='admin' 계정 제외 필터링 (보안 리뷰 반영)
- `PATCH /deactivate`: 어드민 계정 보호 (`CANNOT_DEACTIVATE_ADMIN` 400) 추가 (보안 리뷰 반영)
- `session.add(user)` no-op 제거 (리뷰 반영)
- 14개 백엔드 테스트 추가 (어드민 필터링·어드민 비활성화 차단 테스트 포함), 전체 158개 통과
- `lib/api.ts`: `apiPatch<T>` 추가 (body 선택적, PATCH method)
- `types/index.ts`: `AdminUserItem`, `AdminUserListResponse` 추가; `ApiError` → `ApiErrorResponse` 이름 충돌 해소 (리뷰 반영)
- Next.js: Server Component(page.tsx) + Client Component(UsersTable.tsx) + Server Action(actions.ts) 생성
- `page.tsx`: `token!` → null 가드 + `redirect('/login')` 추가 (리뷰 반영)
- `(admin)/error.tsx`: 에러 바운더리 추가 (리뷰 반영)
- `npm run build` 성공, TypeScript 오류 없음, `/users` 페이지 동적 렌더링 확인

### File List

- backend/app/api/routes/admin.py (UPDATE — AdminUserItem 스키마, GET/PATCH /admin/users, 어드민 보호 로직)
- backend/tests/api/routes/test_admin_users.py (UPDATE — 어드민 필터링·보호 테스트 추가)
- admin/src/lib/api.ts (UPDATE — apiPatch 추가)
- admin/src/types/index.ts (UPDATE — AdminUserItem, AdminUserListResponse; ApiError→ApiErrorResponse)
- admin/src/app/(admin)/error.tsx (NEW)
- admin/src/app/(admin)/users/page.tsx (NEW)
- admin/src/app/(admin)/users/actions.ts (NEW)
- admin/src/app/(admin)/users/UsersTable.tsx (NEW)
