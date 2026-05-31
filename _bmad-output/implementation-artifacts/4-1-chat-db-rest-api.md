---
baseline_commit: NO_VCS
---

# Story 4.1 — 채팅 DB 모델 & REST API

**Status:** review

## Story

As a developer,
I want to create the chat room and message database schema and REST API endpoints,
So that the Flutter app can create chat rooms and load message history.

## Acceptance Criteria

**Given** 아키텍처 마이그레이션을 실행할 때
**When** `alembic upgrade head`를 실행하면
**Then** `chat_rooms`, `chat_room_members`, `messages` 테이블이 생성된다
**And** `chat_room_members`에 `last_read_at TIMESTAMP WITH TIME ZONE NULL` 컬럼이 포함된다
**And** `idx_messages_room_id`, `idx_messages_created_at` 인덱스가 생성된다

**Given** 인증된 구매자가 상품에 대한 채팅방을 생성할 때
**When** `POST /api/v1/chat-rooms`로 `{"product_id": "<uuid>"}` 를 전송하면
**Then** 채팅방과 두 멤버(판매자·구매자) `chat_room_members` 레코드가 생성되고 HTTP 201로 반환된다
**And** 동일 상품·동일 구매자의 채팅방이 이미 존재하면 기존 채팅방을 HTTP 200으로 반환한다 (중복 생성 방지)
**And** 비인증 사용자는 HTTP 401을 받는다

**Given** 인증된 사용자가 채팅 목록을 조회할 때
**When** `GET /api/v1/chat-rooms`를 호출하면
**Then** 본인이 `chat_room_members`에 있는 채팅방 목록을 최근 메시지 순으로 반환한다
**And** 각 채팅방에 상품 썸네일·제목·가격·판매상태, 마지막 메시지 내용·시각, 미읽음 수가 포함된다

**Given** 채팅방의 메시지 내역을 조회할 때
**When** `GET /api/v1/chat-rooms/{room_id}/messages?page=1&limit=50`을 호출하면
**Then** 메시지 목록을 최신순으로 반환한다 (`{"items": [...], "total": N, "page": 1, "limit": 50}`)
**And** 참여하지 않은 채팅방 조회 시 HTTP 403 `FORBIDDEN`을 반환한다

**Given** 인증된 사용자가 채팅방을 읽음 처리할 때
**When** `PATCH /api/v1/chat-rooms/{room_id}/read`를 호출하면
**Then** 해당 사용자의 `last_read_at`이 현재 시각으로 업데이트된다
**And** 참여하지 않은 채팅방에 시도하면 HTTP 403 `FORBIDDEN`을 반환한다

## Tasks / Subtasks

- [x] Task 1: Alembic 마이그레이션 008 — 채팅 테이블 생성 (AC: 1)
  - [x] `backend/app/alembic/versions/008_chat_tables.py` 생성 (down_revision="007")
  - [x] `chat_rooms` 테이블: id (UUID PK), product_id (UUID FK → products.id CASCADE), created_at
  - [x] `chat_room_members` 테이블: chat_room_id (UUID FK CASCADE), user_id (UUID FK CASCADE), last_read_at (TIMESTAMP TZ NULL), PK(chat_room_id, user_id)
  - [x] `messages` 테이블: id (UUID PK), room_id (UUID FK → chat_rooms.id CASCADE), sender_id (UUID FK → users.id CASCADE), content (TEXT NOT NULL), created_at
  - [x] 인덱스: `idx_messages_room_id`, `idx_messages_created_at`
  - [x] `uv run alembic upgrade head` 실행 확인

- [x] Task 2: `backend/app/models.py` — ChatRoom, ChatRoomMember, ChatMessage 모델 추가 (AC: 1)
  - [x] `ChatRoom(SQLModel, table=True)` — `__tablename__ = "chat_rooms"` 명시
  - [x] `ChatRoomMember(SQLModel, table=True)` — `__tablename__ = "chat_room_members"`, composite PK
  - [x] `ChatMessage(SQLModel, table=True)` — `__tablename__ = "messages"`, content는 `SaText()` (기존 alias 활용)
  - [x] 기존 모델 패턴(`sa.Uuid()`, `DateTime(timezone=True)`, `_utcnow` factory) 동일 적용

