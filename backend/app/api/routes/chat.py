"""Story 4.1 — 채팅 REST API: 채팅방 생성, 목록, 메시지 조회, 읽음 처리."""
import uuid
from datetime import datetime, timezone
from typing import Any

from fastapi import APIRouter, HTTPException, Query, Response, status
from pydantic import BaseModel
from sqlmodel import col, func, select

from app.api.deps import CurrentUser, SessionDep
from app.models import ChatMessage, ChatRoom, ChatRoomMember, Product, User

router = APIRouter(prefix="/chat-rooms", tags=["chat"])


# ─── Schemas ──────────────────────────────────────────────────────────────────

class ChatRoomCreateRequest(BaseModel):
    product_id: uuid.UUID


class ChatRoomCreateResponse(BaseModel):
    id: uuid.UUID
    product_id: uuid.UUID
    created_at: datetime
    is_new: bool


class ProductSummary(BaseModel):
    id: uuid.UUID
    title: str
    price: int
    thumbnail_url: str | None
    status: str


class ChatRoomListItem(BaseModel):
    id: uuid.UUID
    product: ProductSummary
    other_user_nickname: str
    last_message: str | None
    last_message_at: datetime | None
    unread_count: int


class ChatMessagePublic(BaseModel):
    id: uuid.UUID
    room_id: uuid.UUID
    sender_id: uuid.UUID
    sender_nickname: str
    content: str
    created_at: datetime


class ChatMessagesResponse(BaseModel):
    items: list[ChatMessagePublic]
    total: int
    page: int
    limit: int


class ReadResponse(BaseModel):
    last_read_at: datetime


# ─── 헬퍼 ────────────────────────────────────────────────────────────────────

_EPOCH = datetime(1970, 1, 1, tzinfo=timezone.utc)


def _get_member_or_403(
    room_id: uuid.UUID, user_id: uuid.UUID, session: SessionDep
) -> ChatRoomMember:
    member = session.exec(
        select(ChatRoomMember).where(
            ChatRoomMember.chat_room_id == room_id,
            ChatRoomMember.user_id == user_id,
        )
    ).first()
    if not member:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail={"detail": "채팅방에 참여하지 않았습니다.", "code": "FORBIDDEN"},
        )
    return member


# ─── POST /chat-rooms ─────────────────────────────────────────────────────────

@router.post("", status_code=status.HTTP_201_CREATED, response_model=ChatRoomCreateResponse)
def create_chat_room(
    body: ChatRoomCreateRequest,
    session: SessionDep,
    current_user: CurrentUser,
    response: Response,
) -> ChatRoomCreateResponse:
    """채팅방 생성 (201) 또는 기존 방 반환 (200)."""
    product = session.get(Product, body.product_id)
    if not product:
        raise HTTPException(
            status_code=404,
            detail={"detail": "상품을 찾을 수 없습니다.", "code": "PRODUCT_NOT_FOUND"},
        )

    if product.seller_id == current_user.id:
        raise HTTPException(
            status_code=400,
            detail={"detail": "본인 상품에는 채팅을 시작할 수 없습니다.", "code": "SELLER_CANNOT_CHAT"},
        )

    existing_room = session.exec(
        select(ChatRoom)
        .join(ChatRoomMember, ChatRoomMember.chat_room_id == ChatRoom.id)
        .where(
            ChatRoom.product_id == body.product_id,
            ChatRoomMember.user_id == current_user.id,
        )
    ).first()

    if existing_room:
        response.status_code = status.HTTP_200_OK
        return ChatRoomCreateResponse(
            id=existing_room.id,
            product_id=existing_room.product_id,
            created_at=existing_room.created_at,
            is_new=False,
        )

    room = ChatRoom(product_id=body.product_id)
    session.add(room)
    session.flush()  # room.id 확보 (commit 전)

    session.add(ChatRoomMember(chat_room_id=room.id, user_id=current_user.id))
    session.add(ChatRoomMember(chat_room_id=room.id, user_id=product.seller_id))
    session.commit()
    session.refresh(room)

    return ChatRoomCreateResponse(
        id=room.id,
        product_id=room.product_id,
        created_at=room.created_at,
        is_new=True,
    )


# ─── GET /chat-rooms ──────────────────────────────────────────────────────────

