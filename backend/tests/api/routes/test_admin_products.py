"""Tests for Story 5.2 — admin product management endpoints."""
import uuid

from fastapi.testclient import TestClient
from sqlmodel import Session

from app import crud
from app.core import security
from app.core.config import settings
from app.models import Product, User

BASE = settings.API_V1_STR


# ─── Helpers ──────────────────────────────────────────────────────────────────

def _make_user(
    db: Session,
    *,
    role: str = "user",
    nickname: str | None = None,
) -> User:
    suffix = uuid.uuid4().hex[:8]
    email = f"{role}_{suffix}@test.com"
    user = crud.upsert_google_user(
        session=db,
        email=email,
        google_sub=uuid.uuid4().hex,
        name=role.capitalize(),
    )
    user.role = role
    user.is_active = True
    if nickname is not None:
        user.nickname = nickname
    db.add(user)
    db.commit()
    db.refresh(user)
    return user


def _make_admin(db: Session, *, nickname: str | None = None) -> User:
    user = _make_user(db, role="admin", nickname=nickname)
    user.hashed_password = security.get_password_hash("adminpass")
    db.add(user)
    db.commit()
    db.refresh(user)
    return user


def _admin_headers(admin: User) -> dict[str, str]:
    token = security.create_access_token(str(admin.id), role="admin")
    return {"Authorization": f"Bearer {token}"}


def _user_headers(user: User) -> dict[str, str]:
    token = security.create_access_token(str(user.id), role="user")
    return {"Authorization": f"Bearer {token}"}


def _get_dong_id(client: TestClient) -> int:
    resp = client.get(f"{BASE}/neighborhoods")
    dongs = [n for n in resp.json()["items"] if n["level"] == "dong"]
    return dongs[0]["id"]


def _create_product(
    db: Session,
    seller_id: uuid.UUID,
    neighborhood_id: int,
    *,
    title: str = "관리자테스트상품",
    status: str = "SALE",
) -> Product:
    product = Product(
        seller_id=seller_id,
        title=title,
        price=10000,
        category="의류",
        status=status,
        neighborhood_id=neighborhood_id,
        image_urls=[],
    )
    db.add(product)
    db.commit()
    db.refresh(product)
    return product


# ─── GET /admin/products ──────────────────────────────────────────────────────

