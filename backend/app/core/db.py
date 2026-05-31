from sqlmodel import Session, create_engine, select

from app.core.config import settings
from app.core.security import get_password_hash
from app.models import User

engine = create_engine(str(settings.SQLALCHEMY_DATABASE_URI))


def init_db(session: Session) -> None:
    """Ensure a default admin account exists with hashed password."""
    user = session.exec(
        select(User).where(User.email == settings.FIRST_SUPERUSER)
    ).first()
    if not user:
        admin = User(
            email=settings.FIRST_SUPERUSER,
            nickname="admin",
            role="admin",
            is_active=True,
            hashed_password=get_password_hash(settings.FIRST_SUPERUSER_PASSWORD),
        )
        session.add(admin)
        session.commit()
        session.refresh(admin)
    elif not user.hashed_password:
        # 기존 admin 유저에 비밀번호 해시 추가
        user.hashed_password = get_password_hash(settings.FIRST_SUPERUSER_PASSWORD)
        session.add(user)
        session.commit()
