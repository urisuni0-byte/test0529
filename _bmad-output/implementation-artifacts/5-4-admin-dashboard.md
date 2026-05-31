---
baseline_commit: NO_VCS
---

# Story 5.4 — 어드민 대시보드

**Status:** review

## Story

As an admin operator,
I want to see key operational metrics on the dashboard,
So that I can monitor the health and activity of the platform at a glance.

## Acceptance Criteria

**Given** 어드민이 대시보드 stats API를 호출할 때
**When** `GET /api/v1/admin/stats`를 호출하면
**Then** 다음 지표를 포함한 JSON을 반환한다: `total_users`, `total_products`, `new_users_today`, `new_products_today`, `active_chat_rooms`
**And** 각 수치는 PostgreSQL에서 실시간으로 집계된다

**Given** 어드민이 Next.js 대시보드 페이지에 접근할 때
**When** `/dashboard` 페이지가 로드되면
**Then** 5개 지표가 카드 형태로 표시된다
**And** 페이지 진입 시 최신 데이터를 로드한다

**Given** 어드민이 대시보드에서 사이드바 메뉴를 사용할 때
**When** "상품 관리" 또는 "사용자 관리"를 클릭하면
**Then** 해당 페이지로 이동한다 (이미 layout.tsx에 구현됨)

## Tasks / Subtasks

- [x] Task 1: 백엔드 — `admin.py`에 stats 엔드포인트 추가 (AC: 1)
  - [x] `AdminStats` Pydantic BaseModel 스키마 정의 (5개 필드)
  - [x] `GET /admin/stats` — 5개 집계 쿼리, `CurrentAdmin` 필수
  - [x] `total_users`: role != 'admin'인 전체 사용자 수
  - [x] `total_products`: 전체 상품 수
  - [x] `new_users_today`: 오늘(UTC) 가입한 사용자 수
  - [x] `new_products_today`: 오늘(UTC) 등록된 상품 수
  - [x] `active_chat_rooms`: 전체 chat_rooms 수 (메시지 존재 여부 무관)

- [x] Task 2: 백엔드 테스트 6개 (AC: 1)
  - [x] `backend/tests/api/routes/test_admin_stats.py` 신규 생성
  - [x] stats 성공 (5개 필드 포함)·어드민필수·미인증
  - [x] new_users_today 정확성 (오늘 가입 유저 반영)
  - [x] new_products_today 정확성 (오늘 등록 상품 반영)
  - [x] total_users에서 어드민 계정 제외 검증

- [x] Task 3: Next.js — `types/index.ts` + `dashboard/page.tsx` 업데이트 (AC: 2)
  - [x] `AdminStats` 타입 추가
  - [x] `dashboard/page.tsx` — Server Component, apiGet → 5개 StatsCard 렌더링
  - [x] `StatsCard` 컴포넌트 (인라인) — label + value 카드

---

## Dev Notes

### 프로젝트 구조

**Backend UPDATE:**
```
backend/app/api/routes/admin.py     ← GET /admin/stats 추가
backend/tests/api/routes/test_admin_stats.py   (NEW)
```

**Next.js UPDATE:**
```
admin/src/types/index.ts            (UPDATE — AdminStats 타입 추가)
admin/src/app/(admin)/dashboard/page.tsx   (UPDATE — 현재 placeholder, 실제 구현으로 교체)
```

### 기존 코드 컨텍스트 — 반드시 준수

**`admin.py` 현재 상태 (Story 5.1~5.3 구현 완료):**

```python
# 현재 엔드포인트:
#   POST /admin/auth/login
#   GET  /admin/products
#   DELETE /admin/products/{product_id}
#   GET  /admin/users
#   PATCH /admin/users/{user_id}/deactivate
#
# 추가할 것:
#   GET  /admin/stats

# 현재 import 상태 (이미 있음):
from app.models import AccessTokenResponse, Product, User
# 추가 필요:
from app.models import ChatRoom  # chat_rooms 카운트에 필요
from datetime import date, timezone  # 오늘 날짜 비교에 필요
from sqlmodel import func  # COUNT 집계에 필요
```

**`User` 모델 (models.py):**
```python
class User(SQLModel, table=True):
    role: str           # 'user' | 'admin' — total_users는 role != 'admin' 필터
    created_at: datetime  # timezone-aware — new_users_today 비교 대상
    is_active: bool
```

**`Product` 모델 (models.py):**
```python
class Product(SQLModel, table=True):
    created_at: datetime  # timezone-aware — new_products_today 비교 대상
```

