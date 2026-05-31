import uuid
from typing import Any

from fastapi import APIRouter, HTTPException
from sqlalchemy.exc import IntegrityError
from sqlmodel import select

from app.api.deps import CurrentUser, SessionDep
from app.models import Like, Product

router = APIRouter(prefix="/products", tags=["likes"])


@router.post("/{product_id}/likes", status_code=201, response_model=None)
def like_product(
    product_id: uuid.UUID,
    session: SessionDep,
    current_user: CurrentUser,
) -> Any:
    """관심 등록. 상품 없으면 404, 이미 등록이면 409."""
    if not session.get(Product, product_id):
        raise HTTPException(
            status_code=404,
            detail={"detail": "상품을 찾을 수 없습니다.", "code": "PRODUCT_NOT_FOUND"},
        )
    like = Like(user_id=current_user.id, product_id=product_id)
    session.add(like)
    try:
        session.commit()
    except IntegrityError:
        session.rollback()
        raise HTTPException(
            status_code=409,
            detail={"detail": "이미 관심 등록된 상품입니다.", "code": "LIKE_ALREADY_EXISTS"},
        )
    return None


@router.delete("/{product_id}/likes", status_code=204, response_model=None)
def unlike_product(
    product_id: uuid.UUID,
    session: SessionDep,
    current_user: CurrentUser,
) -> Any:
    """관심 해제. 등록하지 않은 경우 404."""
    like = session.exec(
        select(Like).where(
            Like.product_id == product_id,
            Like.user_id == current_user.id,
        )
    ).first()
    if not like:
        raise HTTPException(
            status_code=404,
            detail={"detail": "관심 등록 내역을 찾을 수 없습니다.", "code": "LIKE_NOT_FOUND"},
        )
    session.delete(like)
    session.commit()
    return None
