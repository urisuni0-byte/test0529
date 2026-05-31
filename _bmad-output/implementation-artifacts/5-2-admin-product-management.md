---
baseline_commit: NO_VCS
---

# Story 5.2 — 어드민 상품 관리

**Status:** review

## Story

As an admin operator,
I want to view all products and delete inappropriate ones,
So that I can maintain the quality and safety of marketplace listings.

## Acceptance Criteria

**Given** 어드민이 상품 목록 API를 호출할 때
**When** `GET /api/v1/admin/products`를 호출하면
**Then** 전체 상품 목록이 반환된다 (등록일·상태·판매자 닉네임 필터 지원)
**And** 응답에 상품 ID·제목·가격·상태·판매자 닉네임·등록일이 포함된다

**Given** 어드민이 특정 상품을 삭제할 때
**When** `DELETE /api/v1/admin/products/{id}`를 호출하면
**Then** 상품이 삭제되고 HTTP 204를 반환한다

**Given** 일반 사용자 JWT로 어드민 엔드포인트를 호출할 때
**When** `GET` 또는 `DELETE /api/v1/admin/products/*`를 호출하면
**Then** HTTP 403 `FORBIDDEN`을 반환한다

**Given** 어드민이 Next.js 상품 관리 페이지에 접근할 때
**When** `/products` 페이지가 로드되면
**Then** 상품 목록이 테이블로 표시된다 (제목·상태·판매자·등록일 컬럼)
**And** 상태·판매자 닉네임으로 필터링할 수 있다

**Given** 어드민이 상품 삭제 버튼을 클릭할 때
**When** 확인 다이얼로그에서 삭제를 선택하면
**Then** 삭제 API가 호출되고 목록에서 해당 상품이 즉시 제거된다 (페이지 새로고침)

## Tasks / Subtasks

- [x] Task 1: 백엔드 — `admin.py`에 상품 엔드포인트 추가 (AC: 1, 2, 3)
  - [x] `GET /admin/products` — 전체 상품 목록, 필터: `status`, `seller` (닉네임 ILIKE)
  - [x] `DELETE /admin/products/{product_id}` — 상품 삭제, `CurrentAdmin` 필수
  - [x] `AdminProductItem` 응답 스키마 (inline Pydantic BaseModel)
  - [x] 기존 `admin.py`에 추가

- [x] Task 2: 백엔드 테스트 10개 (AC: 1, 2, 3)
  - [x] `backend/tests/api/routes/test_admin_products.py` 신규 생성
  - [x] 목록 성공·필수필드·status필터·seller필터·어드민필수·미인증
  - [x] 삭제 성공·없는상품404·어드민필수·미인증

- [x] Task 3: Next.js — `lib/api.ts` + `types/index.ts` 업데이트 (AC: 4, 5)
  - [x] `apiDelete<T>(path, token)` 추가 (204 No Content 처리)
  - [x] `AdminProductItem`, `AdminProductListResponse` 타입 추가

- [x] Task 4: Next.js — 상품 관리 페이지 (AC: 4, 5)
  - [x] `page.tsx` — Server Component, `await searchParams`, apiGet → ProductsTable
  - [x] `actions.ts` — `deleteProductAction` + `revalidatePath('/products')`
  - [x] `ProductsTable.tsx` — Client Component, confirm dialog, 상태 배지
  - [x] `FilterForm.tsx` — Client Component, URL params 기반 필터

---

## Dev Notes

### 핵심 사항 요약

1. **백엔드**: `admin.py` 기존 파일에 추가 — prefix `/admin`이므로 엔드포인트는 `/admin/products`, `/admin/products/{id}`
2. **`CurrentAdmin` dep**: `from app.api.deps import CurrentAdmin, SessionDep` — 이미 `deps.py`에 있음
3. **상품 삭제**: 기존 `products.py`의 `DELETE /products/{id}`는 판매자 본인 전용. 어드민 버전은 `admin.py`에 별도 구현 (소유자 체크 없음)
4. **Next.js 데이터 흐름**: Server Component `page.tsx` → `getAdminToken()` → `apiGet('/admin/products?...')` → `ProductsTable.tsx` (Client Component)
5. **삭제 후 새로고침**: Server Action에서 `revalidatePath('/products')` 호출
6. **필터**: URL 쿼리 파라미터 `?status=SALE&seller=홍` → `page.tsx`의 `searchParams`로 수신 → API 쿼리에 전달
7. **`apiDelete`** 추가 필요: `lib/api.ts`에 아직 없음

