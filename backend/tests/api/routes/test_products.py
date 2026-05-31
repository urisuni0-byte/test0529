"""Tests for products endpoints.

Story 2.1 — GET /products (feed) and GET /products/{id} (detail), public endpoints.
Story 3.1 — POST /products/images (image upload) and POST /products (create), auth required.
Story 3.3 — like_count is now computed from the likes table (see test_likes.py for like tests).
"""
import uuid
from unittest.mock import patch

import pytest
from fastapi.testclient import TestClient
from sqlmodel import Session

from app import crud
from app.core import security
from app.core.config import settings
from app.models import Product

BASE = settings.API_V1_STR


# ─── Helpers ──────────────────────────────────────────────────────────────────

def _make_seller(db: Session) -> "crud.User":
    email = f"seller_{uuid.uuid4().hex[:8]}@test.com"
    return crud.upsert_google_user(
        session=db, email=email, google_sub=uuid.uuid4().hex, name="Seller"
    )


def _get_dong_id(client: TestClient) -> int:
    """Return the first dong-level neighborhood id from the seeded data."""
    resp = client.get(f"{BASE}/neighborhoods")
    assert resp.status_code == 200
    dongs = [n for n in resp.json()["items"] if n["level"] == "dong"]
    assert dongs, "Seed data must contain at least one dong neighborhood"
    return dongs[0]["id"]


def _get_secondary_dong_id(client: TestClient) -> int:
    """Return a dong not used by other test helpers — for testing empty-result behavior."""
    resp = client.get(f"{BASE}/neighborhoods")
    assert resp.status_code == 200
    dongs = [n for n in resp.json()["items"] if n["level"] == "dong"]
    assert len(dongs) >= 2, "Seed data must contain at least two dong neighborhoods"
    return dongs[-1]["id"]


def _create_product(
    db: Session,
    seller_id: uuid.UUID,
    neighborhood_id: int,
    *,
    title: str = "테스트 상품",
    price: int = 10000,
    category: str = "의류",
    status: str = "SALE",
    image_urls: list[str] | None = None,
    description: str | None = None,
) -> Product:
    product = Product(
        seller_id=seller_id,
        title=title,
        price=price,
        category=category,
        status=status,
        neighborhood_id=neighborhood_id,
        image_urls=image_urls or [],
        description=description,
    )
    db.add(product)
    db.commit()
    db.refresh(product)
    return product


# ─── GET /products (feed) ─────────────────────────────────────────────────────