**`ChatRoom` 모델 (models.py):**
```python
class ChatRoom(SQLModel, table=True):
    __tablename__ = "chat_rooms"
    id: uuid.UUID
    product_id: uuid.UUID
    created_at: datetime
    # active_chat_rooms = SELECT COUNT(*) FROM chat_rooms
```

**오늘 날짜 계산 패턴 (UTC 기준):**
```python
from datetime import datetime, date, timezone

# 오늘 UTC 자정 (00:00:00)
today_start = datetime.combine(date.today(), datetime.min.time(), tzinfo=timezone.utc)

# WHERE created_at >= today_start
```

**SQLModel func.count() 패턴:**
```python
from sqlmodel import func, select

# 전체 카운트
total = session.exec(select(func.count()).select_from(User)).one()

# 조건부 카운트
count = session.exec(
    select(func.count()).select_from(User).where(User.role != "admin")
).one()

# 날짜 필터
new_today = session.exec(
    select(func.count()).select_from(User)
    .where(User.role != "admin")
    .where(User.created_at >= today_start)
).one()
```

### `dashboard/page.tsx` 현재 상태 (placeholder — 교체 대상)

```tsx
// 현재:
export default function DashboardPage() {
  return (
    <div>
      <h1 className="text-2xl font-bold text-gray-900 mb-2">대시보드</h1>
      <p className="text-gray-500 text-sm">Story 5.4에서 운영 지표가 구현됩니다.</p>
    </div>
  );
}
// → 전체를 교체. async Server Component로 변환, apiGet → 카드 렌더링
```

**주의:** 현재 page.tsx는 `async`가 없는 sync 함수. `apiGet` 호출을 위해 `async`로 변환 필수.

---

## API 계약

### GET /api/v1/admin/stats

**인증**: `Authorization: Bearer {admin_jwt}` 필수

**Response 200:**
```json
{
  "total_users": 1234,
  "total_products": 567,
  "new_users_today": 12,
  "new_products_today": 8,
  "active_chat_rooms": 89
}
```

---

## 구현 상세

### 1. `admin.py` — stats 엔드포인트 추가

```python
# import 추가 (상단에):
from datetime import date, timezone
from app.models import ..., ChatRoom  # ChatRoom 추가
from sqlmodel import col, func, select  # func 추가

# AdminStats 스키마:
class AdminStats(BaseModel):
    total_users: int
    total_products: int
    new_users_today: int
    new_products_today: int
    active_chat_rooms: int


@router.get("/stats", response_model=AdminStats)
def get_admin_stats(
    session: SessionDep,
    current_admin: CurrentAdmin,
) -> Any:
    """운영 지표 실시간 집계."""
    today_start = datetime.combine(date.today(), datetime.min.time(), tzinfo=timezone.utc)

    total_users = session.exec(
        select(func.count()).select_from(User).where(User.role != "admin")
    ).one()

    total_products = session.exec(
        select(func.count()).select_from(Product)
    ).one()

    new_users_today = session.exec(
        select(func.count()).select_from(User)
        .where(User.role != "admin")
        .where(User.created_at >= today_start)
    ).one()

    new_products_today = session.exec(
        select(func.count()).select_from(Product)
        .where(Product.created_at >= today_start)
    ).one()

    active_chat_rooms = session.exec(
        select(func.count()).select_from(ChatRoom)
    ).one()

    return AdminStats(
        total_users=total_users,
        total_products=total_products,
        new_users_today=new_users_today,
        new_products_today=new_products_today,
        active_chat_rooms=active_chat_rooms,
    )
```

### 2. `admin/src/types/index.ts` — AdminStats 타입 추가

기존 `AdminUserListResponse` 아래에 추가:
```typescript
export interface AdminStats {
  total_users: number;
  total_products: number;
  new_users_today: number;
  new_products_today: number;
  active_chat_rooms: number;
}
```

### 3. `admin/src/app/(admin)/dashboard/page.tsx` — 전체 교체

```tsx
import { redirect } from 'next/navigation';
import { getAdminToken } from '@/lib/auth';
import { apiGet } from '@/lib/api';
import type { AdminStats } from '@/types';

interface StatCardProps {
  label: string;
  value: number;
}

function StatsCard({ label, value }: StatCardProps) {
  return (
    <div className="bg-white rounded-lg shadow p-6">
      <p className="text-sm text-gray-500 mb-1">{label}</p>
      <p className="text-3xl font-bold text-gray-900">{value.toLocaleString()}</p>
    </div>
  );
}

export default async function DashboardPage() {
  const token = await getAdminToken();
  if (!token) redirect('/login');

  const stats = await apiGet<AdminStats>('/admin/stats', token);

  return (
    <div>
      <h1 className="text-2xl font-bold text-gray-900 mb-6">대시보드</h1>
      <div className="grid grid-cols-2 gap-4 lg:grid-cols-3">
        <StatsCard label="총 가입자" value={stats.total_users} />
        <StatsCard label="총 상품 수" value={stats.total_products} />
        <StatsCard label="오늘 신규 가입" value={stats.new_users_today} />
        <StatsCard label="오늘 신규 상품" value={stats.new_products_today} />
        <StatsCard label="활성 채팅방" value={stats.active_chat_rooms} />
      </div>
    </div>
  );
}
```

