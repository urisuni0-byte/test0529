"""Tests for Story 5.1 — admin authentication endpoint."""
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
    password: str | None = None,
    is_active: bool = True,
) -> User:
    email = f"{role}_{uuid.uuid4().hex[:8]}@test.com"
    user = crud.upsert_google_user(
        session=db,
        email=email,
        google_sub=uuid.uuid4().hex,
        name=role.capitalize(),
    )
    if password is not None:
        user.hashed_password = security.get_password_hash(password)
    user.role = role
    user.is_active = is_active
    db.add(user)
    db.commit()
    db.refresh(user)
    return user


# ─── POST /admin/auth/login ───────────────────────────────────────────────────

class TestAdminLogin:
    def test_login_success_returns_access_token(
        self, client: TestClient, db: Session
    ) -> None:
        """올바른 credentials로 로그인 → 200 + access_token."""
        admin = _make_user(db, role="admin", password="s3cur3pass")

        resp = client.post(
            f"{BASE}/admin/auth/login",
            json={"email": admin.email, "password": "s3cur3pass"},
        )

        assert resp.status_code == 200
        data = resp.json()
        assert "access_token" in data
        assert data["token_type"] == "bearer"

    def test_login_wrong_password_returns_401(
        self, client: TestClient, db: Session
    ) -> None:
        """틀린 비밀번호 → 401 INVALID_CREDENTIALS."""
        admin = _make_user(db, role="admin", password="correct")

        resp = client.post(
            f"{BASE}/admin/auth/login",
            json={"email": admin.email, "password": "wrong"},
        )

        assert resp.status_code == 401
        assert resp.json()["code"] == "INVALID_CREDENTIALS"

    def test_login_nonexistent_email_returns_401(
        self, client: TestClient
    ) -> None:
        """존재하지 않는 이메일 → 401."""
        resp = client.post(
            f"{BASE}/admin/auth/login",
            json={"email": "ghost@example.com", "password": "any"},
        )
        assert resp.status_code == 401
        assert resp.json()["code"] == "INVALID_CREDENTIALS"

    def test_login_no_password_hash_returns_401(
        self, client: TestClient, db: Session
    ) -> None:
        """hashed_password가 null인 계정 → 401 (Google OAuth 전용 유저)."""
        user = _make_user(db, role="admin", password=None)

        resp = client.post(
            f"{BASE}/admin/auth/login",
            json={"email": user.email, "password": "anything"},
        )
        assert resp.status_code == 401

    def test_login_non_admin_role_returns_403(
        self, client: TestClient, db: Session
    ) -> None:
        """role=user 계정 로그인 → 403 FORBIDDEN."""
        user = _make_user(db, role="user", password="pass")

        resp = client.post(
            f"{BASE}/admin/auth/login",
            json={"email": user.email, "password": "pass"},
        )
        assert resp.status_code == 403
        assert resp.json()["code"] == "FORBIDDEN"

    def test_login_deactivated_admin_returns_403(
        self, client: TestClient, db: Session
    ) -> None:
        """is_active=False 계정 → 403 ACCOUNT_DEACTIVATED."""
        admin = _make_user(db, role="admin", password="pass", is_active=False)

        resp = client.post(
            f"{BASE}/admin/auth/login",
            json={"email": admin.email, "password": "pass"},
        )
        assert resp.status_code == 403
        assert resp.json()["code"] == "ACCOUNT_DEACTIVATED"

    def test_token_contains_admin_role_claim(
        self, client: TestClient, db: Session
    ) -> None:
        """반환된 JWT에 role=admin 클레임이 포함된다."""
        import jwt as pyjwt

        admin = _make_user(db, role="admin", password="pass")
        resp = client.post(
            f"{BASE}/admin/auth/login",
            json={"email": admin.email, "password": "pass"},
        )
        assert resp.status_code == 200
        token = resp.json()["access_token"]

        payload = pyjwt.decode(
            token,
            settings.SECRET_KEY,
            algorithms=[security.ALGORITHM],
        )
        assert payload["role"] == "admin"
        assert payload["sub"] == str(admin.id)

    def test_login_first_superuser_from_env(
        self, client: TestClient, db: Session
    ) -> None:
        """FIRST_SUPERUSER 계정으로 로그인 성공 (init_db에서 해시 생성)."""
        # init_db가 이미 FIRST_SUPERUSER를 생성했을 것
        # (conftest.py에서 init_db 호출됨)
        resp = client.post(
            f"{BASE}/admin/auth/login",
            json={
                "email": settings.FIRST_SUPERUSER,
                "password": settings.FIRST_SUPERUSER_PASSWORD,
            },
        )
        assert resp.status_code == 200
        assert "access_token" in resp.json()
