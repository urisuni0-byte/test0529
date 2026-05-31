import uuid
from typing import Any

from fastapi import APIRouter, HTTPException, status

from pydantic import BaseModel, EmailStr

from app import crud
from app.api.deps import SessionDep
from app.core import security
from app.core.config import settings
from app.models import (
    AccessTokenResponse,
    AuthTokenResponse,
    GoogleLoginRequest,
    RefreshRequest,
    User,
)
from app.services.oauth import verify_google_id_token

router = APIRouter(prefix="/auth", tags=["auth"])


@router.post("/google", response_model=AuthTokenResponse)
async def login_google(session: SessionDep, body: GoogleLoginRequest) -> Any:
    """Exchange a Google id_token for a JWT token pair."""
    google_user = await verify_google_id_token(
        id_token=body.id_token, client_id=settings.GOOGLE_CLIENT_ID
    )

    user = crud.upsert_google_user(
        session=session,
        email=google_user["email"],
        google_sub=google_user["sub"],
        name=google_user["name"],
    )

    if not user.is_active:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail={"detail": "계정이 정지되었습니다.", "code": "ACCOUNT_DEACTIVATED"},
        )

    return AuthTokenResponse(
        access_token=security.create_access_token(str(user.id), role=user.role),
        refresh_token=security.create_refresh_token(str(user.id)),
    )


@router.post("/refresh", response_model=AccessTokenResponse)
def refresh_access_token(session: SessionDep, body: RefreshRequest) -> Any:
    """Issue a new access_token from a valid refresh_token."""
    user_id_str = security.verify_refresh_token(body.refresh_token)
    if not user_id_str:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail={"detail": "리프레시 토큰이 유효하지 않습니다.", "code": "INVALID_REFRESH_TOKEN"},
            headers={"WWW-Authenticate": "Bearer"},
        )

    try:
        user_uuid = uuid.UUID(user_id_str)
    except (ValueError, AttributeError):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail={"detail": "리프레시 토큰이 유효하지 않습니다.", "code": "INVALID_REFRESH_TOKEN"},
            headers={"WWW-Authenticate": "Bearer"},
        )

    user = crud.get_user_by_id(session=session, user_id=user_uuid)
    if not user or not user.is_active:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail={"detail": "리프레시 토큰이 유효하지 않습니다.", "code": "INVALID_REFRESH_TOKEN"},
            headers={"WWW-Authenticate": "Bearer"},
        )

    return AccessTokenResponse(
        access_token=security.create_access_token(str(user.id), role=user.role),
    )