### 프로젝트 구조

**Backend UPDATE:**
```
backend/app/api/routes/admin.py    ← GET/DELETE /admin/products 추가
backend/tests/api/routes/test_admin_products.py  (NEW)
```

**Next.js NEW/UPDATE:**
```
admin/src/lib/api.ts               (UPDATE — apiDelete 추가)
admin/src/types/index.ts           (UPDATE — AdminProductItem 타입)
admin/src/app/(admin)/products/page.tsx       (NEW — Server Component)
admin/src/app/(admin)/products/actions.ts     (NEW — Server Action)
admin/src/app/(admin)/products/ProductsTable.tsx  (NEW — Client Component)
admin/src/app/(admin)/products/FilterForm.tsx     (NEW — Client Component)
```

### 기존 코드 컨텍스트 (반드시 보존)

**`admin.py` 현재 상태 (추가 대상):**
```python
# 현재: POST /admin/auth/login 만 있음
# 추가: GET /admin/products + DELETE /admin/products/{product_id}

from app.api.deps import CurrentAdmin, SessionDep  # CurrentAdmin 추가
from app.models import Product, User  # Product, User 추가
```

**`Product` 모델 필드 (backend/app/models.py):**
```python
class Product(SQLModel, table=True):
    id: uuid.UUID
    seller_id: uuid.UUID  # FK → users.id
    title: str            # max_length=40
    price: int
    status: str           # SALE/RESERVED/SOLD
    created_at: datetime
    # ... image_urls, description, category, neighborhood_id
```

**`CurrentAdmin` (api/deps.py):**
```python
CurrentAdmin = Annotated[User, Depends(get_current_admin)]
# get_current_admin: get_current_user + role=="admin" 체크
# role 아닌 경우 403 FORBIDDEN 반환
```

**`lib/api.ts` 현재 상태 (수정 대상):**
```typescript
// 현재: apiPost, apiGet
// 추가:
export async function apiDelete<T = void>(path: string, token: string): Promise<T | null> {
  const res = await fetch(`${API_URL}${path}`, {
    method: 'DELETE',
    headers: { Authorization: `Bearer ${token}` },
    cache: 'no-store',
  });
  if (res.status === 204) return null;  // 204 No Content — body 없음
  return handleResponse<T>(res);
}
```

**`lib/auth.ts` `getAdminToken()` (Server Component에서 사용):**
```typescript
export async function getAdminToken(): Promise<string | undefined>
// 사용: const token = await getAdminToken();
```

**Next.js Server Action 패턴 (Story 5.1에서 확립):**
```typescript
'use server';
import { revalidatePath } from 'next/cache';

export async function deleteProductAction(productId: string): Promise<{ error?: string }> {
  const token = await getAdminToken();
  if (!token) return { error: '인증이 필요합니다.' };
  try {
    await apiDelete(`/admin/products/${productId}`, token);
    revalidatePath('/products');
    return {};
  } catch (err) {
    ...
  }
}
```

---

## API 계약

### GET /api/v1/admin/products

**인증**: `Authorization: Bearer {admin_jwt}` 필수

**Query Params (모두 선택):**
- `status`: `SALE` | `RESERVED` | `SOLD`
- `seller`: 판매자 닉네임 부분 일치 (ILIKE)

**Response 200:**
```json
{
  "items": [
    {
      "id": "uuid",
      "title": "아이폰 15",
      "price": 900000,
      "status": "SALE",
      "seller_nickname": "홍길동",
      "created_at": "2026-05-30T10:00:00Z"
    }
  ],
  "total": 42
}
```

---

### DELETE /api/v1/admin/products/{product_id}

**인증**: `Authorization: Bearer {admin_jwt}` 필수

- **204** — 삭제 성공 (빈 바디)
- **404 PRODUCT_NOT_FOUND** — 상품 없음
- **403 FORBIDDEN** — 일반 유저 접근

---

## 구현 상세

### 1. `admin.py` 추가 엔드포인트