- [x] Task 3: `backend/app/api/routes/chat.py` 신규 생성 (AC: 2, 3, 4, 5)
  - [x] `POST /chat-rooms` — 채팅방 생성 (201) 또는 기존 반환 (200), 인증 필수
  - [x] `GET /chat-rooms` — 내 채팅방 목록, 인증 필수
  - [x] `GET /chat-rooms/{room_id}/messages` — 메시지 내역, 인증 필수, 비멤버 403
  - [x] `PATCH /chat-rooms/{room_id}/read` — last_read_at 갱신, 인증 필수, 비멤버 403
  - [x] `backend/app/api/main.py`에 chat 라우터 등록

- [x] Task 4: 테스트 추가 (AC: 2~5)
  - [x] `backend/tests/api/routes/test_chat.py` 신규 생성 (17개 테스트)
  - [x] test_create_room_201_with_members
  - [x] test_create_room_idempotent_200
  - [x] test_create_room_requires_auth
  - [x] test_list_rooms_only_own
  - [x] test_get_messages_pagination
  - [x] test_get_messages_forbids_non_member
  - [x] test_read_updates_last_read_at

---

## Dev Notes

### 핵심 사항 요약

1. **백엔드 전용 스토리** — Flutter 변경 없음 (Story 4.3, 4.4에서 Flutter 구현)
2. **migration 008 = new head** — 현재 head는 007 (`007_likes_table.py`)
3. **채팅방 중복 방지 로직** — UNIQUE 제약 대신 애플리케이션 레벨에서 처리: product_id + buyer_id(current_user)로 기존 방 조회
4. **판매자는 채팅방 생성 불가** — product.seller_id == current_user.id 이면 HTTP 400
5. **last_read_at 기반 미읽음 수** — `COUNT(messages WHERE room_id=? AND created_at > COALESCE(last_read_at, epoch) AND sender_id != me)`
6. **`PATCH /chat-rooms/{room_id}/read`** — Story 4.4 Flutter 채팅 목록에서 탭 시 호출 (에픽 AC: "last_read_at이 현재 시각으로 업데이트")

### 프로젝트 구조

**NEW — 새로 생성:**
```
backend/app/alembic/versions/008_chat_tables.py
backend/app/api/routes/chat.py
backend/tests/api/routes/test_chat.py
```

**UPDATE — 수정:**
```
backend/app/models.py           ← ChatRoom, ChatRoomMember, Message 모델 추가
backend/app/api/main.py         ← chat 라우터 등록
```

### 기존 코드 컨텍스트 (반드시 보존)

**`models.py` 기존 패턴 (반드시 동일 적용):**
```python
# uuid import, _utcnow 헬퍼 이미 파일 상단에 존재 — 중복 추가 금지
class Like(SQLModel, table=True):
    __tablename__ = "likes"  # type: ignore[assignment]
    user_id: uuid.UUID = Field(foreign_key="users.id", primary_key=True)
    product_id: uuid.UUID = Field(foreign_key="products.id", primary_key=True)
    created_at: datetime = Field(default_factory=_utcnow, sa_type=DateTime(timezone=True))
```

→ ChatRoom, ChatRoomMember, Message도 동일 패턴. `sa_type=DateTime(timezone=True)` 사용, `sa.DateTime` 직접 임포트 금지.

**`alembic/versions/007_likes_table.py` 마이그레이션 패턴 (그대로 따를 것):**
```python
revision: str = "008"
down_revision: Union[str, None] = "007"

# sa.Uuid() — sa.UUID(as_uuid=True) 아님
# sa.TIMESTAMP(timezone=True) + server_default=sa.text("now()")
# sa.ForeignKeyConstraint([...], [...], ondelete="CASCADE")
# sa.PrimaryKeyConstraint("col1", "col2")  ← composite PK
```

**`backend/app/api/routes/likes.py` 라우터 패턴:**
```python
from fastapi import APIRouter, Depends, HTTPException, status
from sqlmodel import Session
from ...api.deps import get_current_user, get_db  # 실제 경로 확인 후 적용
from ...models import User

router = APIRouter()

@router.post("/{product_id}/likes", status_code=status.HTTP_201_CREATED)
def like_product(product_id: uuid.UUID, current_user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    ...
```
→ `get_current_user`, `get_db` import 경로는 `likes.py`와 동일하게.

**`backend/app/api/main.py` 라우터 등록 패턴:**
```python
from .routes import chat
api_router.include_router(chat.router, prefix="/chat-rooms", tags=["chat"])
```
→ 기존 라우터 등록 줄들 참고하여 동일 패턴 적용.

