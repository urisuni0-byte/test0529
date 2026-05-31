"""Tests for Story 3.3 — likes, product update, product delete endpoints."""
import uuid

from fastapi.testclient import TestClient
from sqlmodel import Session
from sqlmodel import select as sq_select

from app import crud
from app.core import security
from app.core.config import settings
from app.models import Like, Product

BASE = settings.API_V1_STR


# ─── Helpers ──────────────────────────────────────────────────────────────────

def _make_user(db: Session, prefix: str = "user") -> crud.User:
    email = f"{prefix}_{uuid.uuid4().hex[:8]}@test.com"
    return crud.upsert_google_user(
        session=db, email=email, google_sub=uuid.uuid4().hex, name=prefix.capitalize()
    )


def _make_auth_headers(user: crud.User) -> dict[str, str]:
    token = security.create_access_token(str(user.id), role=user.role)
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
    title: str = "테스트 상품",
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


def _like_product(db: Session, user_id: uuid.UUID, product_id: uuid.UUID) -> Like:
    like = Like(user_id=user_id, product_id=product_id)
    db.add(like)
    db.commit()
    db.refresh(like)
    return like


# ─── POST /products/{id}/likes ────────────────────────────────────────────────

class TestLikeProduct:
    def test_like_product_success(self, client: TestClient, db: Session) -> None:
        """관심 등록 성공 → 201."""
        seller = _make_user(db, "seller")
        buyer = _make_user(db, "buyer")
        dong_id = _get_dong_id(client)
        product = _create_product(db, seller.id, dong_id)

        resp = client.post(
            f"{BASE}/products/{product.id}/likes",
            headers=_make_auth_headers(buyer),
        )
        assert resp.status_code == 201

    def test_like_duplicate_returns_409(self, client: TestClient, db: Session) -> None:
        """중복 관심 등록 → 409 LIKE_ALREADY_EXISTS."""
        seller = _make_user(db, "seller")
        buyer = _make_user(db, "buyer")
        dong_id = _get_dong_id(client)
        product = _create_product(db, seller.id, dong_id)
        _like_product(db, buyer.id, product.id)

        resp = client.post(
            f"{BASE}/products/{product.id}/likes",
            headers=_make_auth_headers(buyer),
        )
        assert resp.status_code == 409
        assert resp.json()["code"] == "LIKE_ALREADY_EXISTS"

    def test_like_nonexistent_product_returns_404(
        self, client: TestClient, db: Session
    ) -> None:
        """존재하지 않는 상품 관심 등록 → 404 PRODUCT_NOT_FOUND."""
        buyer = _make_user(db, "buyer")
        resp = client.post(
            f"{BASE}/products/{uuid.uuid4()}/likes",
            headers=_make_auth_headers(buyer),
        )
        assert resp.status_code == 404
        assert resp.json()["code"] == "PRODUCT_NOT_FOUND"

    def test_like_requires_auth(self, client: TestClient, db: Session) -> None:
        """미인증 → 401."""
        seller = _make_user(db, "seller")
        dong_id = _get_dong_id(client)
        product = _create_product(db, seller.id, dong_id)

        resp = client.post(f"{BASE}/products/{product.id}/likes")
        assert resp.status_code == 401

    def test_like_count_increments_in_detail(
        self, client: TestClient, db: Session
    ) -> None:
        """관심 등록 후 GET /products/{id}의 like_count가 1 증가."""
        seller = _make_user(db, "seller")
        buyer = _make_user(db, "buyer")
        dong_id = _get_dong_id(client)
        product = _create_product(db, seller.id, dong_id)

        assert client.get(f"{BASE}/products/{product.id}").json()["like_count"] == 0

        client.post(
            f"{BASE}/products/{product.id}/likes",
            headers=_make_auth_headers(buyer),
        )

        assert client.get(f"{BASE}/products/{product.id}").json()["like_count"] == 1

    def test_like_count_increments_in_feed(
        self, client: TestClient, db: Session
    ) -> None:
        """관심 등록 후 GET /products 피드의 like_count가 1 증가."""
        seller = _make_user(db, "seller")
        buyer = _make_user(db, "buyer")
        dong_id = _get_dong_id(client)
        product = _create_product(db, seller.id, dong_id, title="피드관심테스트")

        # 좋아요 전
        feed = client.get(f"{BASE}/products", params={"neighborhood_id": dong_id}).json()
        item_before = next(i for i in feed["items"] if i["id"] == str(product.id))
        before_count = item_before["like_count"]

        # 좋아요 후
        client.post(
            f"{BASE}/products/{product.id}/likes",
            headers=_make_auth_headers(buyer),
        )
        feed = client.get(f"{BASE}/products", params={"neighborhood_id": dong_id}).json()
        item_after = next(i for i in feed["items"] if i["id"] == str(product.id))
        assert item_after["like_count"] == before_count + 1


# ─── DELETE /products/{id}/likes ─────────────────────────────────────────────

