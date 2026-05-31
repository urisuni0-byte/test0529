import uuid
from collections.abc import Generator
from typing import Annotated

import jwt
from fastapi import Depends, HTTPException, status
from fastapi.security import OAuth2PasswordBearer
from jwt.exceptions import InvalidTokenError
from pydantic import ValidationError
from sqlmodel import Session

from app.core import security
from app.core.config import settings
from app.core.db import engine
from app.models import TokenPayload, User

reusable_oauth2 = OAuth2PasswordBearer(
    tokenUrl=f"{settings.API_V1_STR}/auth/google",
    auto_error=False,
)

_UNAUTHORIZED = {
    "status_code": status.HTTP_401_UNAUTHORIZED,
    "detail": {"detail": "인증이 필요합니다.", "code": "UNAUTHORIZED"},
    "headers": {"WWW-Authenticate": "Bearer"},
}


def get_db() -> Generator[Session, None, None]:
    with Session(engine) as session:
        yield session


SessionDep = Annotated[Session, Depends(get_db)]
TokenDep = Annotated[str | None, Depends(reusable_oauth2)]


def get_current_user(session: SessionDep, token: TokenDep) -> User:
    if not token:
        raise HTTPException(**_UNAUTHORIZED)
    try:
        payload = jwt.decode(
            token, settings.SECRET_KEY, algorithms=[security.ALGORITHM]
        )
        token_data = TokenPayload(**payload)
    except (InvalidTokenError, ValidationError):
        raise HTTPException(**_UNAUTHORIZED)

    if not token_data.sub:
        raise HTTPException(**_UNAUTHORIZED)

    try:
        user_uuid = uuid.UUID(token_data.sub)
    except (ValueError, AttributeError):
        raise HTTPException(**_UNAUTHORIZED)

    user = session.get(User, user_uuid)
    if not user:
        raise HTTPException(**_UNAUTHORIZED)
    if not user.is_active:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail={"detail": "계정이 정지되었습니다.", "code": "ACCOUNT_DEACTIVATED"},
        )
    return user


CurrentUser = Annotated[User, Depends(get_current_user)]


def get_current_admin(current_user: CurrentUser) -> User:
    if current_user.role != "admin":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail={"detail": "권한이 없습니다.", "code": "FORBIDDEN"},
        )
    return current_user


CurrentAdmin = Annotated[User, Depends(get_current_admin)]
