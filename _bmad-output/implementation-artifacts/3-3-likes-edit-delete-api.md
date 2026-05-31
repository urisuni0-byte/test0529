---
baseline_commit: NO_VCS
---

# Story 3.3 — 관심 & 상품 수정/삭제 API

**Status:** done

## Story

As a developer,
I want to implement likes, product edit, and delete API endpoints,
So that buyers can save items and sellers can manage their listings.

## Acceptance Criteria

**Given** 아키텍처 마이그레이션을 실행할 때
**When** `alembic upgrade head`를 실행하면
**Then** `likes` 테이블이 생성된다 (user_id, product_id, created_at, 복합 PK = UNIQUE 제약)

**Given** 인증된 사용자가 관심을 등록할 때
**When** `POST /api/v1/products/{id}/likes`를 호출하면
**Then** likes 테이블에 저장되고 HTTP 201을 반환한다
**And** 동일 사용자의 중복 관심 등록 시 HTTP 409 `LIKE_ALREADY_EXISTS`를 반환한다

**Given** 인증된 사용자가 관심을 해제할 때
**When** `DELETE /api/v1/products/{id}/likes`를 호출하면
**Then** likes 레코드가 삭제되고 HTTP 204를 반환한다
**And** 관심 등록되지 않은 상품에 해제를 시도하면 HTTP 404 `LIKE_NOT_FOUND`를 반환한다

**Given** 판매자가 본인 상품을 수정할 때
**When** `PATCH /api/v1/products/{id}`로 변경할 필드를 전송하면
**Then** 해당 필드만 업데이트되고 수정된 상품(ProductDetail)을 반환한다
**And** 타인의 상품 수정 시도 시 HTTP 403 `FORBIDDEN`을 반환한다

**Given** 판매자가 본인 상품을 삭제할 때
**When** `DELETE /api/v1/products/{id}`를 호출하면
**Then** 상품이 삭제되고 HTTP 204를 반환한다
**And** 타인의 상품 삭제 시도 시 HTTP 403 `FORBIDDEN`을 반환한다

## Tasks / Subtasks

- [x] Task 1: Alembic 마이그레이션 007 — likes 테이블 (AC: 1)
  - [x] `backend/app/alembic/versions/007_likes_table.py` 생성
  - [x] `likes` 테이블: user_id UUID, product_id UUID, created_at TIMESTAMP
  - [x] FK: `user_id → users.id ondelete=CASCADE`, `product_id → products.id ondelete=CASCADE`
  - [x] 복합 PK(user_id, product_id) = UNIQUE 제약 역할
  - [x] 인덱스: `idx_likes_product_id` (like_count 집계 쿼리 최적화)
  - [x] `uv run alembic upgrade head` 실행 확인

- [x] Task 2: `Like` DB 모델 + `ProductUpdate` 스키마 추가 (AC: 1, 4)
  - [x] `backend/app/models.py`에 `Like(SQLModel, table=True)` 추가
  - [x] `ProductUpdate` 스키마 추가 (title/price/description/status 선택 필드)
  - [x] status 유효성 검사: SALE/RESERVED/SOLD 외 값 → 422

- [x] Task 3: `backend/app/api/routes/likes.py` 신규 생성 (AC: 2, 3)
  - [x] `POST /{product_id}/likes` → 201 (IntegrityError → 409)
  - [x] `DELETE /{product_id}/likes` → 204 (없으면 404)
  - [x] `backend/app/api/main.py`에 likes 라우터 등록

- [x] Task 4: `backend/app/api/routes/products.py` 수정 (AC: 4, 5 + like_count 실제 집계)
  - [x] `PATCH /{product_id}` — 부분 수정 (판매자 본인만, `exclude_unset=True`)
  - [x] `DELETE /{product_id}` — 삭제 (판매자 본인만)
  - [x] `GET /products` 피드: `like_count` TODO → likes 테이블 집계 (배치 쿼리)
  - [x] `GET /products/{id}` 상세: `like_count` TODO → likes 테이블 집계
  - [x] `POST /products` 신규 등록: `like_count=0` 유지 (신규 상품은 likes 없음)