class TestUnlikeProduct:
    def test_unlike_product_success(self, client: TestClient, db: Session) -> None:
        """관심 해제 성공 → 204."""
        seller = _make_user(db, "seller")
        buyer = _make_user(db, "buyer")
        dong_id = _get_dong_id(client)
        product = _create_product(db, seller.id, dong_id)
        _like_product(db, buyer.id, product.id)

        resp = client.delete(
            f"{BASE}/products/{product.id}/likes",
            headers=_make_auth_headers(buyer),
        )
        assert resp.status_code == 204

    def test_unlike_decrements_like_count(
        self, client: TestClient, db: Session
    ) -> None:
        """관심 해제 후 like_count가 0으로 감소."""
        seller = _make_user(db, "seller")
        buyer = _make_user(db, "buyer")
        dong_id = _get_dong_id(client)
        product = _create_product(db, seller.id, dong_id)
        _like_product(db, buyer.id, product.id)

        assert client.get(f"{BASE}/products/{product.id}").json()["like_count"] == 1

        client.delete(
            f"{BASE}/products/{product.id}/likes",
            headers=_make_auth_headers(buyer),
        )

        assert client.get(f"{BASE}/products/{product.id}").json()["like_count"] == 0

    def test_unlike_not_liked_returns_404(
        self, client: TestClient, db: Session
    ) -> None:
        """관심 등록하지 않은 상품 해제 → 404 LIKE_NOT_FOUND."""
        seller = _make_user(db, "seller")
        buyer = _make_user(db, "buyer")
        dong_id = _get_dong_id(client)
        product = _create_product(db, seller.id, dong_id)

        resp = client.delete(
            f"{BASE}/products/{product.id}/likes",
            headers=_make_auth_headers(buyer),
        )
        assert resp.status_code == 404
        assert resp.json()["code"] == "LIKE_NOT_FOUND"

    def test_unlike_requires_auth(self, client: TestClient, db: Session) -> None:
        """미인증 → 401."""
        seller = _make_user(db, "seller")
        dong_id = _get_dong_id(client)
        product = _create_product(db, seller.id, dong_id)

        resp = client.delete(f"{BASE}/products/{product.id}/likes")
        assert resp.status_code == 401


# ─── PATCH /products/{id} ────────────────────────────────────────────────────

class TestUpdateProduct:
    def test_update_title_only(self, client: TestClient, db: Session) -> None:
        """제목만 수정 — exclude_unset으로 나머지 필드 보존."""
        seller = _make_user(db, "seller")
        dong_id = _get_dong_id(client)
        product = _create_product(db, seller.id, dong_id, title="원래 제목")

        resp = client.patch(
            f"{BASE}/products/{product.id}",
            json={"title": "새 제목"},
            headers=_make_auth_headers(seller),
        )
        assert resp.status_code == 200
        data = resp.json()
        assert data["title"] == "새 제목"
        assert data["price"] == 10000  # 기존 값 보존

    def test_update_status_to_reserved(self, client: TestClient, db: Session) -> None:
        """상태를 RESERVED로 변경."""
        seller = _make_user(db, "seller")
        dong_id = _get_dong_id(client)
        product = _create_product(db, seller.id, dong_id)

        resp = client.patch(
            f"{BASE}/products/{product.id}",
            json={"status": "RESERVED"},
            headers=_make_auth_headers(seller),
        )
        assert resp.status_code == 200
        assert resp.json()["status"] == "RESERVED"

    def test_update_multiple_fields(self, client: TestClient, db: Session) -> None:
        """여러 필드 동시 수정."""
        seller = _make_user(db, "seller")
        dong_id = _get_dong_id(client)
        product = _create_product(db, seller.id, dong_id)

        resp = client.patch(
            f"{BASE}/products/{product.id}",
            json={"title": "수정됨", "price": 99000, "status": "SOLD"},
            headers=_make_auth_headers(seller),
        )
        assert resp.status_code == 200
        data = resp.json()
        assert data["title"] == "수정됨"
        assert data["price"] == 99000
        assert data["status"] == "SOLD"

    def test_update_invalid_status_returns_422(
        self, client: TestClient, db: Session
    ) -> None:
        """유효하지 않은 status 값 → 422."""
        seller = _make_user(db, "seller")
        dong_id = _get_dong_id(client)
        product = _create_product(db, seller.id, dong_id)

        resp = client.patch(
            f"{BASE}/products/{product.id}",
            json={"status": "INVALID_STATUS"},
            headers=_make_auth_headers(seller),
        )
        assert resp.status_code == 422

    def test_update_by_non_seller_returns_403(
        self, client: TestClient, db: Session
    ) -> None:
        """타인 상품 수정 → 403 FORBIDDEN."""
        seller = _make_user(db, "seller")
        other = _make_user(db, "other")
        dong_id = _get_dong_id(client)
        product = _create_product(db, seller.id, dong_id)

        resp = client.patch(
            f"{BASE}/products/{product.id}",
            json={"title": "해킹"},
            headers=_make_auth_headers(other),
        )
        assert resp.status_code == 403
        assert resp.json()["code"] == "FORBIDDEN"

    def test_update_nonexistent_returns_404(
        self, client: TestClient, db: Session
    ) -> None:
        """존재하지 않는 상품 수정 → 404."""
        seller = _make_user(db, "seller")
        resp = client.patch(
            f"{BASE}/products/{uuid.uuid4()}",
            json={"title": "없는 상품"},
            headers=_make_auth_headers(seller),
        )
        assert resp.status_code == 404
        assert resp.json()["code"] == "PRODUCT_NOT_FOUND"

    def test_update_requires_auth(self, client: TestClient, db: Session) -> None:
        """미인증 → 401."""
        seller = _make_user(db, "seller")
        dong_id = _get_dong_id(client)
        product = _create_product(db, seller.id, dong_id)

        resp = client.patch(
            f"{BASE}/products/{product.id}",
            json={"title": "새 제목"},
        )
        assert resp.status_code == 401

    def test_update_returns_like_count(self, client: TestClient, db: Session) -> None:
        """수정 응답에 실제 like_count 포함."""
        seller = _make_user(db, "seller")
        buyer = _make_user(db, "buyer")
        dong_id = _get_dong_id(client)
        product = _create_product(db, seller.id, dong_id)
        _like_product(db, buyer.id, product.id)

        resp = client.patch(
            f"{BASE}/products/{product.id}",
            json={"title": "수정됨"},
            headers=_make_auth_headers(seller),
        )
        assert resp.status_code == 200
        assert resp.json()["like_count"] == 1


