import uuid
from datetime import timedelta
from unittest.mock import AsyncMock, patch

import pytest
from fastapi.testclient import TestClient
from sqlmodel import Session

from app import crud
from app.core import security
from app.core.config import settings
from app.models import User


# ─── Helpers ──────────────────────────────────────────────────────────────────

MOCK_GOOGLE_USER = {
    "sub": "google_uid_12345",
    "email": "googleuser@gmail.com",
    "name": "Google User",
}


def _mock_google_verify(return_value: dict = MOCK_GOOGLE_USER) -> AsyncMock:
    return AsyncMock(return_value=return_value)


# ─── POST /auth/google ─────────────────────────────────────────────────────────

def test_google_login_success(client: TestClient, db: Session) -> None:
    with patch(
        "app.api.routes.auth.verify_google_id_token",
        _mock_google_verify(),
    ):
        resp = client.post(
            f"{settings.API_V1_STR}/auth/google",
            json={"id_token": "fake_google_token"},
        )
    assert resp.status_code == 200
    data = resp.json()
    assert "access_token" in data
    assert "refresh_token" in data
    assert data["token_type"] == "bearer"


def test_google_login_creates_user(client: TestClient, db: Session) -> None:
    unique_email = f"new_google_{uuid.uuid4().hex[:8]}@gmail.com"
    mock_data = {**MOCK_GOOGLE_USER, "email": unique_email, "sub": uuid.uuid4().hex}

    assert crud.get_user_by_email(session=db, email=unique_email) is None

    with patch("app.api.routes.auth.verify_google_id_token", AsyncMock(return_value=mock_data)):
        resp = client.post(
            f"{settings.API_V1_STR}/auth/google",
            json={"id_token": "fake_token"},
        )
    assert resp.status_code == 200
    user = crud.get_user_by_email(session=db, email=unique_email)
    assert user is not None


def test_google_login_deactivated_user(client: TestClient, db: Session) -> None:
    email = f"deactivated_{uuid.uuid4().hex[:8]}@gmail.com"
    user = crud.upsert_google_user(
        session=db, email=email, google_sub=uuid.uuid4().hex, name="Banned"
    )
    user.is_active = False
    db.add(user)
    db.commit()

    mock_data = {**MOCK_GOOGLE_USER, "email": email, "sub": uuid.uuid4().hex}
    with patch("app.api.routes.auth.verify_google_id_token", AsyncMock(return_value=mock_data)):
        resp = client.post(
            f"{settings.API_V1_STR}/auth/google",
            json={"id_token": "fake_token"},
        )
    assert resp.status_code == 403
    assert resp.json()["code"] == "ACCOUNT_DEACTIVATED"


def test_google_login_invalid_token(client: TestClient) -> None:
    from fastapi import HTTPException
    with patch(
        "app.api.routes.auth.verify_google_id_token",
        AsyncMock(side_effect=HTTPException(400, {"detail": "유효하지 않은 Google 토큰입니다.", "code": "INVALID_GOOGLE_TOKEN"})),
    ):
        resp = client.post(
            f"{settings.API_V1_STR}/auth/google",
            json={"id_token": "bad_token"},
        )
    assert resp.status_code == 400


# ─── POST /auth/refresh ────────────────────────────────────────────────────────

def test_refresh_token_success(client: TestClient, db: Session) -> None:
    email = f"refresh_{uuid.uuid4().hex[:8]}@test.com"
    user = crud.upsert_google_user(
        session=db, email=email, google_sub=uuid.uuid4().hex, name="Refresh User"
    )
    refresh_token = security.create_refresh_token(str(user.id))

    resp = client.post(
        f"{settings.API_V1_STR}/auth/refresh",
        json={"refresh_token": refresh_token},
    )
    assert resp.status_code == 200
    data = resp.json()
    assert "access_token" in data
    assert data["token_type"] == "bearer"


def test_refresh_token_invalid(client: TestClient) -> None:
    resp = client.post(
        f"{settings.API_V1_STR}/auth/refresh",
        json={"refresh_token": "this.is.invalid"},
    )
    assert resp.status_code == 401
    assert resp.json()["code"] == "INVALID_REFRESH_TOKEN"


def test_refresh_token_using_access_token_fails(client: TestClient, db: Session) -> None:
    """Access tokens must not be accepted as refresh tokens."""
    email = f"wrongtype_{uuid.uuid4().hex[:8]}@test.com"
    user = crud.upsert_google_user(
        session=db, email=email, google_sub=uuid.uuid4().hex, name="Wrong Type"
    )
    access_token = security.create_access_token(str(user.id))

    resp = client.post(
        f"{settings.API_V1_STR}/auth/refresh",
        json={"refresh_token": access_token},
    )
    assert resp.status_code == 401
    assert resp.json()["code"] == "INVALID_REFRESH_TOKEN"


# ─── Protected endpoint auth check ────────────────────────────────────────────

def test_protected_endpoint_no_token(client: TestClient) -> None:
    resp = client.get(f"{settings.API_V1_STR}/users/me")
    assert resp.status_code == 401
    body = resp.json()
    assert body["code"] == "UNAUTHORIZED"


def test_protected_endpoint_invalid_token(client: TestClient) -> None:
    resp = client.get(
        f"{settings.API_V1_STR}/users/me",
        headers={"Authorization": "Bearer totally.invalid.token"},
    )
    assert resp.status_code == 401
    assert resp.json()["code"] == "UNAUTHORIZED"


def test_admin_endpoint_non_admin_user(client: TestClient, db: Session) -> None:
    """Non-admin users must receive 403 on admin-only endpoints (placeholder check via deps)."""
    email = f"nonadmin_{uuid.uuid4().hex[:8]}@test.com"
    user = crud.upsert_google_user(
        session=db, email=email, google_sub=uuid.uuid4().hex, name="Normal"
    )
    assert user.role == "user"
    token = security.create_access_token(str(user.id), role=user.role)
    # When admin routes are registered (Story 5.1), they must return 403 for role=user
    # For now we verify the token payload carries the correct role.
    import jwt
    from app.core.config import settings as cfg
    payload = jwt.decode(token, cfg.SECRET_KEY, algorithms=["HS256"])
    assert payload["role"] == "user"