- [x] Task 5: 테스트 추가 (AC: 1~5)
  - [x] `backend/tests/api/routes/test_likes.py` 신규 생성
  - [x] `test_products.py` docstring 업데이트 (like_count 0 고정 설명 제거)

---

## Dev Notes

### 핵심 사항 요약

1. **백엔드 전용 스토리** — Flutter 변경 없음
2. **migration 007 = new head** — 현재 head는 006
3. **Like 복합 PK** — `user_id + product_id`가 PK이므로 UNIQUE 제약 내장
4. **likes.py 별도 파일** — 아키텍처 명세에 `routes/likes.py` 존재 (products.py에 넣지 말 것)
5. **like_count 배치 집계** — GET /products 피드에서 N+1 방지: 상품 ID 목록으로 한 번에 집계
6. **R2 이미지 비정리** — 상품 삭제 시 R2 이미지는 MVP에서 정리 안 함 (알려진 한계)
7. **sqlmodel_update 패턴** — `PATCH /users/me`(users.py:32)와 동일 패턴 사용

### 프로젝트 구조

**NEW — 새로 생성:**
```
backend/app/alembic/versions/007_likes_table.py
backend/app/api/routes/likes.py
backend/tests/api/routes/test_likes.py
```

**UPDATE — 수정:**
```
backend/app/models.py           ← Like 모델, ProductUpdate 스키마 추가
backend/app/api/routes/products.py  ← like_count 집계 + PATCH/{id} + DELETE/{id}
backend/app/api/main.py         ← likes 라우터 등록
backend/tests/api/routes/test_products.py  ← docstring 업데이트
```

### 기존 코드 컨텍스트 (반드시 보존)

**`products.py` 현재 상태:**
- `POST /images`, `POST /`, `GET /`, `GET /{product_id}` — 4개 엔드포인트 존재
- 3개의 `like_count=0` TODO 주석 → Task 4에서 실제 집계로 교체
- `POST /` 의 `like_count=0` — 신규 등록 시 likes 없으므로 교체 불필요

**`users.py:32`의 partial update 패턴:**
```python
update_data = user_in.model_dump(exclude_unset=True)
current_user.sqlmodel_update(update_data)
session.add(current_user)
session.commit()
session.refresh(current_user)
```
→ `ProductUpdate`도 동일하게 `exclude_unset=True` + `product.sqlmodel_update(...)` 사용

**`models.py` 기존 SQLModel 패턴:**
- `__tablename__` 반드시 명시 (SQLModel 기본값은 단수)
- `DateTime(timezone=True)` + `sa_type` 인자 패턴
- FK: `Field(foreign_key="table.column")`

**`alembic/versions/005_products_table.py` 패턴:**
- `sa.Uuid()` (SQLAlchemy 2.0 스타일, `sa.UUID(as_uuid=True)` 아님)
- `sa.ForeignKey("table.id", ondelete="CASCADE")` 인라인 방식
- `sa.TIMESTAMP(timezone=True)` + `server_default=sa.text("now()")`

**test_products.py 기존 헬퍼:**
- `_make_seller(db)` — 판매자 User 생성
- `_get_dong_id(client)` — 첫 번째 dong 레벨 동네 ID
- `_make_auth_headers(user)` — JWT Bearer 헤더
- `_create_product(db, seller_id, neighborhood_id, ...)` — DB 직접 상품 생성

---

## API 계약

### POST /api/v1/products/{product_id}/likes

**인증 필수.** 응답 바디 없음.

- **201** — 관심 등록 성공 (빈 바디)
- **409 LIKE_ALREADY_EXISTS** — 이미 관심 등록됨
- **404 PRODUCT_NOT_FOUND** — 상품 없음
- **401 UNAUTHORIZED** — 미인증

---

### DELETE /api/v1/products/{product_id}/likes

**인증 필수.** 응답 바디 없음.

- **204** — 관심 해제 성공
- **404 LIKE_NOT_FOUND** — 관심 등록되지 않은 상품
- **401 UNAUTHORIZED** — 미인증

---

### PATCH /api/v1/products/{product_id}

**인증 필수.** 판매자 본인만.

**Request (모든 필드 선택):**
```json
{
  "title": "새 제목",
  "price": 50000,
  "description": "새 설명",
  "status": "RESERVED"
}
```

