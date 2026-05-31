import uuid
from typing import Any

from fastapi import APIRouter, File, HTTPException, Query, UploadFile
from sqlmodel import func, select

from app.api.deps import CurrentUser, SessionDep
from app.core import storage
from app.models import (
    Like,
    Neighborhood,
    Product,
    ProductCreate,
    ProductDetail,
    ProductFeedItem,
    ProductFeedResponse,
    ProductImageUploadResponse,
    ProductStatus,
    ProductUpdate,
    User,
)

router = APIRouter(prefix="/products", tags=["products"])

_ACTIVE_STATUSES = [ProductStatus.SALE, ProductStatus.RESERVED]
_MAX_IMAGE_SIZE = 1024 * 1024  # 1 MB
_MAX_IMAGE_COUNT = 10


@router.post("/images", response_model=ProductImageUploadResponse)
def upload_product_images(
    _current_user: CurrentUser,
    files: list[UploadFile] = File(...),
) -> Any:
    """Upload images to R2. Returns list of public URLs.

    Two-pass: validates all files before uploading any, preventing orphaned
    R2 objects when a later file fails the size check.
    """
    if len(files) > _MAX_IMAGE_COUNT:
        raise HTTPException(
            status_code=400,
            detail={
                "detail": f"최대 {_MAX_IMAGE_COUNT}장까지 업로드할 수 있습니다.",
                "code": "IMAGE_COUNT_EXCEEDED",
            },
        )
    # Pass 1: validate all sizes before uploading anything
    contents: list[tuple[bytes, str]] = []
    for f in files:
        if f.size is not None and f.size > _MAX_IMAGE_SIZE:
            raise HTTPException(
                status_code=400,
                detail={"detail": "이미지 크기는 1MB 이하여야 합니다.", "code": "IMAGE_TOO_LARGE"},
            )
        content = f.file.read()
        if len(content) > _MAX_IMAGE_SIZE:
            raise HTTPException(
                status_code=400,
                detail={"detail": "이미지 크기는 1MB 이하여야 합니다.", "code": "IMAGE_TOO_LARGE"},
            )
        contents.append((content, f.filename or "image.jpg"))
    # Pass 2: upload only after all validations pass
    urls = [storage.upload_image(c, name) for c, name in contents]
    return ProductImageUploadResponse(urls=urls)


@router.post("", status_code=201, response_model=ProductDetail)
def create_product(
    body: ProductCreate,
    session: SessionDep,
    current_user: CurrentUser,
) -> Any:
    """Create a new product listing.

    neighborhood_id defaults to the seller's current neighborhood.
    """
    neighborhood_id = (
        body.neighborhood_id
        if body.neighborhood_id is not None
        else current_user.neighborhood_id
    )
    if not neighborhood_id:
        raise HTTPException(
            status_code=400,
            detail={
                "detail": "동네 설정이 필요합니다.",
                "code": "NEIGHBORHOOD_NOT_SET",
            },
        )
    if not session.get(Neighborhood, neighborhood_id):
        raise HTTPException(
            status_code=404,
            detail={"detail": "동네를 찾을 수 없습니다.", "code": "NEIGHBORHOOD_NOT_FOUND"},
        )

    product = Product(
        seller_id=current_user.id,
        title=body.title,
        price=body.price,
        category=body.category,
        description=body.description,
        image_urls=body.image_urls,
        neighborhood_id=neighborhood_id,
    )
    session.add(product)
    session.commit()
    session.refresh(product)

    return ProductDetail(
        id=product.id,
        seller_id=product.seller_id,
        title=product.title,
        price=product.price,
        description=product.description,
        category=product.category,
        image_urls=product.image_urls,
        created_at=product.created_at,
        like_count=0,  # 신규 상품은 likes 없음
        status=product.status,
        seller_nickname=current_user.nickname,
    )


