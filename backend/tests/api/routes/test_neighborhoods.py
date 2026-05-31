import uuid

from fastapi.testclient import TestClient
from sqlmodel import Session

from app import crud
from app.core import security
from app.core.config import settings
from app.models import User


def _auth_headers(user: User) -> dict[str, str]:
    token = security.create_access_token(str(user.id), role=user.role)
    return {"Authorization": f"Bearer {token}"}


def _make_user(db: Session) -> User:
    email = f"nbtest_{uuid.uuid4().hex[:8]}@test.com"
    return crud.upsert_google_user(
        session=db, email=email, google_sub=uuid.uuid4().hex, name="NB User"
    )


class TestGetNeighborhoods:
    def test_returns_list(self, client: TestClient) -> None:
        resp = client.get(f"{settings.API_V1_STR}/neighborhoods")
        assert resp.status_code == 200
        data = resp.json()
        assert "items" in data
        assert len(data["items"]) > 0

    def test_no_auth_required(self, client: TestClient) -> None:
        """GET /neighborhoods is a public endpoint."""
        resp = client.get(f"{settings.API_V1_STR}/neighborhoods")
        assert resp.status_code == 200

    def test_items_have_required_fields(self, client: TestClient) -> None:
        resp = client.get(f"{settings.API_V1_STR}/neighborhoods")
        item = resp.json()["items"][0]
        assert "id" in item
        assert "name" in item
        assert "parent_id" in item
        assert "level" in item

    def test_has_dong_level_items(self, client: TestClient) -> None:
        resp = client.get(f"{settings.API_V1_STR}/neighborhoods")
        dongs = [i for i in resp.json()["items"] if i["level"] == "dong"]
        assert len(dongs) > 0


class TestPatchNeighborhood:
    def test_valid_neighborhood_id_saves(
        self, client: TestClient, db: Session
    ) -> None:
        user = _make_user(db)
        # Get a valid dong id
        nbs_resp = client.get(f"{settings.API_V1_STR}/neighborhoods")
        dong = next(
            i for i in nbs_resp.json()["items"] if i["level"] == "dong"
        )
        resp = client.patch(
            f"{settings.API_V1_STR}/users/me",
            json={"neighborhood_id": dong["id"]},
            headers=_auth_headers(user),
        )
        assert resp.status_code == 200
        assert resp.json()["neighborhood_id"] == dong["id"]

    def test_invalid_neighborhood_id_returns_422(
        self, client: TestClient, db: Session
    ) -> None:
        user = _make_user(db)
        resp = client.patch(
            f"{settings.API_V1_STR}/users/me",
            json={"neighborhood_id": 999999},
            headers=_auth_headers(user),
        )
        assert resp.status_code == 422
        assert resp.json()["code"] == "INVALID_NEIGHBORHOOD_ID"

    def test_null_neighborhood_id_clears(
        self, client: TestClient, db: Session
    ) -> None:
        user = _make_user(db)
        # First set a neighborhood
        nbs_resp = client.get(f"{settings.API_V1_STR}/neighborhoods")
        dong = next(
            i for i in nbs_resp.json()["items"] if i["level"] == "dong"
        )
        client.patch(
            f"{settings.API_V1_STR}/users/me",
            json={"neighborhood_id": dong["id"]},
            headers=_auth_headers(user),
        )
        # Now clear it
        resp = client.patch(
            f"{settings.API_V1_STR}/users/me",
            json={"neighborhood_id": None},
            headers=_auth_headers(user),
        )
        assert resp.status_code == 200
        assert resp.json()["neighborhood_id"] is None
