---
baseline_commit: NO_VCS
---

# Story 3.1 — 상품 등록 API & R2 이미지 업로드

**Status:** done

## Story

As a developer,
I want to implement the product registration API with Cloudflare R2 image upload,
So that sellers can create new product listings with photos.

## Acceptance Criteria

**Given** 인증된 판매자가 이미지 파일을 전송할 때
**When** `POST /api/v1/products/images`로 이미지(들)를 업로드하면
**Then** FastAPI가 파일을 R2 버킷에 저장하고 공개 URL 목록을 반환한다
**And** 단일 파일 크기가 1MB를 초과하면 HTTP 400 `IMAGE_TOO_LARGE`를 반환한다
**And** 10장 초과 업로드 시도 시 HTTP 400 `IMAGE_COUNT_EXCEEDED`를 반환한다

**Given** 이미지 URL 목록과 상품 정보를 전송할 때
**When** `POST /api/v1/products`로 상품을 등록하면
**Then** products 테이블에 저장되고 생성된 상품 객체를 HTTP 201로 반환한다
**And** 필수 필드(title, price, category) 누락 시 HTTP 422를 반환한다

**Given** 비인증 사용자가 상품 등록을 시도할 때
**When** `POST /api/v1/products` 또는 `POST /api/v1/products/images`를 호출하면
**Then** HTTP 401을 반환한다

## Tasks / Subtasks

- [x] Task 1: boto3 의존성 추가 및 R2 설정 (AC: 1)
  - [x] `backend/pyproject.toml`에 `boto3` 추가
  - [x] `backend/app/core/config.py`에 R2 설정 5개 추가
  - [x] `backend/.env`에 R2 환경변수 플레이스홀더 추가

- [x] Task 2: `backend/app/core/storage.py` 신규 생성 (AC: 1)
  - [x] `upload_image(content, filename) -> str` 함수 구현
  - [x] boto3 S3 클라이언트 구성 (R2 endpoint)
  - [x] content-type 추론 헬퍼 구현

- [x] Task 3: `backend/app/models.py` 스키마 추가 (AC: 1, 2)
  - [x] `ProductCreate` Pydantic 모델 추가
  - [x] `ProductImageUploadResponse` 모델 추가

- [x] Task 4: `backend/app/api/routes/products.py` 엔드포인트 추가 (AC: 1, 2, 3)
  - [x] `POST /images` 이미지 업로드 엔드포인트 추가
  - [x] `POST /` 상품 등록 엔드포인트 추가
  - [x] storage 모듈 import 추가

- [x] Task 5: 테스트 추가 (AC: 1~3)
  - [x] `tests/api/routes/test_products.py`에 `TestUploadProductImages` 클래스 추가
  - [x] `TestCreateProduct` 클래스 추가
  - [x] `upload_image` mock fixture 추가

## Dev Notes

### 핵심 사항 요약

1. **NO 마이그레이션** — products 테이블은 migration 006이 head. 신규 테이블 없음.
2. **boto3 없음** — `pyproject.toml`에 아직 없음. 반드시 추가해야 함.
3. **백엔드 전용 스토리** — Flutter 파일 변경 없음.
4. **동기 라우트** — 이 프로젝트의 모든 FastAPI 라우트는 `def` (not `async def`). storage.py도 동기 함수로 작성.
5. **라우트 순서 주의** — `POST /images`는 `POST /`보다 먼저 등록 (FastAPI는 선언 순서대로 매칭).

### 프로젝트 구조

**UPDATE — 수정할 파일:**
```
backend/pyproject.toml                        ← boto3 추가
backend/.env                                  ← R2 환경변수 플레이스홀더 추가
backend/app/core/config.py                    ← R2 설정 5개 추가
backend/app/models.py                         ← ProductCreate, ProductImageUploadResponse 추가
backend/app/api/routes/products.py            ← POST /images, POST / 추가
backend/tests/api/routes/test_products.py     ← 신규 테스트 클래스 추가
```

**NEW — 새로 생성할 파일:**
```
backend/app/core/storage.py                   ← R2 업로드 추상화
```

**수정 불필요:**
```
backend/app/api/main.py       ← products 라우터 이미 등록됨
backend/app/api/deps.py       ← CurrentUser 이미 있음
```

### 기존 코드 컨텍스트 (반드시 보존)