@router.get("", response_model=list[ChatRoomListItem])
def list_chat_rooms(
    session: SessionDep,
    current_user: CurrentUser,
) -> Any:
    """내가 참여 중인 채팅방 목록 (최근 메시지 순)."""
    my_room_ids: list[uuid.UUID] = session.exec(
        select(ChatRoomMember.chat_room_id).where(
            ChatRoomMember.user_id == current_user.id
        )
    ).all()

    if not my_room_ids:
        return []

    result: list[ChatRoomListItem] = []
    for room_id in my_room_ids:
        room = session.get(ChatRoom, room_id)
        if not room:
            continue

        product = session.get(Product, room.product_id)
        if not product:
            continue

        other_member = session.exec(
            select(ChatRoomMember).where(
                ChatRoomMember.chat_room_id == room_id,
                ChatRoomMember.user_id != current_user.id,
            )
        ).first()
        other_user = session.get(User, other_member.user_id) if other_member else None

        last_msg = session.exec(
            select(ChatMessage)
            .where(ChatMessage.room_id == room_id)
            .order_by(col(ChatMessage.created_at).desc())
        ).first()

        my_member = session.exec(
            select(ChatRoomMember).where(
                ChatRoomMember.chat_room_id == room_id,
                ChatRoomMember.user_id == current_user.id,
            )
        ).first()
        since = (my_member.last_read_at if my_member and my_member.last_read_at else _EPOCH)

        unread_count: int = session.exec(
            select(func.count(ChatMessage.id)).where(
                ChatMessage.room_id == room_id,
                ChatMessage.created_at > since,
                ChatMessage.sender_id != current_user.id,
            )
        ).one()

        result.append(
            ChatRoomListItem(
                id=room.id,
                product=ProductSummary(
                    id=product.id,
                    title=product.title,
                    price=product.price,
                    thumbnail_url=product.image_urls[0] if product.image_urls else None,
                    status=product.status,
                ),
                other_user_nickname=other_user.nickname or "알 수 없음" if other_user else "알 수 없음",
                last_message=last_msg.content if last_msg else None,
                last_message_at=last_msg.created_at if last_msg else None,
                unread_count=unread_count,
            )
        )

    result.sort(
        key=lambda x: x.last_message_at or _EPOCH,
        reverse=True,
    )
    return result


# ─── GET /chat-rooms/{room_id}/messages ───────────────────────────────────────

@router.get("/{room_id}/messages", response_model=ChatMessagesResponse)
def get_messages(
    room_id: uuid.UUID,
    session: SessionDep,
    current_user: CurrentUser,
    page: int = Query(default=1, ge=1),
    limit: int = Query(default=50, ge=1, le=100),
) -> Any:
    """채팅 메시지 목록 (최신순 페이지네이션). 비멤버 → 403."""
    _get_member_or_403(room_id, current_user.id, session)

    offset = (page - 1) * limit

    total: int = session.exec(
        select(func.count(ChatMessage.id)).where(ChatMessage.room_id == room_id)
    ).one()

    messages = session.exec(
        select(ChatMessage)
        .where(ChatMessage.room_id == room_id)
        .order_by(col(ChatMessage.created_at).desc())
        .offset(offset)
        .limit(limit)
    ).all()

    items: list[ChatMessagePublic] = []
    for msg in messages:
        sender = session.get(User, msg.sender_id)
        items.append(
            ChatMessagePublic(
                id=msg.id,
                room_id=msg.room_id,
                sender_id=msg.sender_id,
                sender_nickname=sender.nickname or "알 수 없음" if sender else "알 수 없음",
                content=msg.content,
                created_at=msg.created_at,
            )
        )

    return ChatMessagesResponse(items=items, total=total, page=page, limit=limit)


# ─── PATCH /chat-rooms/{room_id}/read ─────────────────────────────────────────

@router.patch("/{room_id}/read", response_model=ReadResponse)
def mark_as_read(
    room_id: uuid.UUID,
    session: SessionDep,
    current_user: CurrentUser,
) -> Any:
    """last_read_at을 현재 시각으로 갱신. 비멤버 → 403."""
    member = _get_member_or_403(room_id, current_user.id, session)
    now = datetime.now(tz=timezone.utc)
    member.last_read_at = now
    session.add(member)
    session.commit()
    return ReadResponse(last_read_at=now)
