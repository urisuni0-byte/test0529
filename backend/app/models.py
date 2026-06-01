import re as _re
import uuid
from datetime import datetime, timezone
from enum import Enum

from pydantic import field_validator
from sqlalchemy import ARRAY, Column, DateTime
from sqlalchemy import Text as SaText
from sqlalchemy import text as sa_text
from sqlmodel import Field, SQLModel


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


class ProductStatus(str, Enum):
    SALE = "SALE"
    RESERVED = "RESERVED"
    SOLD = "SOLD"


# ─── DB Table Models ───────────────────────────────────────────────────────────

class Neighborhood(SQLModel, table=True):
    __tablename__ = "neighborhoods"  # type: ignore[assignment]

    id: int = Field(primary_key=True)
    name: str = Field(max_length=50)
    parent_id: int | None = Field(
        default=None, foreign_key="neighborhoods.id", nullable=True
    )
    level: str = Field(max_length=20)


class User(SQLModel, table=True):
    __tablename__ = "users"  # type: ignore[assignment]

    id: uuid.UUID = Field(default_factory=uuid.uuid4, primary_key=True)
    email: str = Field(unique=True, index=True, max_length=255)
    nickname: str | None = Field(default=None, max_length=15, index=True)
    profile_image_url: str | None = Field(default=None)
    neighborhood_id: int | None = Field(
        default=None, foreign_key="neighborhoods.id", nullable=True
    )
    google_sub: str | None = Field(default=None, index=True)
    role: str = Field(default="user", max_length=20)
    is_active: bool = Field(default=True)
    fcm_token: str | None = Field(default=None)
    hashed_password: str | None = Field(default=None)
    created_at: datetime = Field(
        default_factory=_utcnow,
        sa_type=DateTime(timezone=True),  # type: ignore[call-arg]
    )


class Product(SQLModel, table=True):
    __tablename__ = "products"  # type: ignore[assignment]

    id: uuid.UUID = Field(default_factory=uuid.uuid4, primary_key=True)
    seller_id: uuid.UUID = Field(foreign_key="users.id", nullable=False)
    title: str = Field(max_length=40)
    price: int
    description: str | None = Field(default=None)
    category: str = Field(max_length=50)
    image_urls: list[str] = Field(
        default_factory=list,
        sa_column=Column(ARRAY(SaText()), nullable=False, server_default=sa_text("'{}'")),
    )
    status: str = Field(default=ProductStatus.SALE, max_length=20)
    neighborhood_id: int = Field(foreign_key="neighborhoods.id")
    created_at: datetime = Field(
        default_factory=_utcnow,
        sa_type=DateTime(timezone=True),  # type: ignore[call-arg]
    )


# ─── Response Schemas ──────────────────────────────────────────────────────────

class UserPublic(SQLModel):
    id: uuid.UUID
    email: str
    nickname: str | None = None
    profile_image_url: str | None = None
    neighborhood_id: int | None = None
    role: str
    is_active: bool
    created_at: datetime


_NICKNAME_RE = _re.compile(r"^[가-힣a-zA-Z0-9]{2,15}$")


class UserUpdate(SQLModel):
    """PATCH /users/me — only updatable fields exposed to users.

    `None` default means "field absent from request" (handled by exclude_unset).
    The field_validator rejects an *explicit* `{"nickname": null}` — to skip
    updating nickname, simply omit the key from the request body.
    """
    nickname: str | None = Field(default=None, min_length=2, max_length=15)
    fcm_token: str | None = None
    neighborhood_id: int | None = None
    profile_image_url: str | None = None

    @field_validator("nickname", mode="before")
    @classmethod
    def validate_nickname(cls, v: object) -> object:
        """Reject explicit null and enforce character allowlist."""
        if v is None:
            raise ValueError("닉네임은 비울 수 없습니다.")
        if isinstance(v, str) and not _NICKNAME_RE.match(v):
            raise ValueError("닉네임은 한글, 영문, 숫자만 사용할 수 있습니다. (2~15자)")
        return v


# ─── Auth Schemas ──────────────────────────────────────────────────────────────