class TestProductFeed:
    def test_returns_empty_list_when_no_products(
        self, client: TestClient, db: Session
    ) -> None:
        """Feed returns empty items list for a neighborhood with no products."""
        dong_id = _get_secondary_dong_id(client)
        resp = client.get(f"{BASE}/products", params={"neighborhood_id": dong_id})
        assert resp.status_code == 200
        data = resp.json()
        assert data["items"] == []
        assert data["total"] == 0
        assert data["page"] == 1
        assert data["limit"] == 20

    def test_returns_products_in_neighborhood(
        self, client: TestClient, db: Session
    ) -> None:
        """Feed returns products belonging to the requested neighborhood."""
        seller = _make_seller(db)
        dong_id = _get_dong_id(client)
        _create_product(db, seller.id, dong_id, title="피드 상품A")
        _create_product(db, seller.id, dong_id, title="피드 상품B")

        resp = client.get(f"{BASE}/products", params={"neighborhood_id": dong_id})
        assert resp.status_code == 200
        data = resp.json()
        titles = [i["title"] for i in data["items"]]
        assert "피드 상품A" in titles
        assert "피드 상품B" in titles

    def test_sold_products_not_in_feed(
        self, client: TestClient, db: Session
    ) -> None:
        """Products with status=SOLD must not appear in the feed."""
        seller = _make_seller(db)
        dong_id = _get_dong_id(client)
        sold = _create_product(db, seller.id, dong_id, title="판매완료 상품", status="SOLD")

        resp = client.get(f"{BASE}/products", params={"neighborhood_id": dong_id})
        assert resp.status_code == 200
        ids = [i["id"] for i in resp.json()["items"]]
        assert str(sold.id) not in ids

    def test_reserved_products_in_feed(
        self, client: TestClient, db: Session
    ) -> None:
        """Products with status=RESERVED must appear in the feed."""
        seller = _make_seller(db)
        dong_id = _get_dong_id(client)
        reserved = _create_product(
            db, seller.id, dong_id, title="예약중 상품", status="RESERVED"
        )

        resp = client.get(f"{BASE}/products", params={"neighborhood_id": dong_id})
        assert resp.status_code == 200
        ids = [i["id"] for i in resp.json()["items"]]
        assert str(reserved.id) in ids

    def test_feed_is_public_no_auth_required(self, client: TestClient) -> None:
        """Feed endpoint must be accessible without an Authorization header."""
        dong_id = _get_dong_id(client)
        resp = client.get(f"{BASE}/products", params={"neighborhood_id": dong_id})
        assert resp.status_code != 401

    def test_feed_response_has_pagination_fields(
        self, client: TestClient
    ) -> None:
        """Response must include total, page, limit alongside items."""
        dong_id = _get_dong_id(client)
        resp = client.get(
            f"{BASE}/products",
            params={"neighborhood_id": dong_id, "page": 2, "limit": 5},
        )
        assert resp.status_code == 200
        data = resp.json()
        assert "items" in data
        assert "total" in data
        assert data["page"] == 2
        assert data["limit"] == 5

    def test_feed_items_have_required_fields(
        self, client: TestClient, db: Session
    ) -> None:
        """Each feed item must expose the required fields."""
        seller = _make_seller(db)
        dong_id = _get_dong_id(client)
        _create_product(
            db,
            seller.id,
            dong_id,
            title="필드확인 상품",
            price=5000,
            image_urls=["https://example.com/img.jpg"],
        )

        resp = client.get(f"{BASE}/products", params={"neighborhood_id": dong_id})
        assert resp.status_code == 200
        item = next(
            i for i in resp.json()["items"] if i["title"] == "필드확인 상품"
        )
        assert "id" in item
        assert "seller_id" in item
        assert "title" in item
        assert "price" in item
        assert "created_at" in item
        assert "like_count" in item
        assert "status" in item
        assert "thumbnail_url" in item
        assert item["like_count"] == 0
        assert item["thumbnail_url"] == "https://example.com/img.jpg"

    def test_thumbnail_url_is_none_when_no_images(
        self, client: TestClient, db: Session
    ) -> None:
        """thumbnail_url must be null when image_urls is empty."""
        seller = _make_seller(db)
        dong_id = _get_dong_id(client)
        _create_product(db, seller.id, dong_id, title="이미지없는 상품", image_urls=[])

        resp = client.get(f"{BASE}/products", params={"neighborhood_id": dong_id})
        assert resp.status_code == 200
        item = next(
            i for i in resp.json()["items"] if i["title"] == "이미지없는 상품"
        )
        assert item["thumbnail_url"] is None

    def test_feed_returns_newest_first(
        self, client: TestClient, db: Session
    ) -> None:
        """Products must be ordered newest (created_at desc) first."""
        import time

        seller = _make_seller(db)
        dong_id = _get_dong_id(client)

        first = _create_product(db, seller.id, dong_id, title="오래된 상품")
        time.sleep(0.01)  # ensure distinct timestamps
        second = _create_product(db, seller.id, dong_id, title="최신 상품")

        resp = client.get(f"{BASE}/products", params={"neighborhood_id": dong_id})
        assert resp.status_code == 200
        items = resp.json()["items"]
        ids = [i["id"] for i in items]
        assert ids.index(str(second.id)) < ids.index(str(first.id))

    def test_feed_neighborhood_id_required(self, client: TestClient) -> None:
        """Omitting neighborhood_id should return 422 (required query param)."""
        resp = client.get(f"{BASE}/products")
        assert resp.status_code == 422

    def test_invalid_neighborhood_returns_404(self, client: TestClient) -> None:
        """Non-existent neighborhood_id must return 404."""
        resp = client.get(f"{BASE}/products", params={"neighborhood_id": 99999})
        assert resp.status_code == 404
        assert resp.json()["code"] == "NEIGHBORHOOD_NOT_FOUND"

    def test_page_zero_returns_422(self, client: TestClient) -> None:
        """page=0 must return 422 — negative OFFSET would crash PostgreSQL."""
        dong_id = _get_dong_id(client)
        resp = client.get(
            f"{BASE}/products", params={"neighborhood_id": dong_id, "page": 0}
        )
        assert resp.status_code == 422

    def test_limit_zero_returns_422(self, client: TestClient) -> None:
        """limit=0 must return 422."""
        dong_id = _get_dong_id(client)
        resp = client.get(
            f"{BASE}/products", params={"neighborhood_id": dong_id, "limit": 0}
        )
        assert resp.status_code == 422

    def test_limit_above_max_returns_422(self, client: TestClient) -> None:
        """limit=101 must return 422 — unbounded limit is a DoS risk."""
        dong_id = _get_dong_id(client)
        resp = client.get(
            f"{BASE}/products", params={"neighborhood_id": dong_id, "limit": 101}
        )
        assert resp.status_code == 422

    def test_pagination_offset(self, client: TestClient, db: Session) -> None:
        """page=2 should skip the first `limit` products."""
        seller = _make_seller(db)
        dong_id = _get_dong_id(client)
        # Create 3 products to test pagination (limit=2, page=2 → 1 product)
        for i in range(3):
            _create_product(db, seller.id, dong_id, title=f"페이지테스트{i}")

        resp = client.get(
            f"{BASE}/products",
            params={"neighborhood_id": dong_id, "page": 1, "limit": 2},
        )
        assert resp.status_code == 200
        page1_ids = {i["id"] for i in resp.json()["items"]}

        resp2 = client.get(
            f"{BASE}/products",
            params={"neighborhood_id": dong_id, "page": 2, "limit": 2},
        )
        assert resp2.status_code == 200
        page2_ids = {i["id"] for i in resp2.json()["items"]}

        # No overlap between pages
        assert page1_ids.isdisjoint(page2_ids)