class TestListAdminProducts:
    def test_list_products_success(
        self, client: TestClient, db: Session
    ) -> None:
        """어드민 → 200 + items/total 반환."""
        admin = _make_admin(db)
        seller = _make_user(db, nickname="판매자테스트")
        dong_id = _get_dong_id(client)
        _create_product(db, seller.id, dong_id, title="어드민목록테스트")

        resp = client.get(
            f"{BASE}/admin/products",
            headers=_admin_headers(admin),
        )
        assert resp.status_code == 200
        data = resp.json()
        assert "items" in data
        assert "total" in data
        assert data["total"] >= 1
        titles = [i["title"] for i in data["items"]]
        assert "어드민목록테스트" in titles

    def test_list_products_contains_required_fields(
        self, client: TestClient, db: Session
    ) -> None:
        """응답 아이템에 필수 필드 포함."""
        admin = _make_admin(db)
        seller = _make_user(db, nickname="필드테스트판매자")
        dong_id = _get_dong_id(client)
        _create_product(db, seller.id, dong_id, title="필드확인상품")

        resp = client.get(
            f"{BASE}/admin/products", headers=_admin_headers(admin)
        )
        item = next(
            (i for i in resp.json()["items"] if i["title"] == "필드확인상품"), None
        )
        assert item is not None
        assert "id" in item
        assert "price" in item
        assert "status" in item
        assert "seller_nickname" in item
        assert "created_at" in item

    def test_list_products_filter_status(
        self, client: TestClient, db: Session
    ) -> None:
        """status=SOLD 필터 적용 시 해당 상품만 반환."""
        admin = _make_admin(db)
        seller = _make_user(db)
        dong_id = _get_dong_id(client)
        _create_product(db, seller.id, dong_id, title="판매완료상품", status="SOLD")
        _create_product(db, seller.id, dong_id, title="판매중상품", status="SALE")

        resp = client.get(
            f"{BASE}/admin/products?status=SOLD",
            headers=_admin_headers(admin),
        )
        assert resp.status_code == 200
        items = resp.json()["items"]
        statuses = {i["status"] for i in items}
        assert statuses == {"SOLD"}

    def test_list_products_filter_seller_nickname(
        self, client: TestClient, db: Session
    ) -> None:
        """seller 필터: 닉네임 부분 일치 검색."""
        admin = _make_admin(db)
        seller_a = _make_user(db, nickname="홍길동")
        seller_b = _make_user(db, nickname="김철수")
        dong_id = _get_dong_id(client)
        _create_product(db, seller_a.id, dong_id, title="홍길동상품")
        _create_product(db, seller_b.id, dong_id, title="김철수상품")

        resp = client.get(
            f"{BASE}/admin/products?seller=홍길",
            headers=_admin_headers(admin),
        )
        assert resp.status_code == 200
        nicknames = [i["seller_nickname"] for i in resp.json()["items"]]
        assert "홍길동" in nicknames
        assert "김철수" not in nicknames

    def test_list_products_requires_admin(
        self, client: TestClient, db: Session
    ) -> None:
        """일반 유저 → 403 FORBIDDEN."""
        user = _make_user(db)
        resp = client.get(
            f"{BASE}/admin/products",
            headers=_user_headers(user),
        )
        assert resp.status_code == 403

    def test_list_products_requires_auth(self, client: TestClient) -> None:
        """미인증 → 401."""
        resp = client.get(f"{BASE}/admin/products")
        assert resp.status_code == 401


# ─── DELETE /admin/products/{id} ─────────────────────────────────────────────

class TestDeleteAdminProduct:
    def test_delete_product_success(
        self, client: TestClient, db: Session
    ) -> None:
        """어드민 → 204, 상품이 DB에서 제거된다."""
        admin = _make_admin(db)
        seller = _make_user(db)
        dong_id = _get_dong_id(client)
        product = _create_product(db, seller.id, dong_id, title="삭제대상상품")
        product_id = product.id

        resp = client.delete(
            f"{BASE}/admin/products/{product_id}",
            headers=_admin_headers(admin),
        )
        assert resp.status_code == 204

        # DB에서 제거 확인
        db.expire_all()
        assert db.get(Product, product_id) is None

    def test_delete_nonexistent_product_returns_404(
        self, client: TestClient, db: Session
    ) -> None:
        """없는 상품 삭제 → 404 PRODUCT_NOT_FOUND."""
        admin = _make_admin(db)
        resp = client.delete(
            f"{BASE}/admin/products/{uuid.uuid4()}",
            headers=_admin_headers(admin),
        )
        assert resp.status_code == 404
        assert resp.json()["code"] == "PRODUCT_NOT_FOUND"

    def test_delete_product_requires_admin(
        self, client: TestClient, db: Session
    ) -> None:
        """일반 유저 → 403 FORBIDDEN."""
        user = _make_user(db)
        seller = _make_user(db)
        dong_id = _get_dong_id(client)
        product = _create_product(db, seller.id, dong_id)

        resp = client.delete(
            f"{BASE}/admin/products/{product.id}",
            headers=_user_headers(user),
        )
        assert resp.status_code == 403

    def test_delete_product_requires_auth(
        self, client: TestClient, db: Session
    ) -> None:
        """미인증 → 401."""
        seller = _make_user(db)
        dong_id = _get_dong_id(client)
        product = _create_product(db, seller.id, dong_id)

        resp = client.delete(f"{BASE}/admin/products/{product.id}")
        assert resp.status_code == 401