- **200** — 수정된 `ProductDetail` 반환
- **403 FORBIDDEN** — 타인 상품
- **404 PRODUCT_NOT_FOUND** — 상품 없음
- **422** — status 유효하지 않음
- **401 UNAUTHORIZED** — 미인증

---

### DELETE /api/v1/products/{product_id}

**인증 필수.** 판매자 본인만.

- **204** — 삭제 성공 (빈 바디)
- **403 FORBIDDEN** — 타인 상품
- **404 PRODUCT_NOT_FOUND** — 상품 없음
- **401 UNAUTHORIZED** — 미인증

---

## 구현 상세

### 1. `backend/app/alembic/versions/007_likes_table.py`

```python
"""create likes table

Revision ID: 007
Revises: 006
Create Date: 2026-05-30
"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "007"
down_revision: Union[str, None] = "006"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "likes",
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("product_id", sa.Uuid(), nullable=False),
        sa.Column(
            "created_at",
            sa.TIMESTAMP(timezone=True),
            nullable=False,
            server_default=sa.text("now()"),
        ),
        sa.ForeignKeyConstraint(["product_id"], ["products.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("user_id", "product_id"),
    )
    # like_count 집계 쿼리 최적화 (WHERE product_id=? GROUP BY product_id)
    op.create_index("idx_likes_product_id", "likes", ["product_id"])


def downgrade() -> None:
    op.drop_index("idx_likes_product_id", table_name="likes")
    op.drop_table("likes")
```

### 2. `backend/app/models.py` — Like 모델 + ProductUpdate 스키마 추가

파일 끝에 추가:

```python
# ─── Like Table Model ─────────────────────────────────────────────────────────

class Like(SQLModel, table=True):
    __tablename__ = "likes"  # type: ignore[assignment]

    user_id: uuid.UUID = Field(foreign_key="users.id", primary_key=True)
    product_id: uuid.UUID = Field(foreign_key="products.id", primary_key=True)
    created_at: datetime = Field(
        default_factory=_utcnow,
        sa_type=DateTime(timezone=True),  # type: ignore[call-arg]
    )


# ─── Product Update Schema ────────────────────────────────────────────────────

class ProductUpdate(SQLModel):
    """PATCH /products/{id} — 판매자가 수정 가능한 필드만 노출.

    None 기본값 = 요청에서 해당 필드 생략 (exclude_unset 패턴).
    """
    title: str | None = Field(default=None, max_length=40)
    price: int | None = Field(default=None, ge=0)
    description: str | None = None
    status: str | None = None

    @field_validator("status", mode="before")
    @classmethod
    def validate_status(cls, v: object) -> object:
        if v is not None and v not in {s.value for s in ProductStatus}:
            valid = ", ".join(s.value for s in ProductStatus)
            raise ValueError(f"유효한 상태값: {valid}")
        return v
```

### 3. `backend/app/api/routes/likes.py` (NEW)

```python
import uuid
from typing import Any

from fastapi import APIRouter, HTTPException
from sqlalchemy.exc import IntegrityError
from sqlmodel import select

from app.api.deps import CurrentUser, SessionDep
from app.models import Like, Product

router = APIRouter(prefix="/products", tags=["likes"])


@router.post("/{product_id}/likes", status_code=201, response_model=None)
def like_product(
    product_id: uuid.UUID,
    session: SessionDep,
    current_user: CurrentUser,
) -> Any:
    """관심 등록. 이미 등록된 경우 409."""
    if not session.get(Product, product_id):
        raise HTTPException(
            status_code=404,
            detail={"detail": "상품을 찾을 수 없습니다.", "code": "PRODUCT_NOT_FOUND"},
        )
    like = Like(user_id=current_user.id, product_id=product_id)
    session.add(like)
    try:
        session.commit()
    except IntegrityError:
        session.rollback()
        raise HTTPException(
            status_code=409,
            detail={"detail": "이미 관심 등록된 상품입니다.", "code": "LIKE_ALREADY_EXISTS"},
        )
    return None


@router.delete("/{product_id}/likes", status_code=204, response_model=None)
def unlike_product(
    product_id: uuid.UUID,
    session: SessionDep,
    current_user: CurrentUser,
) -> Any:
    """관심 해제. 등록하지 않은 경우 404."""
    like = session.exec(
        select(Like).where(
            Like.product_id == product_id,
            Like.user_id == current_user.id,
        )
    ).first()
    if not like:
        raise HTTPException(
            status_code=404,
            detail={"detail": "관심 등록 내역을 찾을 수 없습니다.", "code": "LIKE_NOT_FOUND"},
        )
    session.delete(like)
    session.commit()
    return None
```