**test_likes.py 헬퍼 재사용:**
```python
# test_chat.py에서 재사용할 헬퍼 — test_products.py / test_likes.py 에서 복사
_make_user(db)        # 테스트 사용자 생성
_make_auth_headers(user)  # JWT Bearer 헤더
_make_seller(db)      # 다른 사용자(판매자) 생성
_create_product(db, seller_id, neighborhood_id)  # DB 직접 상품 생성
```

---

## API 계약

### POST /api/v1/chat-rooms

**인증 필수.** 구매자(current_user ≠ product.seller_id)만 생성 가능.

**Request:**
```json
{ "product_id": "uuid-string" }
```

**Response (201 — 신규 생성):**
```json
{
  "id": "room-uuid",
  "product_id": "product-uuid",
  "created_at": "2026-05-30T10:00:00Z",
  "is_new": true
}
```

**Response (200 — 기존 방 반환):**
```json
{
  "id": "existing-room-uuid",
  "product_id": "product-uuid",
  "created_at": "2026-05-29T08:00:00Z",
  "is_new": false
}
```

- **400 SELLER_CANNOT_CHAT** — 판매자가 본인 상품 채팅방 생성 시도
- **404 PRODUCT_NOT_FOUND** — 상품 없음
- **401 UNAUTHORIZED** — 미인증

---

### GET /api/v1/chat-rooms

**인증 필수.**

**Response (200):**
```json
[
  {
    "id": "room-uuid",
    "product": {
      "id": "product-uuid",
      "title": "아이폰 15",
      "price": 900000,
      "thumbnail_url": "https://r2.../img.jpg",
      "status": "SALE"
    },
    "other_user_nickname": "김지수",
    "last_message": "안녕하세요!",
    "last_message_at": "2026-05-30T10:00:00Z",
    "unread_count": 3
  }
]
```

- 내림차순 정렬: `last_message_at` DESC (메시지 없는 방은 `chat_rooms.created_at` 기준)
- `unread_count` = `COUNT(messages WHERE room_id=? AND created_at > COALESCE(last_read_at, '1970-01-01') AND sender_id != current_user_id)`

---

### GET /api/v1/chat-rooms/{room_id}/messages

**인증 필수.** 멤버만 접근 가능.

**Query Params:** `page=1` (기본값), `limit=50` (기본값, 최대 100)

**Response (200):**
```json
{
  "items": [
    {
      "id": "msg-uuid",
      "room_id": "room-uuid",
      "sender_id": "user-uuid",
      "sender_nickname": "홍길동",
      "content": "안녕하세요!",
      "created_at": "2026-05-30T10:00:00Z"
    }
  ],
  "total": 42,
  "page": 1,
  "limit": 50
}
```

- **최신 메시지가 첫 번째** (created_at DESC) — Flutter에서 역순 렌더링
- **403 FORBIDDEN** — 비멤버

---

### PATCH /api/v1/chat-rooms/{room_id}/read

**인증 필수.** 멤버만 접근 가능.

**Response (200):**
```json
{ "last_read_at": "2026-05-30T10:05:00Z" }
```

- **403 FORBIDDEN** — 비멤버
- Story 4.4 Flutter 채팅 목록에서 방 탭 시 호출

---

## 구현 상세

### 1. `backend/app/alembic/versions/008_chat_tables.py`

```python
"""create chat tables

Revision ID: 008
Revises: 007
Create Date: 2026-05-30
"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "008"
down_revision: Union[str, None] = "007"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # chat_rooms
    op.create_table(
        "chat_rooms",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("product_id", sa.Uuid(), nullable=False),
        sa.Column(
            "created_at",
            sa.TIMESTAMP(timezone=True),
            nullable=False,
            server_default=sa.text("now()"),
        ),
        sa.ForeignKeyConstraint(["product_id"], ["products.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
    )

    # chat_room_members
    op.create_table(
        "chat_room_members",
        sa.Column("chat_room_id", sa.Uuid(), nullable=False),
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("last_read_at", sa.TIMESTAMP(timezone=True), nullable=True),
        sa.ForeignKeyConstraint(["chat_room_id"], ["chat_rooms.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("chat_room_id", "user_id"),
    )

    # messages
    op.create_table(
        "messages",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("room_id", sa.Uuid(), nullable=False),
        sa.Column("sender_id", sa.Uuid(), nullable=False),
        sa.Column("content", sa.Text(), nullable=False),
        sa.Column(
            "created_at",
            sa.TIMESTAMP(timezone=True),
            nullable=False,
            server_default=sa.text("now()"),
        ),
        sa.ForeignKeyConstraint(["room_id"], ["chat_rooms.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["sender_id"], ["users.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("idx_messages_room_id", "messages", ["room_id"])
    op.create_index("idx_messages_created_at", "messages", ["created_at"])


def downgrade() -> None:
    op.drop_index("idx_messages_created_at", table_name="messages")
    op.drop_index("idx_messages_room_id", table_name="messages")
    op.drop_table("messages")
    op.drop_table("chat_room_members")
    op.drop_table("chat_rooms")
```

