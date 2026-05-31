"""Story 5.1~5.4 — 어드민 인증, 상품·사용자·대시보드 관리 엔드포인트."""
import uuid
from datetime import datetime, timezone
from typing import Any

from fastapi import APIRouter, HTTPException, Query, status
from pydantic import BaseModel, EmailStr
from sqlmodel import col, func, select

from app.api.deps import CurrentAdmin, SessionDep
from app.core import security
from app.crud import get_user_by_email
from app.models import AccessTokenResponse, ChatRoom, Product, User

router = APIRouter(prefix="/admin", tags=["admin"])


class AdminLoginRequest(BaseModel):
    email: EmailStr
    password: str


@router.post("/auth/login", response_model=AccessTokenResponse)
def admin_login(body: AdminLoginRequest, session: SessionDep) -> Any:
    """이메일·비밀번호로 어드민 로그인. role=admin 계정만 허용."""
    user = get_user_by_email(session=session, email=body.email)

    # 존재 여부 + 비밀번호 확인 (단락 평가 방지: 항상 일관된 흐름)
    password_valid = (
        user is not None
        and user.hashed_password is not None
        and security.verify_password(body.password, user.hashed_password)
    )

    if not password_valid:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail={"detail": "이메일 또는 비밀번호가 올바르지 않습니다.", "code": "INVALID_CREDENTIALS"},
        )

    if not user.is_active:  # type: ignore[union-attr]
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail={"detail": "계정이 정지되었습니다.", "code": "ACCOUNT_DEACTIVATED"},
        )

    if user.role != "admin":  # type: ignore[union-attr]
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail={"detail": "권한이 없습니다.", "code": "FORBIDDEN"},
        )

    return AccessTokenResponse(
        access_token=security.create_access_token(str(user.id), role=user.role),  # type: ignore[union-attr]
    )


# ─── 상품 관리 ─────────────────────────────────────────────────────────────────

class AdminProductItem(BaseModel):
    id: uuid.UUID
    title: str
    price: int
    status: str
    seller_nickname: str | None
    created_at: datetime


@router.get("/products")
def list_admin_products(
    session: SessionDep,
    current_admin: CurrentAdmin,
    status: str | None = Query(default=None),
    seller: str | None = Query(default=None),
) -> Any:
    """전체 상품 목록. 상태·판매자 닉네임으로 필터링 가능."""
    query = select(Product, User).join(User, User.id == Product.seller_id)

    if status:
        query = query.where(Product.status == status)
    if seller:
        query = query.where(col(User.nickname).ilike(f"%{seller}%"))

    query = query.order_by(col(Product.created_at).desc())
    rows = session.exec(query).all()

    items = [
        AdminProductItem(
            id=product.id,
            title=product.title,
            price=product.price,
            status=product.status,
            seller_nickname=user.nickname,
            created_at=product.created_at,
        )
        for product, user in rows
    ]
    return {"items": items, "total": len(items)}


@router.delete("/products/{product_id}", status_code=204, response_model=None)
def delete_admin_product(
    product_id: uuid.UUID,
    session: SessionDep,
    current_admin: CurrentAdmin,
) -> None:
    """어드민 상품 강제 삭제. 소유자 체크 없음."""
    product = session.get(Product, product_id)
    if not product:
        raise HTTPException(
            status_code=404,
            detail={"detail": "상품을 찾을 수 없습니다.", "code": "PRODUCT_NOT_FOUND"},
        )
    session.delete(product)
    session.commit()


# ─── 사용자 관리 ───────────────────────────────────────────────────────────────

class AdminUserItem(BaseModel):
    id: uuid.UUID
    email: str
    nickname: str | None
    is_active: bool
    created_at: datetime


@router.get("/users")
def list_admin_users(
    session: SessionDep,
    current_admin: CurrentAdmin,
) -> Any:
    """일반 사용자 목록. role=admin 계정 제외. created_at 내림차순."""
    users = session.exec(
        select(User)
        .where(User.role != "admin")
        .order_by(col(User.created_at).desc())
    ).all()
    items = [
        AdminUserItem(
            id=u.id,
            email=u.email,
            nickname=u.nickname,
            is_active=u.is_active,
            created_at=u.created_at,
        )
        for u in users
    ]
    return {"items": items, "total": len(items)}


@router.patch("/users/{user_id}/deactivate")
def deactivate_admin_user(
    user_id: uuid.UUID,
    session: SessionDep,
    current_admin: CurrentAdmin,
) -> Any:
    """일반 사용자 비활성화. is_active=False 설정. 어드민 계정 보호."""
    if user_id == current_admin.id:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail={"detail": "자신의 계정은 비활성화할 수 없습니다.", "code": "CANNOT_DEACTIVATE_SELF"},
        )
    user = session.get(User, user_id)
    if not user:
        raise HTTPException(
            status_code=404,
            detail={"detail": "사용자를 찾을 수 없습니다.", "code": "USER_NOT_FOUND"},
        )
    if user.role == "admin":
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail={"detail": "어드민 계정은 비활성화할 수 없습니다.", "code": "CANNOT_DEACTIVATE_ADMIN"},
        )
    user.is_active = False
    session.commit()
    session.refresh(user)
    return AdminUserItem(
        id=user.id,
        email=user.email,
        nickname=user.nickname,
        is_active=user.is_active,
        created_at=user.created_at,
    )


# ─── 대시보드 통계 ─────────────────────────────────────────────────────────────

class AdminStats(BaseModel):
    total_users: int
    total_products: int
    new_users_today: int
    new_products_today: int
    active_chat_rooms: int


@router.get("/stats", response_model=AdminStats)
def get_admin_stats(
    session: SessionDep,
    current_admin: CurrentAdmin,
) -> Any:
    """운영 지표 실시간 집계. 어드민 계정 제외."""
    today_start = datetime.now(timezone.utc).replace(
        hour=0, minute=0, second=0, microsecond=0
    )

    total_users = session.exec(
        select(func.count()).select_from(User).where(User.role != "admin")
    ).one()

    total_products = session.exec(
        select(func.count()).select_from(Product)
    ).one()

    new_users_today = session.exec(
        select(func.count()).select_from(User)
        .where(User.role != "admin")
        .where(User.created_at >= today_start)
    ).one()

    new_products_today = session.exec(
        select(func.count()).select_from(Product)
        .where(Product.created_at >= today_start)
    ).one()

    active_chat_rooms = session.exec(
        select(func.count()).select_from(ChatRoom)
    ).one()

    return AdminStats(
        total_users=total_users,
        total_products=total_products,
        new_users_today=new_users_today,
        new_products_today=new_products_today,
        active_chat_rooms=active_chat_rooms,
    )