**`products.py` 현재 상태:**
- `GET /products` — 피드 (공개)
- `GET /products/{product_id}` — 상세 (공개)
- `like_count=0` TODO 주석 → Story 3.3에서 수정. **이번 스토리에서 건드리지 말 것**

**`models.py` 현재 상태:**
- `ProductDetail` 스키마 이미 있음 → 상품 등록 응답에 재사용
- `Product` SQLModel 이미 있음 → DB 저장에 사용
- `ProductStatus.SALE/RESERVED/SOLD` enum 이미 있음

**`deps.py`:**
- `CurrentUser = Annotated[User, Depends(get_current_user)]` 이미 있음 → import해서 사용

---

## API 계약

### POST /api/v1/products/images

**인증 필수.** multipart/form-data.

**Request:** `files` field (multiple UploadFile)

**Response 200:**
```json
{ "urls": ["https://pub-xxx.r2.dev/products/uuid.jpg", "..."] }
```

**Errors:**
- `400 IMAGE_TOO_LARGE` — 파일 1개 > 1MB (`1024*1024` bytes)
- `400 IMAGE_COUNT_EXCEEDED` — files > 10장
- `401 UNAUTHORIZED` — 미인증

---

### POST /api/v1/products

**인증 필수.** application/json.

**Request body:**
```json
{
  "title": "아이폰 15 Pro 팝니다",        // 필수, max 40자
  "price": 1200000,                       // 필수, >= 0
  "category": "전자기기",                  // 필수, max 50자
  "description": "3개월 사용...",          // 선택
  "image_urls": ["https://r2..."],         // 선택, 기본 []
  "neighborhood_id": null                  // 선택, null이면 현재 유저의 neighborhood_id 사용
}
```

**Response 201:** `ProductDetail` 스키마 (기존 `GET /products/{id}`와 동일한 형식)
```json
{
  "id": "uuid",
  "seller_id": "uuid",
  "title": "아이폰 15 Pro 팝니다",
  "price": 1200000,
  "description": "3개월 사용...",
  "category": "전자기기",
  "image_urls": ["https://r2..."],
  "created_at": "2026-05-30T10:00:00Z",
  "like_count": 0,
  "status": "SALE",
  "seller_nickname": "당근이"
}
```

**Errors:**
- `422` — title/price/category 누락 (Pydantic)
- `422 NEIGHBORHOOD_NOT_SET` — neighborhood_id 없고 user.neighborhood_id도 null
- `404 NEIGHBORHOOD_NOT_FOUND` — 유효하지 않은 neighborhood_id
- `401 UNAUTHORIZED` — 미인증

---

## 구현 상세

### 1. `backend/pyproject.toml` — boto3 추가

```toml
dependencies = [
    ...기존 의존성...
    "boto3>=1.34.0,<2.0.0",
]
```

### 2. `backend/app/core/config.py` — R2 설정 추가

`Settings` 클래스에 추가:
```python
R2_ACCOUNT_ID: str = ""
R2_ACCESS_KEY_ID: str = ""
R2_SECRET_ACCESS_KEY: str = ""
R2_BUCKET_NAME: str = "marketplace"
R2_PUBLIC_URL: str = ""  # e.g., https://pub-xxx.r2.dev
```

### 3. `backend/.env` — R2 플레이스홀더 추가

파일 끝에 추가:
```
# Cloudflare R2
R2_ACCOUNT_ID=
R2_ACCESS_KEY_ID=
R2_SECRET_ACCESS_KEY=
R2_BUCKET_NAME=marketplace
R2_PUBLIC_URL=
```

### 4. `backend/app/core/storage.py` (NEW)