### 2. `backend/app/models.py` — 채팅 모델 추가

파일 끝(Like 모델 아래)에 추가:

```python
# ─── Chat Models ─────────────────────────────────────────────────────────────

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


class Message(SQLModel, table=True):
    __tablename__ = "messages"  # type: ignore[assignment]

    id: uuid.UUID = Field(default_factory=uuid.uuid4, primary_key=True)
    room_id: uuid.UUID = Field(foreign_key="chat_rooms.id")
    sender_id: uuid.UUID = Field(foreign_key="users.id")
    content: str = Field(sa_column=Column(Text, nullable=False))
    created_at: datetime = Field(
        default_factory=_utcnow,
        sa_type=DateTime(timezone=True),  # type: ignore[call-arg]
    )
```

> **주의**: `Column(Text, ...)` 사용 시 `from sqlalchemy import Column, Text` import 필요 — 기존 파일에 이미 있는지 확인 후 없으면 추가.

### 3. `backend/app/api/routes/chat.py` (NEW)

```python
import uuid
from datetime import datetime, timezone
from typing import Any

from fastapi import APIRouter, Depends, HTTPException, Query, status
from pydantic import BaseModel
from sqlmodel import Session, select, func, col

from ...api.deps import get_current_user, get_db  # 실제 경로는 likes.py 참고
from ...models import ChatRoom, ChatRoomMember, Message, Product, User

router = APIRouter()


# ─── Schemas (inline — 별도 schemas/chat.py 파일 불필요) ───────────────────────

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


class MessagePublic(BaseModel):
    id: uuid.UUID
    room_id: uuid.UUID
    sender_id: uuid.UUID
    sender_nickname: str
    content: str
    created_at: datetime


class MessagesResponse(BaseModel):
    items: list[MessagePublic]
    total: int
    page: int
    limit: int


class ReadResponse(BaseModel):
    last_read_at: datetime


# ─── 헬퍼: 멤버 여부 확인 ──────────────────────────────────────────────────────

def _get_member_or_403(room_id: uuid.UUID, user_id: uuid.UUID, db: Session) -> ChatRoomMember:
    member = db.exec(
        select(ChatRoomMember).where(
            ChatRoomMember.chat_room_id == room_id,
            ChatRoomMember.user_id == user_id,
        )
    ).first()
    if not member:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail={"detail": "채팅방에 참여하지 않았습니다.", "code": "FORBIDDEN"})
    return member


# ─── POST /chat-rooms ─────────────────────────────────────────────────────────

@router.post("", status_code=status.HTTP_201_CREATED, response_model=ChatRoomCreateResponse)
def create_chat_room(
    body: ChatRoomCreateRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> Any:
    # 상품 조회
    product = db.get(Product, body.product_id)
    if not product:
        raise HTTPException(status_code=404, detail={"detail": "상품을 찾을 수 없습니다.", "code": "PRODUCT_NOT_FOUND"})

    # 판매자는 본인 상품 채팅방 생성 불가
    if product.seller_id == current_user.id:
        raise HTTPException(status_code=400, detail={"detail": "본인 상품에는 채팅을 시작할 수 없습니다.", "code": "SELLER_CANNOT_CHAT"})

    # 기존 채팅방 조회: 동일 product_id + 현재 사용자가 멤버인 방
    existing_room = db.exec(
        select(ChatRoom)
        .join(ChatRoomMember, ChatRoomMember.chat_room_id == ChatRoom.id)
        .where(
            ChatRoom.product_id == body.product_id,
            ChatRoomMember.user_id == current_user.id,
        )
    ).first()

    if existing_room:
        # 200으로 변경하여 반환 (Response 객체 직접 반환 필요)
        from fastapi.responses import JSONResponse
        return JSONResponse(
            status_code=status.HTTP_200_OK,
            content={
                "id": str(existing_room.id),
                "product_id": str(existing_room.product_id),
                "created_at": existing_room.created_at.isoformat(),
                "is_new": False,
            },
        )

    # 신규 채팅방 생성
    room = ChatRoom(product_id=body.product_id)
    db.add(room)
    db.flush()  # room.id 확보

    # 멤버 2명 추가 (구매자 + 판매자)
    buyer_member = ChatRoomMember(chat_room_id=room.id, user_id=current_user.id)
    seller_member = ChatRoomMember(chat_room_id=room.id, user_id=product.seller_id)
    db.add(buyer_member)
    db.add(seller_member)
    db.commit()
    db.refresh(room)

    return ChatRoomCreateResponse(
        id=room.id,
        product_id=room.product_id,
        created_at=room.created_at,
        is_new=True,
    )


# ─── GET /chat-rooms ──────────────────────────────────────────────────────────

@router.get("", response_model=list[ChatRoomListItem])
def list_chat_rooms(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> Any:
    # 내가 멤버인 모든 채팅방 ID
    my_room_ids = db.exec(
        select(ChatRoomMember.chat_room_id).where(ChatRoomMember.user_id == current_user.id)
    ).all()

    if not my_room_ids:
        return []

    result = []
    for room_id in my_room_ids:
        room = db.get(ChatRoom, room_id)
        if not room:
            continue

        # 상품 정보
        product = db.get(Product, room.product_id)
        if not product:
            continue

        # 상대방 닉네임
        other_member = db.exec(
            select(ChatRoomMember).where(
                ChatRoomMember.chat_room_id == room_id,
                ChatRoomMember.user_id != current_user.id,
            )
        ).first()
        other_user = db.get(User, other_member.user_id) if other_member else None

        # 마지막 메시지
        last_msg = db.exec(
            select(Message)
            .where(Message.room_id == room_id)
            .order_by(col(Message.created_at).desc())
        ).first()

        # 미읽음 수 (last_read_at 이후 + 상대방이 보낸 메시지)
        my_member = db.exec(
            select(ChatRoomMember).where(
                ChatRoomMember.chat_room_id == room_id,
                ChatRoomMember.user_id == current_user.id,
            )
        ).first()

        from datetime import datetime as dt
        epoch = dt(1970, 1, 1, tzinfo=timezone.utc)
        since = my_member.last_read_at if my_member and my_member.last_read_at else epoch

        unread_count = db.exec(
            select(func.count(Message.id)).where(
                Message.room_id == room_id,
                Message.created_at > since,
                Message.sender_id != current_user.id,
            )
        ).one()

        product_summary = ProductSummary(
            id=product.id,
            title=product.title,
            price=product.price,
            thumbnail_url=product.image_urls[0] if product.image_urls else None,
            status=product.status,
        )

        result.append(ChatRoomListItem(
            id=room.id,
            product=product_summary,
            other_user_nickname=other_user.nickname if other_user else "알 수 없음",
            last_message=last_msg.content if last_msg else None,
            last_message_at=last_msg.created_at if last_msg else None,
            unread_count=unread_count,
        ))

    # 최근 메시지 순 정렬 (last_message_at DESC, 없으면 room.created_at)
    result.sort(
        key=lambda x: x.last_message_at or dt(1970, 1, 1, tzinfo=timezone.utc),
        reverse=True,
    )

    return result


# ─── GET /chat-rooms/{room_id}/messages ───────────────────────────────────────

@router.get("/{room_id}/messages", response_model=MessagesResponse)
def get_messages(
    room_id: uuid.UUID,
    page: int = Query(default=1, ge=1),
    limit: int = Query(default=50, ge=1, le=100),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> Any:
    _get_member_or_403(room_id, current_user.id, db)

    offset = (page - 1) * limit

    total = db.exec(
        select(func.count(Message.id)).where(Message.room_id == room_id)
    ).one()

    messages = db.exec(
        select(Message)
        .where(Message.room_id == room_id)
        .order_by(col(Message.created_at).desc())
        .offset(offset)
        .limit(limit)
    ).all()

    items = []
    for msg in messages:
        sender = db.get(User, msg.sender_id)
        items.append(MessagePublic(
            id=msg.id,
            room_id=msg.room_id,
            sender_id=msg.sender_id,
            sender_nickname=sender.nickname if sender else "알 수 없음",
            content=msg.content,
            created_at=msg.created_at,
        ))

    return MessagesResponse(items=items, total=total, page=page, limit=limit)


# ─── PATCH /chat-rooms/{room_id}/read ─────────────────────────────────────────

@router.patch("/{room_id}/read", response_model=ReadResponse)
def mark_as_read(
    room_id: uuid.UUID,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> Any:
    member = _get_member_or_403(room_id, current_user.id, db)
    now = datetime.now(tz=timezone.utc)
    member.last_read_at = now
    db.add(member)
    db.commit()
    return ReadResponse(last_read_at=now)
```