```python
# admin.py 상단 imports에 추가:
import uuid
from typing import Any

from fastapi import Query  # 추가
from pydantic import BaseModel
from sqlmodel import col, select  # 추가

from app.api.deps import CurrentAdmin, SessionDep
from app.models import AccessTokenResponse, Product, User  # Product, User 추가


# ─── 상품 관리 스키마 ──────────────────────────────────────────────────────────

class AdminProductItem(BaseModel):
    id: uuid.UUID
    title: str
    price: int
    status: str
    seller_nickname: str | None
    created_at: datetime  # from datetime import datetime


# ─── GET /admin/products ──────────────────────────────────────────────────────

@router.get("/products")
def list_admin_products(
    session: SessionDep,
    current_admin: CurrentAdmin,
    status: str | None = Query(default=None),
    seller: str | None = Query(default=None),
) -> Any:
    """전체 상품 목록. 상태·판매자 닉네임으로 필터링 가능."""
    query = select(Product, User).join(User, User.id == Product.seller_id)

    if status:
        query = query.where(Product.status == status)
    if seller:
        # User.nickname ILIKE '%seller%'
        query = query.where(col(User.nickname).ilike(f"%{seller}%"))

    query = query.order_by(col(Product.created_at).desc())
    rows = session.exec(query).all()

    items = [
        AdminProductItem(
            id=product.id,
            title=product.title,
            price=product.price,
            status=product.status,
            seller_nickname=user.nickname,
            created_at=product.created_at,
        )
        for product, user in rows
    ]
    return {"items": items, "total": len(items)}


# ─── DELETE /admin/products/{product_id} ──────────────────────────────────────

@router.delete("/products/{product_id}", status_code=204, response_model=None)
def delete_admin_product(
    product_id: uuid.UUID,
    session: SessionDep,
    current_admin: CurrentAdmin,
) -> None:
    """어드민 상품 삭제. 소유자 체크 없음."""
    product = session.get(Product, product_id)
    if not product:
        raise HTTPException(
            status_code=404,
            detail={"detail": "상품을 찾을 수 없습니다.", "code": "PRODUCT_NOT_FOUND"},
        )
    session.delete(product)
    session.commit()
```

### 2. `admin/src/types/index.ts` — 타입 추가

기존 타입 뒤에 추가:

```typescript
export interface AdminProductItem {
  id: string;
  title: string;
  price: number;
  status: 'SALE' | 'RESERVED' | 'SOLD';
  seller_nickname: string | null;
  created_at: string;
}

export interface AdminProductListResponse {
  items: AdminProductItem[];
  total: number;
}

const STATUS_LABELS: Record<string, string> = {
  SALE: '판매중',
  RESERVED: '예약중',
  SOLD: '판매완료',
};
```

### 3. `admin/src/lib/api.ts` — `apiDelete` 추가

```typescript
export async function apiDelete<T = void>(
  path: string,
  token: string,
): Promise<T | null> {
  const res = await fetch(`${API_URL}${path}`, {
    method: 'DELETE',
    headers: { Authorization: `Bearer ${token}` },
    cache: 'no-store',
  });
  if (res.status === 204) return null; // No Content
  return handleResponse<T>(res);
}
```

### 4. `admin/src/app/(admin)/products/actions.ts`

```typescript
'use server';

import { revalidatePath } from 'next/cache';
import { apiDelete } from '@/lib/api';
import { getAdminToken } from '@/lib/auth';
import { ApiError } from '@/lib/api';

export interface ActionResult {
  error?: string;
}

export async function deleteProductAction(
  productId: string,
): Promise<ActionResult> {
  const token = await getAdminToken();
  if (!token) return { error: '인증이 필요합니다.' };

  try {
    await apiDelete(`/admin/products/${productId}`, token);
    revalidatePath('/products');
    return {};
  } catch (err) {
    if (err instanceof ApiError) {
      return { error: err.message };
    }
    return { error: '삭제 중 오류가 발생했습니다.' };
  }
}
```

### 5. `admin/src/app/(admin)/products/page.tsx`

```tsx
import { getAdminToken } from '@/lib/auth';
import { apiGet } from '@/lib/api';
import type { AdminProductListResponse } from '@/types';
import ProductsTable from './ProductsTable';
import FilterForm from './FilterForm';

interface SearchParams {
  status?: string;
  seller?: string;
}

export default async function ProductsPage({
  searchParams,
}: {
  searchParams: Promise<SearchParams>;
}) {
  const params = await searchParams;
  const token = await getAdminToken();

  const qs = new URLSearchParams();
  if (params.status) qs.set('status', params.status);
  if (params.seller) qs.set('seller', params.seller);

  const data = await apiGet<AdminProductListResponse>(
    `/admin/products${qs.size > 0 ? `?${qs}` : ''}`,
    token!,
  );

  return (
    <div>
      <div className="flex items-center justify-between mb-4">
        <h1 className="text-2xl font-bold text-gray-900">상품 관리</h1>
        <span className="text-sm text-gray-500">총 {data.total}개</span>
      </div>
      <FilterForm currentStatus={params.status} currentSeller={params.seller} />
      <ProductsTable products={data.items} />
    </div>
  );
}
```

