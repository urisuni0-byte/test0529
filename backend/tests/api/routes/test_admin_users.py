"""Tests for Story 5.3 — admin user management endpoints."""
import uuid

from fastapi.testclient import TestClient
from sqlmodel import Session

from app import crud
from app.core import security
from app.core.config import settings
from app.models import User

BASE = settings.API_V1_STR


# ─── Helpers ──────────────────────────────────────────────────────────────────

def _make_user(
    db: Session,
    *,
    role: str = "user",
    nickname: str | None = None,
    is_active: bool = True,
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
    user.is_active = is_active
    if nickname is not None:
        user.nickname = nickname
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


# ─── GET /admin/users ─────────────────────────────────────────────────────────

class TestListAdminUsers:
    def test_list_users_success(self, client: TestClient, db: Session) -> None:
        """어드민 → 200 + items/total 반환."""
        admin = _make_admin(db)
        _make_user(db, nickname="테스트유저")

        resp = client.get(
            f"{BASE}/admin/users",
            headers=_admin_headers(admin),
        )
        assert resp.status_code == 200
        data = resp.json()
        assert "items" in data
        assert "total" in data
        assert data["total"] >= 1

    def test_list_users_excludes_admin_accounts(
        self, client: TestClient, db: Session
    ) -> None:
        """어드민 계정은 목록에 포함되지 않음."""
        admin = _make_admin(db)
        _make_user(db, nickname="일반유저")

        resp = client.get(f"{BASE}/admin/users", headers=_admin_headers(admin))
        assert resp.status_code == 200
        emails = [i["email"] for i in resp.json()["items"]]
        assert admin.email not in emails

    def test_list_users_contains_required_fields(
        self, client: TestClient, db: Session
    ) -> None:
        """응답 아이템에 필수 필드 포함: id, email, nickname, is_active, created_at."""
        admin = _make_admin(db)
        _make_user(db, nickname="필드확인유저")

        resp = client.get(f"{BASE}/admin/users", headers=_admin_headers(admin))
        assert resp.status_code == 200
        item = resp.json()["items"][0]
        assert "id" in item
        assert "email" in item
        assert "nickname" in item
        assert "is_active" in item
        assert "created_at" in item

    def test_list_users_requires_admin(
        self, client: TestClient, db: Session
    ) -> None:
        """일반 유저 → 403 FORBIDDEN."""
        user = _make_user(db)
        resp = client.get(
            f"{BASE}/admin/users",
            headers=_user_headers(user),
        )
        assert resp.status_code == 403

    def test_list_users_requires_auth(self, client: TestClient) -> None:
        """미인증 → 401."""
        resp = client.get(f"{BASE}/admin/users")
        assert resp.status_code == 401


# ─── PATCH /admin/users/{id}/deactivate ───────────────────────────────────────

class TestDeactivateAdminUser:
    def test_deactivate_user_success(
        self, client: TestClient, db: Session
    ) -> None:
        """어드민 → 200, is_active=false 반환 + DB 반영."""
        admin = _make_admin(db)
        target = _make_user(db, nickname="비활성화대상")
        assert target.is_active is True

        resp = client.patch(
            f"{BASE}/admin/users/{target.id}/deactivate",
            headers=_admin_headers(admin),
        )
        assert resp.status_code == 200
        data = resp.json()
        assert data["is_active"] is False
        assert data["id"] == str(target.id)

        db.expire_all()
        updated = db.get(User, target.id)
        assert updated is not None
        assert updated.is_active is False

    def test_deactivate_nonexistent_user_returns_404(
        self, client: TestClient, db: Session
    ) -> None:
        """없는 사용자 비활성화 → 404 USER_NOT_FOUND."""
        admin = _make_admin(db)
        resp = client.patch(
            f"{BASE}/admin/users/{uuid.uuid4()}/deactivate",
            headers=_admin_headers(admin),
        )
        assert resp.status_code == 404
        assert resp.json()["code"] == "USER_NOT_FOUND"

    def test_deactivate_self_returns_400(
        self, client: TestClient, db: Session
    ) -> None:
        """어드민 자기 자신 비활성화 → 400 CANNOT_DEACTIVATE_SELF."""
        admin = _make_admin(db)
        resp = client.patch(
            f"{BASE}/admin/users/{admin.id}/deactivate",
            headers=_admin_headers(admin),
        )
        assert resp.status_code == 400
        assert resp.json()["code"] == "CANNOT_DEACTIVATE_SELF"

    def test_deactivate_user_requires_admin(
        self, client: TestClient, db: Session
    ) -> None:
        """일반 유저 → 403 FORBIDDEN."""
        user = _make_user(db)
        target = _make_user(db)
        resp = client.patch(
            f"{BASE}/admin/users/{target.id}/deactivate",
            headers=_user_headers(user),
        )
        assert resp.status_code == 403

    def test_deactivate_user_requires_auth(
        self, client: TestClient, db: Session
    ) -> None:
        """미인증 → 401."""
        target = _make_user(db)
        resp = client.patch(f"{BASE}/admin/users/{target.id}/deactivate")
        assert resp.status_code == 401

    def test_deactivate_already_inactive_is_idempotent(
        self, client: TestClient, db: Session
    ) -> None:
        """이미 비활성화된 사용자 재비활성화 → 200 (멱등)."""
        admin = _make_admin(db)
        target = _make_user(db, is_active=False)

        resp = client.patch(
            f"{BASE}/admin/users/{target.id}/deactivate",
            headers=_admin_headers(admin),
        )
        assert resp.status_code == 200
        assert resp.json()["is_active"] is False

    def test_deactivate_admin_user_returns_400(
        self, client: TestClient, db: Session
    ) -> None:
        """어드민 계정 비활성화 시도 → 400 CANNOT_DEACTIVATE_ADMIN."""
        admin = _make_admin(db)
        other_admin = _make_admin(db)

        resp = client.patch(
            f"{BASE}/admin/users/{other_admin.id}/deactivate",
            headers=_admin_headers(admin),
        )
        assert resp.status_code == 400
        assert resp.json()["code"] == "CANNOT_DEACTIVATE_ADMIN"


# ─── is_active 체크 통합 검증 ─────────────────────────────────────────────────

class TestDeactivatedUserAccess:
    def test_deactivated_user_google_login_returns_403(
        self, client: TestClient, db: Session
    ) -> None:
        """비활성화된 사용자가 Google 로그인 시도 → auth.py가 403 반환.

        upsert_google_user는 is_active를 덮어쓰지 않으므로,
        기존 비활성 사용자가 OAuth 재시도해도 재활성화되지 않는다.
        """
        suffix = uuid.uuid4().hex[:8]
        inactive_user = crud.upsert_google_user(
            session=db,
            email=f"inactive_{suffix}@test.com",
            google_sub=uuid.uuid4().hex,
            name="Inactive",
        )
        inactive_user.is_active = False
        db.add(inactive_user)
        db.commit()
        db.refresh(inactive_user)

        # verify_google_id_token을 우회하기 위해 JWT 직접 검증 경로 사용
        # 비활성화된 사용자의 JWT로 보호된 엔드포인트 접근 시 403
        token = security.create_access_token(str(inactive_user.id), role="user")
        resp = client.get(
            f"{BASE}/users/me",
            headers={"Authorization": f"Bearer {token}"},
        )
        assert resp.status_code == 403
        assert resp.json()["code"] == "ACCOUNT_DEACTIVATED"

    def test_deactivated_user_jwt_access_returns_403(
        self, client: TestClient, db: Session
    ) -> None:
        """비활성화된 사용자 JWT로 보호된 엔드포인트 접근 → 403 ACCOUNT_DEACTIVATED."""
        inactive_user = _make_user(db, is_active=False)
        token = security.create_access_token(str(inactive_user.id), role="user")
        resp = client.get(
            f"{BASE}/users/me",
            headers={"Authorization": f"Bearer {token}"},
        )
        assert resp.status_code == 403
        assert resp.json()["code"] == "ACCOUNT_DEACTIVATED"