@router.get("", response_model=ProductFeedResponse)
def get_products(
    session: SessionDep,
    neighborhood_id: int,
    page: int = Query(default=1, ge=1),
    limit: int = Query(default=20, ge=1, le=100),
) -> Any:
    """Return SALE/RESERVED products for a given neighborhood, newest first.

    Public endpoint — no authentication required.
    like_count is computed from the likes table (batch query, no N+1).
    """
    if not session.get(Neighborhood, neighborhood_id):
        raise HTTPException(
            status_code=404,
            detail={"detail": "동네를 찾을 수 없습니다.", "code": "NEIGHBORHOOD_NOT_FOUND"},
        )

    offset = (page - 1) * limit

    total = session.exec(
        select(func.count()).select_from(Product).where(
            Product.neighborhood_id == neighborhood_id,
            Product.status.in_(_ACTIVE_STATUSES),
        )
    ).one()
    products = session.exec(
        select(Product)
        .where(
            Product.neighborhood_id == neighborhood_id,
            Product.status.in_(_ACTIVE_STATUSES),
        )
        .order_by(Product.created_at.desc())
        .offset(offset)
        .limit(limit)
    ).all()

    # 배치 like_count 집계 (N+1 방지)
    product_ids = [p.id for p in products]
    if product_ids:
        like_count_rows = session.exec(
            select(Like.product_id, func.count(Like.user_id).label("cnt"))
            .where(Like.product_id.in_(product_ids))
            .group_by(Like.product_id)
        ).all()
        like_counts: dict[uuid.UUID, int] = {row[0]: row[1] for row in like_count_rows}
    else:
        like_counts = {}

    items = [
        ProductFeedItem(
            id=p.id,
            seller_id=p.seller_id,
            title=p.title,
            price=p.price,
            created_at=p.created_at,
            like_count=like_counts.get(p.id, 0),
            status=p.status,
            thumbnail_url=p.image_urls[0] if p.image_urls else None,
        )
        for p in products
    ]

    return ProductFeedResponse(items=items, total=total, page=page, limit=limit)


@router.patch("/{product_id}", response_model=ProductDetail)
def update_product(
    product_id: uuid.UUID,
    body: ProductUpdate,
    session: SessionDep,
    current_user: CurrentUser,
) -> Any:
    """부분 수정. 판매자 본인만 가능."""
    product = session.get(Product, product_id)
    if not product:
        raise HTTPException(
            status_code=404,
            detail={"detail": "상품을 찾을 수 없습니다.", "code": "PRODUCT_NOT_FOUND"},
        )
    if product.seller_id != current_user.id:
        raise HTTPException(
            status_code=403,
            detail={"detail": "권한이 없습니다.", "code": "FORBIDDEN"},
        )

    update_data = body.model_dump(exclude_unset=True)
    product.sqlmodel_update(update_data)
    session.add(product)
    session.commit()
    session.refresh(product)

    seller = session.get(User, product.seller_id)
    like_count = session.exec(
        select(func.count()).select_from(Like).where(Like.product_id == product.id)
    ).one()
    return ProductDetail(
        id=product.id,
        seller_id=product.seller_id,
        title=product.title,
        price=product.price,
        description=product.description,
        category=product.category,
        image_urls=product.image_urls,
        created_at=product.created_at,
        like_count=like_count,
        status=product.status,
        seller_nickname=seller.nickname if seller else None,
    )


@router.delete("/{product_id}", status_code=204, response_model=None)
def delete_product(
    product_id: uuid.UUID,
    session: SessionDep,
    current_user: CurrentUser,
) -> Any:
    """삭제. 판매자 본인만 가능. R2 이미지는 MVP에서 별도 정리 안 함."""
    product = session.get(Product, product_id)
    if not product:
        raise HTTPException(
            status_code=404,
            detail={"detail": "상품을 찾을 수 없습니다.", "code": "PRODUCT_NOT_FOUND"},
        )
    if product.seller_id != current_user.id:
        raise HTTPException(
            status_code=403,
            detail={"detail": "권한이 없습니다.", "code": "FORBIDDEN"},
        )
    session.delete(product)
    session.commit()
    return None


@router.get("/{product_id}", response_model=ProductDetail)
def get_product(session: SessionDep, product_id: uuid.UUID) -> Any:
    """Return full product detail by ID.

    Public endpoint — no authentication required.
    Returns 404 if product not found.
    like_count is computed from the likes table.
    """
    product = session.get(Product, product_id)
    if not product:
        raise HTTPException(
            status_code=404,
            detail={"detail": "상품을 찾을 수 없습니다.", "code": "PRODUCT_NOT_FOUND"},
        )

    seller = session.get(User, product.seller_id)
    like_count = session.exec(
        select(func.count()).select_from(Like).where(Like.product_id == product.id)
    ).one()
    return ProductDetail(
        id=product.id,
        seller_id=product.seller_id,
        title=product.title,
        price=product.price,
        description=product.description,
        category=product.category,
        image_urls=product.image_urls,
        created_at=product.created_at,
        like_count=like_count,
        status=product.status,
        seller_nickname=seller.nickname if seller else None,
    )