### 4. `backend/app/api/main.py` — likes 라우터 등록

```python
from app.api.routes import auth, likes, neighborhoods, products, users

api_router = APIRouter()
api_router.include_router(auth.router)
api_router.include_router(users.router)
api_router.include_router(neighborhoods.router)
api_router.include_router(products.router)
api_router.include_router(likes.router)
```

### 5. `backend/app/api/routes/products.py` — like_count 집계 + PATCH + DELETE

**imports 추가:**
```python
from sqlmodel import func, select

from app.models import (
    ...
    Like,
    ProductUpdate,
)
```

**GET /products (피드) — like_count 배치 집계:**
```python
# ... 기존 products 쿼리 후 ...

# 배치 like_count 집계 (N+1 방지)
product_ids = [p.id for p in products]
if product_ids:
    like_count_rows = session.exec(
        select(Like.product_id, func.count(Like.user_id).label("cnt"))
        .where(Like.product_id.in_(product_ids))
        .group_by(Like.product_id)
    ).all()
    like_counts: dict[uuid.UUID, int] = {row[0]: row[1] for row in like_count_rows}
else:
    like_counts = {}

items = [
    ProductFeedItem(
        id=p.id,
        seller_id=p.seller_id,
        title=p.title,
        price=p.price,
        created_at=p.created_at,
        like_count=like_counts.get(p.id, 0),  # ← TODO 제거
        status=p.status,
        thumbnail_url=p.image_urls[0] if p.image_urls else None,
    )
    for p in products
]
```

**GET /products/{id} (상세) — like_count 단건 집계:**
```python
# product 조회 후
like_count = session.exec(
    select(func.count()).select_from(Like).where(Like.product_id == product.id)
).one()

seller = session.get(User, product.seller_id)
return ProductDetail(
    ...
    like_count=like_count,  # ← TODO 제거
    ...
)
```

**PATCH /{product_id} — 추가:**
```python
@router.patch("/{product_id}", response_model=ProductDetail)
def update_product(
    product_id: uuid.UUID,
    body: ProductUpdate,
    session: SessionDep,
    current_user: CurrentUser,
) -> Any:
    """부분 수정. 판매자 본인만 가능."""
    product = session.get(Product, product_id)
    if not product:
        raise HTTPException(
            status_code=404,
            detail={"detail": "상품을 찾을 수 없습니다.", "code": "PRODUCT_NOT_FOUND"},
        )
    if product.seller_id != current_user.id:
        raise HTTPException(
            status_code=403,
            detail={"detail": "권한이 없습니다.", "code": "FORBIDDEN"},
        )

    update_data = body.model_dump(exclude_unset=True)
    product.sqlmodel_update(update_data)
    session.add(product)
    session.commit()
    session.refresh(product)

    seller = session.get(User, product.seller_id)
    like_count = session.exec(
        select(func.count()).select_from(Like).where(Like.product_id == product.id)
    ).one()
    return ProductDetail(
        id=product.id,
        seller_id=product.seller_id,
        title=product.title,
        price=product.price,
        description=product.description,
        category=product.category,
        image_urls=product.image_urls,
        created_at=product.created_at,
        like_count=like_count,
        status=product.status,
        seller_nickname=seller.nickname if seller else None,
    )


@router.delete("/{product_id}", status_code=204, response_model=None)
def delete_product(
    product_id: uuid.UUID,
    session: SessionDep,
    current_user: CurrentUser,
) -> Any:
    """삭제. 판매자 본인만 가능. R2 이미지는 MVP에서 별도 정리 안 함."""
    product = session.get(Product, product_id)
    if not product:
        raise HTTPException(
            status_code=404,
            detail={"detail": "상품을 찾을 수 없습니다.", "code": "PRODUCT_NOT_FOUND"},
        )
    if product.seller_id != current_user.id:
        raise HTTPException(
            status_code=403,
            detail={"detail": "권한이 없습니다.", "code": "FORBIDDEN"},
        )
    session.delete(product)
    session.commit()
    return None
```