# ─── GET /products/{id} (detail) ──────────────────────────────────────────────

class TestProductDetail:
    def test_returns_full_detail(self, client: TestClient, db: Session) -> None:
        """Detail endpoint returns all required fields."""
        seller = _make_seller(db)
        dong_id = _get_dong_id(client)
        product = _create_product(
            db,
            seller.id,
            dong_id,
            title="상세 조회 상품",
            price=30000,
            category="전자기기",
            image_urls=["https://example.com/a.jpg", "https://example.com/b.jpg"],
            description="상품 설명입니다.",
        )

        resp = client.get(f"{BASE}/products/{product.id}")
        assert resp.status_code == 200
        data = resp.json()
        assert data["id"] == str(product.id)
        assert data["title"] == "상세 조회 상품"
        assert data["price"] == 30000
        assert data["category"] == "전자기기"
        assert data["description"] == "상품 설명입니다."
        assert data["image_urls"] == [
            "https://example.com/a.jpg",
            "https://example.com/b.jpg",
        ]
        assert data["like_count"] == 0
        assert data["status"] == "SALE"
        assert "seller_id" in data
        assert "created_at" in data

    def test_returns_seller_nickname(self, client: TestClient, db: Session) -> None:
        """Detail endpoint includes the seller's nickname."""
        seller = _make_seller(db)
        # Give the seller a unique nickname
        nick = f"nick{uuid.uuid4().hex[:6]}"
        seller.nickname = nick
        db.add(seller)
        db.commit()

        dong_id = _get_dong_id(client)
        product = _create_product(db, seller.id, dong_id, title="닉네임 테스트 상품")

        resp = client.get(f"{BASE}/products/{product.id}")
        assert resp.status_code == 200
        assert resp.json()["seller_nickname"] == nick

    def test_returns_404_for_missing_product(self, client: TestClient) -> None:
        """GET /products/{non_existent_id} must return 404."""
        fake_id = uuid.uuid4()
        resp = client.get(f"{BASE}/products/{fake_id}")
        assert resp.status_code == 404
        body = resp.json()
        assert body["code"] == "PRODUCT_NOT_FOUND"

    def test_detail_is_public_no_auth_required(
        self, client: TestClient, db: Session
    ) -> None:
        """Detail endpoint must be accessible without an Authorization header."""
        seller = _make_seller(db)
        dong_id = _get_dong_id(client)
        product = _create_product(db, seller.id, dong_id, title="공개 접근 상품")

        resp = client.get(f"{BASE}/products/{product.id}")
        assert resp.status_code == 200

    def test_detail_description_nullable(
        self, client: TestClient, db: Session
    ) -> None:
        """description may be null in the detail response."""
        seller = _make_seller(db)
        dong_id = _get_dong_id(client)
        product = _create_product(
            db, seller.id, dong_id, title="설명없는 상품", description=None
        )

        resp = client.get(f"{BASE}/products/{product.id}")
        assert resp.status_code == 200
        assert resp.json()["description"] is None