class AuthTokenResponse(SQLModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"


class AccessTokenResponse(SQLModel):
    access_token: str
    token_type: str = "bearer"


class GoogleLoginRequest(SQLModel):
    id_token: str


class RefreshRequest(SQLModel):
    refresh_token: str


class EmailRegisterRequest(SQLModel):
    email: str
    password: str
    nickname: str


class EmailLoginRequest(SQLModel):
    email: str
    password: str


# ─── JWT Payload ───────────────────────────────────────────────────────────────

class TokenPayload(SQLModel):
    sub: str | None = None
    role: str | None = None


# ─── Generic ───────────────────────────────────────────────────────────────────

class Message(SQLModel):
    message: str


# ─── Product Schemas ───────────────────────────────────────────────────────────

class ProductFeedItem(SQLModel):
    id: uuid.UUID
    seller_id: uuid.UUID
    title: str
    price: int
    created_at: datetime
    like_count: int
    status: str
    thumbnail_url: str | None


class ProductFeedResponse(SQLModel):
    items: list[ProductFeedItem]
    total: int
    page: int
    limit: int


class ProductDetail(SQLModel):
    id: uuid.UUID
    seller_id: uuid.UUID
    title: str
    price: int
    description: str | None
    category: str
    image_urls: list[str]
    created_at: datetime
    like_count: int
    status: str
    seller_nickname: str | None


# ─── Product Create / Upload Schemas ──────────────────────────────────────────

class ProductCreate(SQLModel):
    title: str = Field(max_length=40)
    price: int = Field(ge=0)
    category: str = Field(max_length=50)
    description: str | None = Field(default=None, max_length=2000)
    image_urls: list[str] = Field(default_factory=list, max_length=10)
    neighborhood_id: int | None = None


class ProductImageUploadResponse(SQLModel):
    urls: list[str]


# ─── Like Table Model ─────────────────────────────────────────────────────────

class Like(SQLModel, table=True):
    __tablename__ = "likes"  # type: ignore[assignment]

    user_id: uuid.UUID = Field(foreign_key="users.id", primary_key=True)
    product_id: uuid.UUID = Field(foreign_key="products.id", primary_key=True)
    created_at: datetime = Field(
        default_factory=_utcnow,
        sa_type=DateTime(timezone=True),  # type: ignore[call-arg]
    )


# ─── Chat Table Models ───────────────────────────────────────────────────────

class ChatRoom(SQLModel, table=True):
    __tablename__ = "chat_rooms"  # type: ignore[assignment]

    id: uuid.UUID = Field(default_factory=uuid.uuid4, primary_key=True)
    product_id: uuid.UUID = Field(foreign_key="products.id")
    created_at: datetime = Field(
        default_factory=_utcnow,
        sa_type=DateTime(timezone=True),  # type: ignore[call-arg]
    )


class ChatRoomMember(SQLModel, table=True):
    __tablename__ = "chat_room_members"  # type: ignore[assignment]

    chat_room_id: uuid.UUID = Field(foreign_key="chat_rooms.id", primary_key=True)
    user_id: uuid.UUID = Field(foreign_key="users.id", primary_key=True)
    last_read_at: datetime | None = Field(
        default=None,
        sa_type=DateTime(timezone=True),  # type: ignore[call-arg]
    )


class ChatMessage(SQLModel, table=True):
    __tablename__ = "messages"  # type: ignore[assignment]

    id: uuid.UUID = Field(default_factory=uuid.uuid4, primary_key=True)
    room_id: uuid.UUID = Field(foreign_key="chat_rooms.id")
    sender_id: uuid.UUID = Field(foreign_key="users.id")
    content: str = Field(sa_column=Column(SaText(), nullable=False))
    created_at: datetime = Field(
        default_factory=_utcnow,
        sa_type=DateTime(timezone=True),  # type: ignore[call-arg]
    )


# ─── Product Update Schema ────────────────────────────────────────────────────

class ProductUpdate(SQLModel):
    """PATCH /products/{id} — 판매자가 수정 가능한 필드만 노출.

    None 기본값 = 요청에서 해당 필드 생략 (exclude_unset 패턴).
    """

    title: str | None = Field(default=None, max_length=40)
    price: int | None = Field(default=None, ge=0)
    description: str | None = None
    status: str | None = None

    @field_validator("status", mode="before")
    @classmethod
    def validate_status(cls, v: object) -> object:
        if v is not None and v not in {s.value for s in ProductStatus}:
            valid = ", ".join(s.value for s in ProductStatus)
            raise ValueError(f"유효한 상태값: {valid}")
        return v
