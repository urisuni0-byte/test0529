"""Tests for Story 5.4 — admin stats endpoint."""
import uuid
from datetime import datetime, timezone

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
    is_active: bool = True,
) -> User:
    suffix = uuid.uuid4().hex[:8]
    user = crud.upsert_google_user(
        session=db,
        email=f"{role}_{suffix}@test.com",
        google_sub=uuid.uuid4().hex,
        name=role.capitalize(),
    )
    user.role = role
    user.is_active = is_active
    db.add(user)
    db.commit()
    db.refresh(user)
    return user


def _make_admin(db: Session) -> User:
    user = _make_user(db, role="admin")
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
) -> Product:
    product = Product(
        seller_id=seller_id,
        title="통계테스트상품",
        price=10000,
        category="기타",
        status="SALE",
        neighborhood_id=neighborhood_id,
        image_urls=[],
    )
    db.add(product)
    db.commit()
    db.refresh(product)
    return product


# ─── GET /admin/stats ─────────────────────────────────────────────────────────

class TestAdminStats:
    def test_stats_success_contains_required_fields(
        self, client: TestClient, db: Session
    ) -> None:
        """어드민 → 200 + 5개 필수 필드 반환."""
        admin = _make_admin(db)

        resp = client.get(f"{BASE}/admin/stats", headers=_admin_headers(admin))

        assert resp.status_code == 200
        data = resp.json()
        assert "total_users" in data
        assert "total_products" in data
        assert "new_users_today" in data
        assert "new_products_today" in data
        assert "active_chat_rooms" in data
        assert all(isinstance(data[k], int) for k in data)

    def test_stats_requires_admin(self, client: TestClient, db: Session) -> None:
        """일반 유저 → 403 FORBIDDEN."""
        user = _make_user(db)
        resp = client.get(f"{BASE}/admin/stats", headers=_user_headers(user))
        assert resp.status_code == 403

    def test_stats_requires_auth(self, client: TestClient) -> None:
        """미인증 → 401."""
        resp = client.get(f"{BASE}/admin/stats")
        assert resp.status_code == 401

    def test_stats_new_users_today_counts_today_signups(
        self, client: TestClient, db: Session
    ) -> None:
        """new_users_today는 오늘 가입한 일반 사용자 수를 반영한다."""
        admin = _make_admin(db)

        # 기준값 먼저 확인
        before = client.get(
            f"{BASE}/admin/stats", headers=_admin_headers(admin)
        ).json()["new_users_today"]

        # 오늘 가입 유저 2명 추가
        _make_user(db)
        _make_user(db)

        after = client.get(
            f"{BASE}/admin/stats", headers=_admin_headers(admin)
        ).json()["new_users_today"]

        assert after == before + 2

    def test_stats_new_products_today_counts_today_registrations(
        self, client: TestClient, db: Session
    ) -> None:
        """new_products_today는 오늘 등록된 상품 수를 반영한다."""
        admin = _make_admin(db)
        seller = _make_user(db)
        dong_id = _get_dong_id(client)

        before = client.get(
            f"{BASE}/admin/stats", headers=_admin_headers(admin)
        ).json()["new_products_today"]

        _create_product(db, seller.id, dong_id)
        _create_product(db, seller.id, dong_id)

        after = client.get(
            f"{BASE}/admin/stats", headers=_admin_headers(admin)
        ).json()["new_products_today"]

        assert after == before + 2

    def test_stats_total_users_excludes_admin_accounts(
        self, client: TestClient, db: Session
    ) -> None:
        """total_users는 role='admin' 계정을 제외한다."""
        admin = _make_admin(db)

        before = client.get(
            f"{BASE}/admin/stats", headers=_admin_headers(admin)
        ).json()["total_users"]

        # 어드민 계정 추가 — total_users에 반영되면 안 됨
        _make_admin(db)
        # 일반 유저 추가 — total_users에 반영되어야 함
        _make_user(db)

        after = client.get(
            f"{BASE}/admin/stats", headers=_admin_headers(admin)
        ).json()["total_users"]

        assert after == before + 1