# ─── Auth Helper (Story 3.1+) ─────────────────────────────────────────────────

def _make_auth_headers(user: crud.User) -> dict[str, str]:
    token = security.create_access_token(str(user.id), role=user.role)
    return {"Authorization": f"Bearer {token}"}


# ─── POST /products/images (Story 3.1) ───────────────────────────────────────

@pytest.fixture
def mock_upload_image():
    """Mock R2 upload — returns predictable URL without real network calls."""
    with patch("app.core.storage.upload_image") as mock:
        mock.return_value = "https://r2.test/products/test.jpg"
        yield mock


class TestUploadProductImages:
    def test_upload_single_image_returns_url(
        self, client: TestClient, db: Session, mock_upload_image: object
    ) -> None:
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

    def test_upload_multiple_images(
        self, client: TestClient, db: Session, mock_upload_image: object
    ) -> None:
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

    def test_upload_image_too_large_returns_400(
        self, client: TestClient, db: Session, mock_upload_image: object
    ) -> None:
        """File exceeding 1MB returns 400 IMAGE_TOO_LARGE."""
        seller = _make_seller(db)
        big_content = b"x" * (1024 * 1024 + 1)
        resp = client.post(
            f"{BASE}/products/images",
            files=[("files", ("big.jpg", big_content, "image/jpeg"))],
            headers=_make_auth_headers(seller),
        )
        assert resp.status_code == 400
        assert resp.json()["code"] == "IMAGE_TOO_LARGE"

    def test_second_file_too_large_prevents_all_uploads(
        self, client: TestClient, db: Session, mock_upload_image: object
    ) -> None:
        """2-pass: when any file fails size check, no R2 uploads occur."""
        from unittest.mock import MagicMock
        seller = _make_seller(db)
        files = [
            ("files", ("ok.jpg", b"x" * 100, "image/jpeg")),
            ("files", ("big.jpg", b"x" * (1024 * 1024 + 1), "image/jpeg")),
        ]
        resp = client.post(
            f"{BASE}/products/images",
            files=files,
            headers=_make_auth_headers(seller),
        )
        assert resp.status_code == 400
        assert resp.json()["code"] == "IMAGE_TOO_LARGE"
        assert isinstance(mock_upload_image, MagicMock)
        mock_upload_image.assert_not_called()

    def test_upload_too_many_images_returns_400(
        self, client: TestClient, db: Session, mock_upload_image: object
    ) -> None:
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

    def test_upload_images_requires_auth(self, client: TestClient) -> None:
        """Image upload endpoint requires authentication."""
        resp = client.post(
            f"{BASE}/products/images",
            files=[("files", ("photo.jpg", b"x" * 100, "image/jpeg"))],
        )
        assert resp.status_code == 401


# ─── POST /products (Story 3.1) ───────────────────────────────────────────────