> **성능 주의**: GET /chat-rooms는 N개 방에 대해 N번 쿼리를 실행한다 (단순 구현). MVP 수준으로 채팅방 수가 적어 허용. 향후 단일 JOIN 쿼리로 최적화 가능.

### 4. `backend/app/api/main.py` — 라우터 등록

```python
# 기존 라우터 등록 블록에 추가 (likes 라우터 등록 방식과 동일)
from .routes import chat
api_router.include_router(chat.router, prefix="/chat-rooms", tags=["chat"])
```

### 5. `backend/tests/api/routes/test_chat.py` (NEW)

```python
import uuid
import pytest
from fastapi.testclient import TestClient
from sqlmodel import Session

# 기존 test_products.py 헬퍼 import 또는 동일 패턴 재정의
# _make_user, _make_auth_headers, _create_product 필요

def test_create_room_201_with_members(client: TestClient, db: Session):
    seller = _make_user(db)
    buyer = _make_user(db)
    product = _create_product(db, seller_id=seller.id, ...)

    resp = client.post(
        "/api/v1/chat-rooms",
        json={"product_id": str(product.id)},
        headers=_make_auth_headers(buyer),
    )
    assert resp.status_code == 201
    data = resp.json()
    assert data["is_new"] is True
    # DB에 chat_room_members 2개 확인
    members = db.exec(select(ChatRoomMember).where(...)).all()
    assert len(members) == 2


def test_create_room_idempotent_200(client, db):
    # 동일 상품·구매자로 두 번 POST → 두 번째는 200
    ...

def test_create_room_requires_auth(client):
    resp = client.post("/api/v1/chat-rooms", json={"product_id": str(uuid.uuid4())})
    assert resp.status_code == 401


def test_list_rooms_only_own(client, db):
    # user_a 채팅방에 user_b는 접근 불가 (목록에 미포함)
    ...

def test_get_messages_forbids_non_member(client, db):
    room = ...
    non_member = _make_user(db)
    resp = client.get(
        f"/api/v1/chat-rooms/{room.id}/messages",
        headers=_make_auth_headers(non_member),
    )
    assert resp.status_code == 403

def test_get_messages_pagination(client, db):
    # 60개 메시지 생성 → page=1, limit=50 → 50개, total=60
    ...

def test_read_updates_last_read_at(client, db):
    # PATCH /read 후 ChatRoomMember.last_read_at이 갱신됨
    ...
```

