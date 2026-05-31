import uuid

from sqlmodel import Session

from app import crud
from app.core import security
from app.models import User


def create_test_user(db: Session, email: str | None = None) -> User:
    email = email or f"test_{uuid.uuid4().hex[:8]}@test.com"
    return crud.upsert_google_user(
        session=db, email=email, google_sub=uuid.uuid4().hex, name="Test User"
    )


def auth_headers_for_user(user: User) -> dict[str, str]:
    token = security.create_access_token(str(user.id), role=user.role)
    return {"Authorization": f"Bearer {token}"}