**최종 라우트 순서 (products.py 전체):**
```
POST  /images           기존
POST  /                 기존
GET   /                 기존
PATCH /{product_id}     신규 ← GET /{product_id} 앞에 선언 불필요 (다른 메서드)
DELETE /{product_id}    신규
GET   /{product_id}     기존
```

FastAPI는 메서드가 다르면 순서 무관하게 매칭됨 — `/product_id` 경로 변수와 `/images` 경로 충돌 없음.

---

## 테스트 요구사항

### `test_likes.py` 구조

```python
# backend/tests/api/routes/test_likes.py

def _make_buyer(db): ...  # _make_seller와 동일 패턴, 다른 email

class TestLikeProduct:
    def test_like_product_success(client, db)  # 201
    def test_like_duplicate_returns_409(client, db)  # 409 LIKE_ALREADY_EXISTS
    def test_like_nonexistent_product_returns_404(client, db)  # 404 PRODUCT_NOT_FOUND
    def test_like_requires_auth(client, db)  # 401
    def test_like_count_increments_in_feed(client, db)  # GET /products like_count 검증
    def test_like_count_increments_in_detail(client, db)  # GET /products/{id} like_count 검증

class TestUnlikeProduct:
    def test_unlike_product_success(client, db)  # 204
    def test_unlike_not_liked_returns_404(client, db)  # 404 LIKE_NOT_FOUND
    def test_unlike_requires_auth(client, db)  # 401

class TestUpdateProduct:
    def test_update_title_only(client, db)  # exclude_unset 확인
    def test_update_status_to_reserved(client, db)
    def test_update_invalid_status_returns_422(client, db)
    def test_update_by_non_seller_returns_403(client, db)
    def test_update_nonexistent_returns_404(client, db)
    def test_update_requires_auth(client, db)

class TestDeleteProduct:
    def test_delete_own_product(client, db)  # 204
    def test_delete_removes_product_from_db(client, db)  # 이후 GET → 404
    def test_delete_by_non_seller_returns_403(client, db)
    def test_delete_nonexistent_returns_404(client, db)
    def test_delete_requires_auth(client, db)
    def test_delete_cascades_likes(client, db)  # 상품 삭제 시 likes도 삭제
```

### like_count 집계 테스트 패턴

```python
# like_count가 실제로 집계되는지 확인
def test_like_count_increments_in_detail(self, client, db):
    seller = _make_seller(db)
    buyer = _make_buyer(db)
    dong_id = _get_dong_id(client)
    product = _create_product(db, seller.id, dong_id)

    # 좋아요 전
    resp = client.get(f"{BASE}/products/{product.id}")
    assert resp.json()["like_count"] == 0

    # 좋아요 후
    client.post(
        f"{BASE}/products/{product.id}/likes",
        headers=_make_auth_headers(buyer),
    )
    resp = client.get(f"{BASE}/products/{product.id}")
    assert resp.json()["like_count"] == 1
```

---

## 개발자 가드레일

### MUST 따라야 할 패턴

1. **`sqlmodel_update` 패턴**: `product.sqlmodel_update(body.model_dump(exclude_unset=True))` — `PATCH /users/me`(users.py:32-34)와 동일. `setattr` 루프 사용 금지.

2. **`IntegrityError` 처리**: `session.add(like) → try: session.commit() except IntegrityError: session.rollback() → 409`. 커밋 전 duplicate 체크 쿼리 금지 (race condition).

3. **배치 like_count 집계**: GET /products 피드에서 개별 상품마다 SELECT COUNT 호출 금지. 상품 ID 목록으로 한 번에 GROUP BY 집계.

4. **에러 응답 형식**: `{"detail": "...", "code": "..."}` — 모든 에러에 일관 적용.