---

## 개발자 가드레일

### MUST 따라야 할 패턴

1. **`admin.py`에 추가**: 신규 파일 생성 금지. 기존 `admin.py`에 추가.

2. **`func.count()` 패턴**: `select(func.count()).select_from(Model).where(...)` — `.one()`으로 단일 int 반환.

3. **UTC 기준 오늘 날짜**: `datetime.combine(date.today(), datetime.min.time(), tzinfo=timezone.utc)` — DB 컬럼이 `TIMESTAMP WITH TIME ZONE`이므로 timezone-aware datetime 사용.

4. **`total_users`와 `new_users_today`에 `role != 'admin'` 필터**: 어드민 계정 제외 (Story 5.3 패턴 일관성).

5. **`active_chat_rooms` 정의**: chat_rooms 테이블 전체 COUNT. "활성" 기준은 메시지 존재 여부가 아닌 채팅방 생성 수 (MVP 단순화).

6. **`dashboard/page.tsx`는 전체 교체**: 현재 sync 함수 → async Server Component로 변환. 기존 placeholder 텍스트 제거.

7. **`token!` 금지**: `if (!token) redirect('/login')` 패턴 사용 (Story 5.3 리뷰 반영).

8. **`from app.models import ..., ChatRoom` 추가**: `admin.py` import에 ChatRoom 추가 필수.

### MUST NOT

- `admin.py` 외부에 `/admin/stats` 엔드포인트 생성 금지
- `new_users_today` 등에서 Python `datetime.now().date()`로 날짜 비교 금지 — timezone 불일치 발생. 반드시 UTC aware datetime 사용
- `layout.tsx` 수정 금지 — 사이드바 네비게이션 이미 완성됨

---

## 이전 스토리 학습사항 (Story 5.3 리뷰 반영)

1. **`token!` 대신 null 가드**: `const token = await getAdminToken(); if (!token) redirect('/login');`

2. **`(admin)/error.tsx` 존재**: Story 5.3에서 추가됨 — `dashboard/page.tsx`의 apiGet 오류도 이 바운더리가 처리함. 별도 error.tsx 불필요.

3. **`admin.py`에 추가**: 기존 import 라인에 `ChatRoom` 추가, `func` 추가.

4. **테스트 helper 패턴**: `test_admin_stats.py`에 `_make_user`, `_make_admin`, `_admin_headers`, `_user_headers`, `_get_dong_id`, `_create_product` 함수 복사 (conftest에 없음). `test_admin_products.py` 참조.

5. **`npm run build` 필수**: TypeScript 오류 없음 확인 후 완료.

---

## Dev Agent Record

### Agent Model Used

claude-sonnet-4-6

### Debug Log References

- `date.today()`는 로컬 시각 기준 → UTC 기준 오늘 자정이 필요하므로 `datetime.now(timezone.utc).replace(hour=0, minute=0, second=0, microsecond=0)` 사용. 테스트 환경에서 `date.today()` 방식은 timezone 불일치로 실패함.
- `func.count()` 패턴: `select(func.count()).select_from(Model).where(...)` → `.one()` 으로 int 반환

### Completion Notes List

- `admin.py`: `AdminStats` 스키마 + `GET /admin/stats` 추가. `func.count()` 5개 쿼리, UTC 기준 오늘 날짜 필터
- 6개 백엔드 테스트 추가 (어드민 필터·UTC 오늘 경계 검증 포함), 전체 164개 통과
- `types/index.ts`: `AdminStats` 타입 추가
- `dashboard/page.tsx`: placeholder 제거, async Server Component + `StatsCard` 인라인 컴포넌트로 교체
- `npm run build` 성공, TypeScript 오류 없음, `/dashboard` 동적 렌더링 확인

### File List

- backend/app/api/routes/admin.py (UPDATE — AdminStats 스키마, GET /admin/stats)
- backend/tests/api/routes/test_admin_stats.py (NEW)
- admin/src/types/index.ts (UPDATE — AdminStats 타입 추가)
- admin/src/app/(admin)/dashboard/page.tsx (UPDATE — placeholder → async Server Component)
