import uuid

from sqlalchemy.exc import IntegrityError
from sqlmodel import Session, select

from app.models import User


def get_user_by_email(*, session: Session, email: str) -> User | None:
    return session.exec(select(User).where(User.email == email)).first()


def get_user_by_id(*, session: Session, user_id: uuid.UUID) -> User | None:
    return session.get(User, user_id)


def create_email_user(
    *, session: Session, email: str, hashed_password: str, nickname: str
) -> User:
    user = User(email=email, hashed_password=hashed_password, nickname=nickname)
    session.add(user)
    session.commit()
    session.refresh(user)
    return user


def upsert_google_user(
    *, session: Session, email: str, google_sub: str, name: str
) -> User:
    """Return existing user by email, or create a new one.

    New users are created with nickname=None — the onboarding flow
    asks them to choose a unique nickname before entering the app.

    Handles concurrent first-login races via IntegrityError retry.
    """
    user = get_user_by_email(session=session, email=email)
    if user:
        return user

    new_user = User(email=email, google_sub=google_sub)
    session.add(new_user)
    try:
        session.commit()
    except IntegrityError:
        session.rollback()
        existing = get_user_by_email(session=session, email=email)
        if existing:
            return existing
        raise
    session.refresh(new_user)
    return new_user