5. **PATCH 순서**: `product.sqlmodel_update(...)` → `session.add()` → `session.commit()` → `session.refresh()` → `ProductDetail` 반환. refresh 없이 반환하면 stale 데이터.

6. **likes.py 별도 파일**: products.py에 likes 엔드포인트 추가 금지. 아키텍처 명세대로 별도 파일.

7. **migration 파일명 패턴**: `007_likes_table.py` — 3자리 숫자 prefix + 설명.

### MUST NOT

- `GET` 엔드포인트에서 `like_count` 집계 없이 0 하드코딩 — TODO 주석 제거 필요
- `PATCH`에 `PUT` 사용 — 아키텍처 규칙: PATCH만
- migration에서 `sa.UUID(as_uuid=True)` 사용 — 프로젝트는 `sa.Uuid()` 사용 (005 마이그레이션 패턴)
- 상품 삭제 시 R2 이미지 삭제 구현 — MVP 범위 밖

### 실행 확인

```bash
cd backend
uv run alembic upgrade head        # 007 마이그레이션 확인
uv run pytest -q                   # 전체 테스트 (61개 기존 + 신규)
uv run ruff check app/ tests/      # 린트
```

---

## 이전 스토리 학습사항 (Story 3.1 + 코드리뷰)

1. **에러 응답 형식**: `raise HTTPException(status_code=..., detail={"detail":"...", "code":"..."})` — dict 형식 일관 적용.

2. **`CurrentUser`/`SessionDep` import**: `from app.api.deps import CurrentUser, SessionDep` — deps.py에 이미 정의됨.

3. **테스트 DB 공유**: `db` fixture는 `scope="session"`. 고유 이메일 사용 (`uuid.uuid4().hex[:8]` prefix).

4. **`_get_dong_id(client)`**: 기존 헬퍼 재사용. 새로 만들지 말 것.

5. **`_make_auth_headers(user)`**: `test_products.py`에 이미 정의됨 → `test_likes.py`에서 동일 패턴으로 재정의.

6. **422 vs 400 상태코드**: NEIGHBORHOOD_NOT_SET을 422→400으로 수정한 선례. 비즈니스 로직 오류는 400, 구조적 유효성은 422(Pydantic). `ProductUpdate.status` 유효성은 Pydantic 검증이므로 422 정상.

7. **`Like` 모델의 복합 PK**: SQLModel에서 두 필드 모두 `primary_key=True`로 설정하면 복합 PK 생성됨. 별도 `__table_args__` 불필요.

---

## Dev Agent Record

### Agent Model Used

claude-sonnet-4-6

### Debug Log References

- `test_delete_cascades_likes` — `db.expire_all()` 후 삭제된 Product 객체 로드 시도 → `ObjectDeletedError`. `db.expunge_all()`로 identity map 완전 초기화 후 재쿼리하여 해결.
- `test_likes.py` isort — `from sqlmodel import Session, select as sq_select` 한 줄 import가 isort 위반. ruff `--fix`로 두 줄로 분리.

### Completion Notes List

- Alembic migration 007: likes 테이블 (복합 PK = UNIQUE, CASCADE FK, idx_likes_product_id 인덱스)
- `Like` SQLModel + `ProductUpdate` 스키마 (status field_validator) 추가
- `likes.py` 신규: POST /{id}/likes (201/409), DELETE /{id}/likes (204/404)
- `products.py`: PATCH /{id} (sqlmodel_update + exclude_unset), DELETE /{id}, like_count 배치 집계
- 기존 like_count=0 TODO 3개 → 실제 집계 코드로 교체 완료
- 테스트 27개 신규 (TestLikeProduct 6 + TestUnlikeProduct 4 + TestUpdateProduct 8 + TestDeleteProduct 6 + 기존 1 docstring 업데이트)
- 전체 88/88 통과, ruff 클린

### File List
- backend/app/alembic/versions/007_likes_table.py (NEW)
- backend/app/models.py (UPDATE)
- backend/app/api/routes/likes.py (NEW)
- backend/app/api/main.py (UPDATE)
- backend/app/api/routes/products.py (UPDATE)
- backend/tests/api/routes/test_likes.py (NEW)
- backend/tests/api/routes/test_products.py (UPDATE - docstring only)