---

## 개발자 가드레일

### MUST 따라야 할 패턴

1. **migration revision 체인**: `down_revision = "007"` — 현재 head(007) 뒤에 이어야 함. 실제 head 확인: `uv run alembic current`

2. **`sa.Uuid()` 사용**: `sa.UUID(as_uuid=True)` 금지. Story 3.3 / 007 마이그레이션 패턴 그대로.

3. **`__tablename__` 명시**: SQLModel 기본값은 단수형이라 복수 테이블명 오류 발생. 모든 모델에 `__tablename__ = "chat_rooms"` 등 명시.

4. **에러 응답 형식**: `{"detail": "...", "code": "ERROR_CODE"}` — FastAPI 기본 `detail: str` 아님. 기존 코드베이스 모두 이 형식 사용.

5. **PATCH only, PUT 금지**: `/read` 엔드포인트도 PATCH 사용.

6. **채팅방 생성 200/201 구분**: 기존 방 반환 시 `JSONResponse(status_code=200, ...)` 명시 — FastAPI는 기본적으로 decorator의 status_code를 사용하므로 JSONResponse로 오버라이드.

7. **비멤버 403**: 메시지 조회·읽음 처리 전 멤버십 확인 필수. `_get_member_or_403` 헬퍼 재사용.

8. **`db.flush()` 후 `room.id` 사용**: 멤버 생성 시 room.id 참조 전 flush 필수. commit 전에 id 필요.