class TestCreateProduct:
    def test_create_product_success(
        self, client: TestClient, db: Session
    ) -> None:
        """Authenticated seller can create a product using their neighborhood."""
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

    def test_create_product_with_explicit_neighborhood(
        self, client: TestClient, db: Session
    ) -> None:
        """Product creation with explicit neighborhood_id in body."""
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
        assert resp.json()["title"] == "동네 지정 상품"

    def test_create_product_missing_title_returns_422(
        self, client: TestClient, db: Session
    ) -> None:
        """Missing required field title returns 422."""
        seller = _make_seller(db)
        dong_id = _get_dong_id(client)
        seller.neighborhood_id = dong_id
        db.add(seller)
        db.commit()

        resp = client.post(
            f"{BASE}/products",
            json={"price": 10000, "category": "의류"},
            headers=_make_auth_headers(seller),
        )
        assert resp.status_code == 422

    def test_create_product_no_neighborhood_returns_400(
        self, client: TestClient, db: Session
    ) -> None:
        """Seller with no neighborhood and no neighborhood_id in body returns 400."""
        seller = _make_seller(db)
        # seller.neighborhood_id is None by default

        resp = client.post(
            f"{BASE}/products",
            json={"title": "상품", "price": 5000, "category": "기타"},
            headers=_make_auth_headers(seller),
        )
        assert resp.status_code == 400
        assert resp.json()["code"] == "NEIGHBORHOOD_NOT_SET"

    def test_create_product_invalid_neighborhood_returns_404(
        self, client: TestClient, db: Session
    ) -> None:
        """Non-existent neighborhood_id returns 404."""
        seller = _make_seller(db)

        resp = client.post(
            f"{BASE}/products",
            json={
                "title": "상품",
                "price": 5000,
                "category": "기타",
                "neighborhood_id": 99999,
            },
            headers=_make_auth_headers(seller),
        )
        assert resp.status_code == 404
        assert resp.json()["code"] == "NEIGHBORHOOD_NOT_FOUND"

    def test_create_product_requires_auth(self, client: TestClient) -> None:
        """Product creation requires authentication."""
        resp = client.post(
            f"{BASE}/products",
            json={"title": "상품", "price": 5000, "category": "기타"},
        )
        assert resp.status_code == 401
        assert resp.json()["code"] == "UNAUTHORIZED"

    def test_created_product_appears_in_feed(
        self, client: TestClient, db: Session
    ) -> None:
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

        feed_resp = client.get(
            f"{BASE}/products", params={"neighborhood_id": dong_id}
        )
        assert feed_resp.status_code == 200
        ids = [i["id"] for i in feed_resp.json()["items"]]
        assert product_id in ids

    def test_create_product_with_image_urls(
        self, client: TestClient, db: Session
    ) -> None:
        """Product created with image URLs stores them correctly."""
        seller = _make_seller(db)
        dong_id = _get_dong_id(client)
        image_urls = ["https://r2.test/products/a.jpg", "https://r2.test/products/b.jpg"]

        resp = client.post(
            f"{BASE}/products",
            json={
                "title": "이미지 있는 상품",
                "price": 30000,
                "category": "전자기기",
                "image_urls": image_urls,
                "neighborhood_id": dong_id,
            },
            headers=_make_auth_headers(seller),
        )
        assert resp.status_code == 201
        data = resp.json()
        assert data["image_urls"] == image_urls

    def test_create_product_too_many_image_urls_returns_422(
        self, client: TestClient, db: Session
    ) -> None:
        """image_urls exceeding 10 items is rejected at schema level."""
        seller = _make_seller(db)
        dong_id = _get_dong_id(client)

        resp = client.post(
            f"{BASE}/products",
            json={
                "title": "이미지 초과 상품",
                "price": 5000,
                "category": "기타",
                "neighborhood_id": dong_id,
                "image_urls": [f"https://r2.test/{i}.jpg" for i in range(11)],
            },
            headers=_make_auth_headers(seller),
        )
        assert resp.status_code == 422

    def test_create_product_description_too_long_returns_422(
        self, client: TestClient, db: Session
    ) -> None:
        """description longer than 2000 characters returns 422."""
        seller = _make_seller(db)
        dong_id = _get_dong_id(client)

        resp = client.post(
            f"{BASE}/products",
            json={
                "title": "긴 설명 상품",
                "price": 5000,
                "category": "기타",
                "neighborhood_id": dong_id,
                "description": "a" * 2001,
            },
            headers=_make_auth_headers(seller),
        )
        assert resp.status_code == 422