```python
import uuid

import boto3

from app.core.config import settings

_CONTENT_TYPES = {
    "jpg": "image/jpeg",
    "jpeg": "image/jpeg",
    "png": "image/png",
    "webp": "image/webp",
    "gif": "image/gif",
}


def _make_key(filename: str) -> str:
    ext = filename.rsplit(".", 1)[-1].lower() if "." in filename else "jpg"
    return f"products/{uuid.uuid4()}.{ext}"


def _content_type(filename: str) -> str:
    ext = filename.rsplit(".", 1)[-1].lower() if "." in filename else ""
    return _CONTENT_TYPES.get(ext, "image/jpeg")


def upload_image(content: bytes, filename: str) -> str:
    """Upload image bytes to Cloudflare R2 and return the public URL."""
    key = _make_key(filename)
    client = boto3.client(
        "s3",
        endpoint_url=f"https://{settings.R2_ACCOUNT_ID}.r2.cloudflarestorage.com",
        aws_access_key_id=settings.R2_ACCESS_KEY_ID,
        aws_secret_access_key=settings.R2_SECRET_ACCESS_KEY,
        region_name="auto",
    )
    client.put_object(
        Bucket=settings.R2_BUCKET_NAME,
        Key=key,
        Body=content,
        ContentType=_content_type(filename),
    )
    return f"{settings.R2_PUBLIC_URL}/{key}"
```

**중요:** 함수 이름 `upload_image`를 그대로 유지. 테스트에서 `app.core.storage.upload_image`를 mock patch함.

### 5. `backend/app/models.py` — 스키마 추가

파일 끝에 추가:
```python
# ─── Product Create Schema ─────────────────────────────────────────────────────

class ProductCreate(SQLModel):
    title: str = Field(max_length=40)
    price: int = Field(ge=0)
    category: str = Field(max_length=50)
    description: str | None = None
    image_urls: list[str] = Field(default_factory=list)
    neighborhood_id: int | None = None


class ProductImageUploadResponse(SQLModel):
    urls: list[str]
```

### 6. `backend/app/api/routes/products.py` — 엔드포인트 추가

파일 상단 import에 추가:
```python
from fastapi import File, UploadFile

from app.api.deps import CurrentUser
from app.core import storage
from app.models import (
    ...,
    ProductCreate,
    ProductImageUploadResponse,
)
```

상수 추가 (라우터 선언 전):
```python
_MAX_IMAGE_SIZE = 1024 * 1024  # 1 MB
_MAX_IMAGE_COUNT = 10
```

기존 `@router.get("")` 앞에 다음 두 엔드포인트 삽입:

```python
@router.post("/images", response_model=ProductImageUploadResponse)
def upload_product_images(
    files: list[UploadFile] = File(...),
    current_user: CurrentUser,
) -> Any:
    """Upload images to R2. Returns list of public URLs.

    Validates: max 10 files, each ≤ 1 MB.
    Authentication required.
    """
    if len(files) > _MAX_IMAGE_COUNT:
        raise HTTPException(
            status_code=400,
            detail={
                "detail": f"최대 {_MAX_IMAGE_COUNT}장까지 업로드할 수 있습니다.",
                "code": "IMAGE_COUNT_EXCEEDED",
            },
        )
    urls: list[str] = []
    for f in files:
        content = f.file.read()
        if len(content) > _MAX_IMAGE_SIZE:
            raise HTTPException(
                status_code=400,
                detail={
                    "detail": "이미지 크기는 1MB 이하여야 합니다.",
                    "code": "IMAGE_TOO_LARGE",
                },
            )
        urls.append(storage.upload_image(content, f.filename or "image.jpg"))
    return ProductImageUploadResponse(urls=urls)


@router.post("", status_code=201, response_model=ProductDetail)
def create_product(
    body: ProductCreate,
    session: SessionDep,
    current_user: CurrentUser,
) -> Any:
    """Create a new product listing.

    neighborhood_id defaults to the seller's current neighborhood.
    """
    neighborhood_id = body.neighborhood_id or current_user.neighborhood_id
    if not neighborhood_id:
        raise HTTPException(
            status_code=422,
            detail={
                "detail": "동네 설정이 필요합니다.",
                "code": "NEIGHBORHOOD_NOT_SET",
            },
        )
    if not session.get(Neighborhood, neighborhood_id):
        raise HTTPException(
            status_code=404,
            detail={"detail": "동네를 찾을 수 없습니다.", "code": "NEIGHBORHOOD_NOT_FOUND"},
        )

    product = Product(
        seller_id=current_user.id,
        title=body.title,
        price=body.price,
        category=body.category,
        description=body.description,
        image_urls=body.image_urls,
        neighborhood_id=neighborhood_id,
    )
    session.add(product)
    session.commit()
    session.refresh(product)

    return ProductDetail(
        id=product.id,
        seller_id=product.seller_id,
        title=product.title,
        price=product.price,
        description=product.description,
        category=product.category,
        image_urls=product.image_urls,
        created_at=product.created_at,
        like_count=0,
        status=product.status,
        seller_nickname=current_user.nickname,
    )
```

