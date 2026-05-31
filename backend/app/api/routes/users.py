from typing import Any

from fastapi import APIRouter, HTTPException, status
from sqlalchemy.exc import IntegrityError

from app.api.deps import CurrentUser, SessionDep
from app.models import Message, Neighborhood, UserPublic, UserUpdate

router = APIRouter(prefix="/users", tags=["users"])


@router.get("/me", response_model=UserPublic)
def read_user_me(current_user: CurrentUser) -> Any:
    return current_user


@router.patch("/me", response_model=UserPublic)
def update_user_me(
    *, session: SessionDep, user_in: UserUpdate, current_user: CurrentUser
) -> Any:
    if user_in.neighborhood_id is not None:
        exists = session.get(Neighborhood, user_in.neighborhood_id)
        if not exists:
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail={
                    "detail": "존재하지 않는 동네 ID입니다.",
                    "code": "INVALID_NEIGHBORHOOD_ID",
                },
            )

    update_data = user_in.model_dump(exclude_unset=True)
    current_user.sqlmodel_update(update_data)
    session.add(current_user)
    try:
        session.commit()
    except IntegrityError:
        session.rollback()
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail={
                "detail": "이미 사용 중인 닉네임입니다.",
                "code": "NICKNAME_ALREADY_TAKEN",
            },
        )
    session.refresh(current_user)
    return current_user


@router.delete("/me", response_model=Message)
def delete_user_me(session: SessionDep, current_user: CurrentUser) -> Message:
    session.delete(current_user)
    session.commit()
    return Message(message="User deleted successfully")