# ─── DELETE /products/{id} ───────────────────────────────────────────────────

class TestDeleteProduct:
    def test_delete_own_product(self, client: TestClient, db: Session) -> None:
        """본인 상품 삭제 → 204."""
        seller = _make_user(db, "seller")
        dong_id = _get_dong_id(client)
        product = _create_product(db, seller.id, dong_id)

        resp = client.delete(
            f"{BASE}/products/{product.id}",
            headers=_make_auth_headers(seller),
        )
        assert resp.status_code == 204

    def test_delete_removes_product_from_db(
        self, client: TestClient, db: Session
    ) -> None:
        """삭제 후 GET → 404."""
        seller = _make_user(db, "seller")
        dong_id = _get_dong_id(client)
        product = _create_product(db, seller.id, dong_id)

        client.delete(
            f"{BASE}/products/{product.id}",
            headers=_make_auth_headers(seller),
        )
        resp = client.get(f"{BASE}/products/{product.id}")
        assert resp.status_code == 404

    def test_delete_by_non_seller_returns_403(
        self, client: TestClient, db: Session
    ) -> None:
        """타인 상품 삭제 → 403 FORBIDDEN."""
        seller = _make_user(db, "seller")
        other = _make_user(db, "other")
        dong_id = _get_dong_id(client)
        product = _create_product(db, seller.id, dong_id)

        resp = client.delete(
            f"{BASE}/products/{product.id}",
            headers=_make_auth_headers(other),
        )
        assert resp.status_code == 403
        assert resp.json()["code"] == "FORBIDDEN"

    def test_delete_nonexistent_returns_404(
        self, client: TestClient, db: Session
    ) -> None:
        """존재하지 않는 상품 삭제 → 404."""
        seller = _make_user(db, "seller")
        resp = client.delete(
            f"{BASE}/products/{uuid.uuid4()}",
            headers=_make_auth_headers(seller),
        )
        assert resp.status_code == 404
        assert resp.json()["code"] == "PRODUCT_NOT_FOUND"

    def test_delete_requires_auth(self, client: TestClient, db: Session) -> None:
        """미인증 → 401."""
        seller = _make_user(db, "seller")
        dong_id = _get_dong_id(client)
        product = _create_product(db, seller.id, dong_id)

        resp = client.delete(f"{BASE}/products/{product.id}")
        assert resp.status_code == 401

    def test_delete_cascades_likes(self, client: TestClient, db: Session) -> None:
        """상품 삭제 시 likes도 CASCADE 삭제 (DB 정합성)."""
        seller = _make_user(db, "seller")
        buyer = _make_user(db, "buyer")
        dong_id = _get_dong_id(client)
        product = _create_product(db, seller.id, dong_id)
        product_id = product.id  # UUID 값 저장 (삭제 후 stale 객체 접근 방지)
        _like_product(db, buyer.id, product_id)

        # 좋아요 존재 확인
        assert db.exec(
            sq_select(Like).where(Like.product_id == product_id)
        ).first() is not None

        client.delete(
            f"{BASE}/products/{product_id}",
            headers=_make_auth_headers(seller),
        )

        # expunge_all: identity map 초기화 → 다음 쿼리는 DB에서 직접 조회
        db.expunge_all()
        assert db.exec(
            sq_select(Like).where(Like.product_id == product_id)
        ).first() is None