**최종 라우트 순서 (products.py 전체):**
```
POST /images         ← 신규 (특정 경로, /{id} 보다 앞에 등록)
POST /               ← 신규
GET  /               ← 기존 피드
GET  /{product_id}   ← 기존 상세
```

---

## 테스트 요구사항

### mock fixture

`test_products.py` 상단에 추가:
```python
from unittest.mock import MagicMock, patch

@pytest.fixture
def mock_upload_image():
    """Mock R2 upload — returns predictable URL without real network calls."""
    with patch("app.core.storage.upload_image") as mock:
        mock.return_value = "https://r2.test/products/test.jpg"
        yield mock
```

인증 헬퍼 (test_users.py와 동일 패턴으로 추가):
```python
from app.core import security

def _make_auth_headers(user: "crud.User") -> dict[str, str]:
    token = security.create_access_token(str(user.id), role=user.role)
    return {"Authorization": f"Bearer {token}"}
```

### `TestUploadProductImages` 클래스

```python
class TestUploadProductImages:
    def test_upload_single_image_returns_url(self, client, db, mock_upload_image):
        """Successful upload returns URL list with one entry."""
        seller = _make_seller(db)
        resp = client.post(
            f"{BASE}/products/images",
            files=[("files", ("photo.jpg", b"x" * 100, "image/jpeg"))],
            headers=_make_auth_headers(seller),
        )
        assert resp.status_code == 200
        data = resp.json()
        assert "urls" in data
        assert len(data["urls"]) == 1
        assert data["urls"][0] == "https://r2.test/products/test.jpg"

    def test_upload_multiple_images(self, client, db, mock_upload_image):
        """Up to 10 files can be uploaded at once."""
        seller = _make_seller(db)
        files = [("files", (f"img{i}.jpg", b"x" * 100, "image/jpeg")) for i in range(3)]
        resp = client.post(
            f"{BASE}/products/images",
            files=files,
            headers=_make_auth_headers(seller),
        )
        assert resp.status_code == 200
        assert len(resp.json()["urls"]) == 3

    def test_upload_image_too_large_returns_400(self, client, db, mock_upload_image):
        """File exceeding 1MB returns 400 IMAGE_TOO_LARGE."""
        seller = _make_seller(db)
        big_content = b"x" * (1024 * 1024 + 1)  # 1 byte over 1MB
        resp = client.post(
            f"{BASE}/products/images",
            files=[("files", ("big.jpg", big_content, "image/jpeg"))],
            headers=_make_auth_headers(seller),
        )
        assert resp.status_code == 400
        assert resp.json()["code"] == "IMAGE_TOO_LARGE"
        mock_upload_image.assert_not_called()

    def test_upload_too_many_images_returns_400(self, client, db, mock_upload_image):
        """More than 10 files returns 400 IMAGE_COUNT_EXCEEDED."""
        seller = _make_seller(db)
        files = [("files", (f"img{i}.jpg", b"x" * 100, "image/jpeg")) for i in range(11)]
        resp = client.post(
            f"{BASE}/products/images",
            files=files,
            headers=_make_auth_headers(seller),
        )
        assert resp.status_code == 400
        assert resp.json()["code"] == "IMAGE_COUNT_EXCEEDED"

    def test_upload_images_requires_auth(self, client):
        """Image upload endpoint requires authentication."""
        resp = client.post(
            f"{BASE}/products/images",
            files=[("files", ("photo.jpg", b"x" * 100, "image/jpeg"))],
        )
        assert resp.status_code == 401
```

### `TestCreateProduct` 클래스