### 6. `admin/src/app/(admin)/products/FilterForm.tsx`

```tsx
'use client';

import { useRouter } from 'next/navigation';
import { useState } from 'react';

interface FilterFormProps {
  currentStatus?: string;
  currentSeller?: string;
}

export default function FilterForm({ currentStatus, currentSeller }: FilterFormProps) {
  const router = useRouter();
  const [status, setStatus] = useState(currentStatus ?? '');
  const [seller, setSeller] = useState(currentSeller ?? '');

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    const qs = new URLSearchParams();
    if (status) qs.set('status', status);
    if (seller) qs.set('seller', seller);
    router.push(`/products${qs.size > 0 ? `?${qs}` : ''}`);
  };

  const handleReset = () => {
    setStatus('');
    setSeller('');
    router.push('/products');
  };

  return (
    <form onSubmit={handleSubmit} className="flex gap-3 mb-4 flex-wrap">
      <select
        value={status}
        onChange={(e) => setStatus(e.target.value)}
        className="px-3 py-2 border border-gray-300 rounded-md text-sm focus:outline-none focus:ring-2 focus:ring-blue-500"
      >
        <option value="">전체 상태</option>
        <option value="SALE">판매중</option>
        <option value="RESERVED">예약중</option>
        <option value="SOLD">판매완료</option>
      </select>

      <input
        type="text"
        value={seller}
        onChange={(e) => setSeller(e.target.value)}
        placeholder="판매자 닉네임"
        className="px-3 py-2 border border-gray-300 rounded-md text-sm focus:outline-none focus:ring-2 focus:ring-blue-500 w-36"
      />

      <button
        type="submit"
        className="px-4 py-2 bg-blue-600 text-white rounded-md text-sm hover:bg-blue-700"
      >
        검색
      </button>
      <button
        type="button"
        onClick={handleReset}
        className="px-4 py-2 bg-gray-200 text-gray-700 rounded-md text-sm hover:bg-gray-300"
      >
        초기화
      </button>
    </form>
  );
}
```

### 7. `admin/src/app/(admin)/products/ProductsTable.tsx`

