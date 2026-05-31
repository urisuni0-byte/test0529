import uuid

from sqlmodel import Session

from app import crud


def test_get_user_by_email_not_found(db: Session) -> None:
    result = crud.get_user_by_email(session=db, email="nonexistent@example.com")
    assert result is None


def test_upsert_google_user_creates_new(db: Session) -> None:
    email = f"new_{uuid.uuid4().hex[:8]}@gmail.com"
    user = crud.upsert_google_user(
        session=db, email=email, google_sub="google_sub_123", name="Test User"
    )
    assert user.email == email
    assert user.nickname is None  # nickname set via onboarding, not at creation
    assert user.role == "user"
    assert user.is_active is True


def test_upsert_google_user_returns_existing(db: Session) -> None:
    email = f"existing_{uuid.uuid4().hex[:8]}@gmail.com"
    user1 = crud.upsert_google_user(
        session=db, email=email, google_sub="sub_abc", name="Original"
    )
    user2 = crud.upsert_google_user(
        session=db, email=email, google_sub="sub_abc", name="Original"
    )
    assert user1.id == user2.id