```python
class TestCreateProduct:
    def test_create_product_success(self, client, db):
        """Authenticated seller can create a product."""
        seller = _make_seller(db)
        dong_id = _get_dong_id(client)
        seller.neighborhood_id = dong_id
        db.add(seller)
        db.commit()

        resp = client.post(
            f"{BASE}/products",
            json={
                "title": "새 상품",
                "price": 50000,
                "category": "전자기기",
                "image_urls": [],
            },
            headers=_make_auth_headers(seller),
        )
        assert resp.status_code == 201
        data = resp.json()
        assert data["title"] == "새 상품"
        assert data["price"] == 50000
        assert data["category"] == "전자기기"
        assert data["status"] == "SALE"
        assert data["like_count"] == 0
        assert "id" in data
        assert "created_at" in data

    def test_create_product_with_explicit_neighborhood(self, client, db):
        """Product creation with explicit neighborhood_id."""
        seller = _make_seller(db)
        dong_id = _get_dong_id(client)

        resp = client.post(
            f"{BASE}/products",
            json={
                "title": "동네 지정 상품",
                "price": 10000,
                "category": "의류",
                "neighborhood_id": dong_id,
            },
            headers=_make_auth_headers(seller),
        )
        assert resp.status_code == 201

    def test_create_product_missing_required_fields(self, client, db):
        """Missing title, price, or category returns 422."""
        seller = _make_seller(db)
        dong_id = _get_dong_id(client)
        seller.neighborhood_id = dong_id
        db.add(seller)
        db.commit()

        resp = client.post(
            f"{BASE}/products",
            json={"price": 10000, "category": "의류"},  # title 누락
            headers=_make_auth_headers(seller),
        )
        assert resp.status_code == 422

    def test_create_product_no_neighborhood_returns_422(self, client, db):
        """Seller with no neighborhood and no neighborhood_id in body returns 422."""
        seller = _make_seller(db)
        # seller.neighborhood_id = None (기본값)

        resp = client.post(
            f"{BASE}/products",
            json={"title": "상품", "price": 5000, "category": "기타"},
            headers=_make_auth_headers(seller),
        )
        assert resp.status_code == 422

    def test_create_product_requires_auth(self, client):
        """Product creation requires authentication."""
        resp = client.post(
            f"{BASE}/products",
            json={"title": "상품", "price": 5000, "category": "기타"},
        )
        assert resp.status_code == 401

    def test_created_product_appears_in_feed(self, client, db):
        """After creation, product is visible in the neighborhood feed."""
        seller = _make_seller(db)
        dong_id = _get_dong_id(client)
        seller.neighborhood_id = dong_id
        db.add(seller)
        db.commit()

        create_resp = client.post(
            f"{BASE}/products",
            json={
                "title": "피드노출 확인 상품",
                "price": 99000,
                "category": "가구",
                "neighborhood_id": dong_id,
            },
            headers=_make_auth_headers(seller),
        )
        assert create_resp.status_code == 201
        product_id = create_resp.json()["id"]

        feed_resp = client.get(f"{BASE}/products", params={"neighborhood_id": dong_id})
        assert feed_resp.status_code == 200
        ids = [i["id"] for i in feed_resp.json()["items"]]
        assert product_id in ids
```

---

## 개발자 가드레일

### MUST 따라야 할 패턴

1. **`storage.upload_image` 모듈 참조**: route에서 `from app.core import storage`로 import 후 `storage.upload_image(...)` 호출. `from app.core.storage import upload_image`로 직접 import하면 테스트 mock이 작동하지 않음.

2. **동기 함수 유지**: `def upload_product_images(...)`, `def create_product(...)` — `async def` 사용 금지. 프로젝트 전체가 sync psycopg 기반.

3. **라우트 선언 순서**: `POST /images`를 `GET /`과 `GET /{product_id}` 보다 먼저 선언. FastAPI는 선언 순서대로 매칭.

4. **에러 형식 준수**: `{"detail": "...", "code": "..."}` — 다른 라우트와 동일한 flat 형식.

5. **`ProductDetail` 재사용**: `POST /products` 응답 스키마는 기존 `ProductDetail`을 재사용. 새 응답 스키마 만들지 말 것.

6. **`like_count=0`**: 신규 상품의 like_count는 항상 0. Story 3.3까지는 likes 테이블 없음.

7. **`current_user.neighborhood_id` fallback**: `body.neighborhood_id or current_user.neighborhood_id` 패턴. 둘 다 None이면 422.

### MUST NOT

- `boto3` async 클라이언트(`aiobotocore`) 사용 금지 — sync boto3만 사용
- 테스트에서 실제 R2 API 호출 금지 — `mock_upload_image` fixture 필수
- likes 테이블 참조 금지 — Story 3.3의 범위
- `PUT` 엔드포인트 추가 금지 — 아키텍처 규칙: PATCH만 사용
- `ProductStatus` enum 변경 금지 — 기존 SALE/RESERVED/SOLD 유지