```tsx
'use client';

import { useState } from 'react';
import { deleteProductAction } from './actions';
import type { AdminProductItem } from '@/types';

const STATUS_LABELS: Record<string, string> = {
  SALE: '판매중',
  RESERVED: '예약중',
  SOLD: '판매완료',
};

interface ProductsTableProps {
  products: AdminProductItem[];
}

export default function ProductsTable({ products }: ProductsTableProps) {
  const [deletingId, setDeletingId] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  const handleDelete = async (product: AdminProductItem) => {
    if (!confirm(`"${product.title}" 상품을 삭제하시겠습니까?`)) return;

    setDeletingId(product.id);
    setError(null);
    const result = await deleteProductAction(product.id);
    setDeletingId(null);
    if (result.error) setError(result.error);
  };

  if (products.length === 0) {
    return (
      <div className="text-center py-12 text-gray-500">
        검색 결과가 없습니다.
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
              <th className="text-left px-4 py-3 font-medium text-gray-600">제목</th>
              <th className="text-left px-4 py-3 font-medium text-gray-600">가격</th>
              <th className="text-left px-4 py-3 font-medium text-gray-600">상태</th>
              <th className="text-left px-4 py-3 font-medium text-gray-600">판매자</th>
              <th className="text-left px-4 py-3 font-medium text-gray-600">등록일</th>
              <th className="px-4 py-3" />
            </tr>
          </thead>
          <tbody className="divide-y divide-gray-100">
            {products.map((p) => (
              <tr key={p.id} className="hover:bg-gray-50">
                <td className="px-4 py-3 font-medium text-gray-900 max-w-[200px] truncate">
                  {p.title}
                </td>
                <td className="px-4 py-3 text-gray-700">
                  {p.price.toLocaleString()}원
                </td>
                <td className="px-4 py-3">
                  <span
                    className={`px-2 py-1 rounded text-xs font-medium ${
                      p.status === 'SALE'
                        ? 'bg-green-100 text-green-700'
                        : p.status === 'RESERVED'
                        ? 'bg-yellow-100 text-yellow-700'
                        : 'bg-gray-100 text-gray-600'
                    }`}
                  >
                    {STATUS_LABELS[p.status] ?? p.status}
                  </span>
                </td>
                <td className="px-4 py-3 text-gray-600">
                  {p.seller_nickname ?? '–'}
                </td>
                <td className="px-4 py-3 text-gray-500">
                  {new Date(p.created_at).toLocaleDateString('ko-KR')}
                </td>
                <td className="px-4 py-3 text-right">
                  <button
                    onClick={() => handleDelete(p)}
                    disabled={deletingId === p.id}
                    className="px-3 py-1 bg-red-600 text-white rounded text-xs hover:bg-red-700 disabled:opacity-50"
                  >
                    {deletingId === p.id ? '삭제 중...' : '삭제'}
                  </button>
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

1. **`admin.py`에 추가**: 새 `admin_products.py` 파일 생성 금지. 기존 `admin.py`에 추가 (같은 router, prefix `/admin`).

2. **`CurrentAdmin` dep**: `GET /admin/products`와 `DELETE /admin/products/{id}` 모두 필수. `CurrentAdmin`은 내부적으로 `CurrentUser` + role=admin 체크.

3. **JOIN으로 seller_nickname 조회**: `select(Product, User).join(User, User.id == Product.seller_id)` — N+1 방지.

4. **`col()` 래퍼**: `col(User.nickname).ilike(...)`, `col(Product.created_at).desc()` — SQLModel/SQLAlchemy 2.0 패턴.

5. **`apiDelete` 204 처리**: 응답 바디가 없으므로 `res.json()` 호출 금지. `res.status === 204`이면 null 반환.

6. **`revalidatePath('/products')`**: 삭제 Server Action에서 Next.js 캐시 무효화. 페이지 새로고침 대신 사용.

7. **`searchParams` async**: Next.js 16.x에서 `searchParams`는 Promise — `await searchParams` 필수.

8. **`datetime` import**: `admin.py`에 `AdminProductItem`의 `created_at` 필드에 `from datetime import datetime` 추가.

### MUST NOT

- `admin.py` 외부에 `/admin/products` 엔드포인트 생성 금지
- 기존 `products.py`의 `DELETE /products/{id}` 수정 금지 (판매자 전용 기존 동작 보존)
- `useActionState` 대신 일반 `useState` + async function으로 삭제 처리 (form이 아닌 버튼)

---

## 이전 스토리 학습사항 (Story 5.1)

1. **`await searchParams`**: Next.js 16.x에서 `searchParams`도 async. 반드시 `await searchParams` 사용.

2. **Server Component + Client Component 분리**: `page.tsx`는 Server Component (데이터 페칭), `ProductsTable.tsx`는 Client Component (삭제 버튼 상호작용).

3. **Server Action에서 `getAdminToken()`**: `await cookies()` → token 읽기. 인증 없으면 `{ error: '...' }` 반환.

4. **`type: ignore[union-attr]` 패턴**: backend에서 user가 None일 수 없지만 mypy가 추론 못할 때 사용 (Story 5.1 패턴).

5. **`npm run build`**: TypeScript 검증 + Next.js 빌드 성공 확인 필수.

---

## Dev Agent Record

### Agent Model Used

claude-sonnet-4-6

### Debug Log References

- `col()` wrapper: `col(User.nickname).ilike(...)`, `col(Product.created_at).desc()` — SQLModel 2.0 필수

### Completion Notes List

- `admin.py`: GET/DELETE /admin/products 추가, JOIN으로 seller_nickname 조회 (N+1 방지)
- 10개 백엔드 테스트, 144개 전체 통과
- `lib/api.ts`: `apiDelete` 추가 (204 No Content 처리)
- `types/index.ts`: AdminProductItem, AdminProductListResponse 추가
- Next.js: Server Component(page.tsx) + Client Components(ProductsTable, FilterForm) + Server Action(actions.ts)
- `await searchParams` (Next.js 16.x 필수)
- `npm run build` 성공, TypeScript 오류 없음

### File List

- backend/app/api/routes/admin.py (UPDATE — GET/DELETE /admin/products)
- backend/tests/api/routes/test_admin_products.py (NEW)
- admin/src/lib/api.ts (UPDATE — apiDelete)
- admin/src/types/index.ts (UPDATE — AdminProductItem, AdminProductListResponse)
- admin/src/app/(admin)/products/page.tsx (NEW)
- admin/src/app/(admin)/products/actions.ts (NEW)
- admin/src/app/(admin)/products/ProductsTable.tsx (NEW)
- admin/src/app/(admin)/products/FilterForm.tsx (NEW)
