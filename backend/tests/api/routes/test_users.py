import uuid

from fastapi.testclient import TestClient
from sqlmodel import Session

from app import crud
from app.core import security
from app.models import User


def _make_auth_headers(user: User) -> dict[str, str]:
    token = security.create_access_token(str(user.id), role=user.role)
    return {"Authorization": f"Bearer {token}"}


def test_get_user_me(client: TestClient, db: Session) -> None:
    email = f"me_{uuid.uuid4().hex[:8]}@test.com"
    user = crud.upsert_google_user(
        session=db, email=email, google_sub="sub_me", name="Me User"
    )
    resp = client.get("/api/v1/users/me", headers=_make_auth_headers(user))
    assert resp.status_code == 200
    data = resp.json()
    assert data["email"] == email


def test_patch_user_me_nickname(client: TestClient, db: Session) -> None:
    email = f"patch_{uuid.uuid4().hex[:8]}@test.com"
    user = crud.upsert_google_user(
        session=db, email=email, google_sub="sub_patch", name="Patch User"
    )
    resp = client.patch(
        "/api/v1/users/me",
        json={"nickname": "새닉네임"},
        headers=_make_auth_headers(user),
    )
    assert resp.status_code == 200
    assert resp.json()["nickname"] == "새닉네임"


def test_get_user_me_no_token(client: TestClient) -> None:
    resp = client.get("/api/v1/users/me")
    assert resp.status_code == 401
    assert resp.json()["code"] == "UNAUTHORIZED"


def test_patch_nickname_too_short(client: TestClient, db: Session) -> None:
    email = f"short_{uuid.uuid4().hex[:8]}@test.com"
    user = crud.upsert_google_user(
        session=db, email=email, google_sub="sub_short", name="Short User"
    )
    resp = client.patch(
        "/api/v1/users/me",
        json={"nickname": "a"},
        headers=_make_auth_headers(user),
    )
    assert resp.status_code == 422


def test_patch_nickname_too_long(client: TestClient, db: Session) -> None:
    email = f"long_{uuid.uuid4().hex[:8]}@test.com"
    user = crud.upsert_google_user(
        session=db, email=email, google_sub="sub_long", name="Long User"
    )
    resp = client.patch(
        "/api/v1/users/me",
        json={"nickname": "a" * 16},
        headers=_make_auth_headers(user),
    )
    assert resp.status_code == 422


def test_patch_nickname_valid_boundary(client: TestClient, db: Session) -> None:
    """Boundary values: 2-char and 15-char nicknames are valid."""
    email = f"boundary_{uuid.uuid4().hex[:8]}@test.com"
    user = crud.upsert_google_user(
        session=db, email=email, google_sub="sub_boundary", name="Boundary User"
    )
    headers = _make_auth_headers(user)

    # Exactly 2 characters — minimum valid length
    resp = client.patch(
        "/api/v1/users/me",
        json={"nickname": "ab"},
        headers=headers,
    )
    assert resp.status_code == 200
    assert resp.json()["nickname"] == "ab"

    # Exactly 15 characters — maximum valid length
    resp = client.patch(
        "/api/v1/users/me",
        json={"nickname": "a" * 15},
        headers=headers,
    )
    assert resp.status_code == 200
    assert resp.json()["nickname"] == "a" * 15