### boto3 설치 검증

구현 전 실행:
```bash
cd backend
uv add "boto3>=1.34.0,<2.0.0"
uv run python -c "import boto3; print('boto3 OK')"
```

### R2 미설정 환경에서의 테스트

테스트는 `mock_upload_image` fixture로 실제 R2 호출 없이 실행됨.
`config.py`의 R2 설정은 빈 문자열 기본값이므로 서버 시작에 영향 없음.
실제 R2 연동은 `.env`에 자격증명 입력 후 수동 테스트.

### 파일 읽기 방식 (UploadFile)

```python
content = f.file.read()  # SpooledTemporaryFile.read() → bytes
```

`await f.read()` 사용 금지 (async). `f.file.read()` 사용.

---

## 이전 스토리 학습사항 (Story 2.x)

1. **에러 응답 형식**: `raise HTTPException(status_code=..., detail={"detail":"...", "code":"..."})` — dict 형식 일관 적용. 문자열 사용 시 `main.py`의 핸들러가 코드 필드 없이 반환함.
2. **`CurrentUser` import**: `from app.api.deps import CurrentUser` — deps.py에 이미 정의됨.
3. **테스트 DB 공유**: `db` fixture는 `scope="session"`. 테스트 간 데이터가 남아있을 수 있으므로 고유한 이메일/제목 사용.
4. **`_get_dong_id(client)`**: 기존 헬퍼 함수 재사용. 새로 만들지 말 것.
5. **`_make_seller(db)`**: 기존 헬퍼 함수 재사용.

---

## Dev Agent Record

### Agent Model Used

claude-sonnet-4-6

### Debug Log References

- ARG001 ruff 경고: `upload_product_images`의 `current_user`는 auth 가드로만 사용(값 불필요) → `_current_user`로 rename 해결
- models.py의 pre-existing `import re as _re` E402/I001 → import 상단 이동 + sqlalchemy import 통합으로 해결

### Completion Notes List

- boto3 1.43.18 설치 완료 (uv add)
- `backend/app/core/storage.py` 신규 생성 — R2 이미지 업로드 추상화 (`upload_image` 함수)
- `POST /api/v1/products/images` — multipart 다중 파일 업로드, 1MB/10장 제한 검증
- `POST /api/v1/products` — 상품 등록, neighborhood_id fallback(user 설정값), 201 반환
- `ProductCreate`, `ProductImageUploadResponse` 스키마 추가
- 테스트 13개 추가 (5개 이미지 업로드, 8개 상품 등록), mock_upload_image fixture로 R2 격리
- 전체 테스트 61/61 통과, ruff 린트 클린

**코드리뷰 이슈 수정 (2026-05-30):**
- [Fix #1/#5] config.py `_normalize_and_validate_r2` 추가 — R2_PUBLIC_URL 후행 슬래시 제거 + 빈 값 경고
- [Fix #2/#3] 2-pass 업로드: 크기 검사를 모든 파일에 먼저 수행 후 업로드 → 고아 R2 객체 방지, f.size fast-path 추가
- [Fix #4] `NEIGHBORHOOD_NOT_SET` 422 → 400 (아키텍처 계약 준수)
- [Fix #6] `ProductCreate.image_urls` max_length=10 추가
- [Fix #7] `ProductCreate.description` max_length=2000 추가
- [Fix #8] boto3 클라이언트 `_get_s3_client()` lru_cache 싱글톤으로 변경
- [Fix #9] `neighborhood_id or` → `neighborhood_id if ... is not None else` 패턴
- [Fix #10] `_get_ext()` 헬퍼 통합, `_make_key`/`_content_type` 폴백 불일치 해소
- 신규 테스트 3개 추가 (2-pass 고아방지, image_urls 초과, description 길이 초과)
- 전체 테스트 64/64 통과, ruff 클린

### File List
- backend/pyproject.toml (UPDATE)
- backend/.env (UPDATE)
- backend/app/core/config.py (UPDATE)
- backend/app/core/storage.py (NEW)
- backend/app/models.py (UPDATE)
- backend/app/api/routes/products.py (UPDATE)
- backend/tests/api/routes/test_products.py (UPDATE)