9. **`product.seller_id` 확인**: `Product` 모델의 seller_id 필드명은 기존 products.py 라우트에서 사용 중인 것과 동일해야 함. 혼동 금지.

### MUST NOT

- `@riverpod` — Flutter 코드 없음, 이 스토리는 백엔드 전용
- `schemas/chat.py` 별도 파일 생성 금지 — inline Pydantic 스키마 사용 (Story 3.3의 likes.py 패턴 참고, 기존 코드베이스에 별도 schemas 디렉토리 있는지 먼저 확인)
- `WebSocket` 코드 — Story 4.2에서 구현. 이 스토리는 REST만.
- `BackgroundTasks` (FCM) — Story 4.5에서 구현.
- N+1 쿼리 최적화 과욕 금지 — MVP 단순 구현 후 성능 이슈 시 개선.

---

## 이전 스토리 학습사항 (Story 3.3)

1. **migration revision 확인**: `uv run alembic current`로 현재 head 확인 후 `down_revision` 설정. 충돌 시 마이그레이션 실패.

2. **복합 PK = UNIQUE 제약**: `ChatRoomMember`의 `PrimaryKeyConstraint("chat_room_id", "user_id")`는 동일 사용자가 동일 방에 중복 등록되는 것을 DB 레벨에서 방지.

3. **`exclude_unset=True` PATCH 패턴**: 이 스토리에는 PATCH 바디 필드가 없지만, `ProductUpdate` 패턴(Story 3.3)을 참고하여 향후 수정 엔드포인트 추가 시 적용.

4. **라우터 prefix 설정**: `api_router.include_router(chat.router, prefix="/chat-rooms", tags=["chat"])` → 라우트 내부에서는 `@router.post("")` (빈 문자열) 사용.

5. **test fixtures**: `client`, `db` 픽스처는 기존 `conftest.py`에 정의됨. 별도 정의 금지, import 방식 확인.

6. **`Column(Text)` import**: `from sqlalchemy import Column, Text` — `models.py`에 이미 있는지 확인 후 없으면 추가. 중복 import 금지.

---

## Dev Agent Record

### Agent Model Used

claude-sonnet-4-6

### Debug Log References

- `Message` 이름 충돌 발견: `models.py`에 이미 `class Message(SQLModel): message: str` 존재 → 채팅 메시지 모델을 `ChatMessage`로 명명 (`__tablename__ = "messages"` 유지)
- `Text` import 충돌 회피: `models.py`에서 `Text`가 `SaText`로 alias됨 → `Column(SaText(), ...)` 사용
- `from app.api.deps import CurrentUser, SessionDep` — 실제 코드베이스 패턴. 스토리 문서의 `get_current_user, get_db` 패턴과 다름
- 라우터 prefix는 `APIRouter(prefix="/chat-rooms")` 방식 (main.py include_router에 prefix 없음)
- `session: SessionDep` — 실제 파라미터명은 `db`가 아님

### Completion Notes List

- Alembic `008_chat_tables.py`: chat_rooms, chat_room_members, messages 테이블 생성 + idx_messages_room_id/created_at 인덱스
- `ChatRoom`, `ChatRoomMember`, `ChatMessage` SQLModel 모델 → `models.py` 추가 (기존 패턴 완전 준수)
- `chat.py` 4개 엔드포인트: POST /chat-rooms (201/200 구분), GET /chat-rooms (미읽음 수 포함), GET /{id}/messages (페이지네이션), PATCH /{id}/read
- 채팅방 중복 방지: 애플리케이션 레벨 중복 체크 (기존 방 → JSONResponse 200)
- 판매자 본인 채팅방 생성 시도 → 400 SELLER_CANNOT_CHAT
- 17개 신규 테스트, 105/105 전체 통과 (기존 88개 회귀 없음)

### File List

- backend/app/alembic/versions/008_chat_tables.py (NEW)
- backend/app/models.py (UPDATE — ChatRoom, ChatRoomMember, ChatMessage 모델 추가)
- backend/app/api/routes/chat.py (NEW)
- backend/app/api/main.py (UPDATE — chat 라우터 등록)
- backend/tests/api/routes/test_chat.py (NEW)
