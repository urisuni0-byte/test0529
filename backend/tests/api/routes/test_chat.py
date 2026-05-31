"""Tests for Story 4.1 — chat REST API endpoints."""
import uuid

from fastapi.testclient import TestClient
from sqlmodel import Session, select

from app import crud
from app.core import security
from app.core.config import settings
from app.models import ChatMessage, ChatRoom, ChatRoomMember, Product

BASE = settings.API_V1_STR


# ─── Helpers ──────────────────────────────────────────────────────────────────

def _make_user(db: Session, prefix: str = "user") -> crud.User:
    email = f"{prefix}_{uuid.uuid4().hex[:8]}@test.com"
    return crud.upsert_google_user(
        session=db, email=email, google_sub=uuid.uuid4().hex, name=prefix.capitalize()
    )


def _make_auth_headers(user: crud.User) -> dict[str, str]:
    token = security.create_access_token(str(user.id), role=user.role)
    return {"Authorization": f"Bearer {token}"}


def _get_dong_id(client: TestClient) -> int:
    resp = client.get(f"{BASE}/neighborhoods")
    dongs = [n for n in resp.json()["items"] if n["level"] == "dong"]
    return dongs[0]["id"]


def _create_product(
    db: Session,
    seller_id: uuid.UUID,
    neighborhood_id: int,
    *,
    title: str = "테스트 상품",
) -> Product:
    product = Product(
        seller_id=seller_id,
        title=title,
        price=10000,
        category="의류",
        status="SALE",
        neighborhood_id=neighborhood_id,
        image_urls=["https://example.com/img.jpg"],
    )
    db.add(product)
    db.commit()
    db.refresh(product)
    return product


def _create_chat_room(db: Session, product: Product, buyer_id: uuid.UUID) -> ChatRoom:
    room = ChatRoom(product_id=product.id)
    db.add(room)
    db.flush()
    db.add(ChatRoomMember(chat_room_id=room.id, user_id=buyer_id))
    db.add(ChatRoomMember(chat_room_id=room.id, user_id=product.seller_id))
    db.commit()
    db.refresh(room)
    return room


def _add_message(
    db: Session,
    room_id: uuid.UUID,
    sender_id: uuid.UUID,
    content: str = "안녕하세요!",
) -> ChatMessage:
    msg = ChatMessage(room_id=room_id, sender_id=sender_id, content=content)
    db.add(msg)
    db.commit()
    db.refresh(msg)
    return msg


# ─── POST /chat-rooms ─────────────────────────────────────────────────────────

class TestCreateChatRoom:
    def test_create_room_201_with_members(self, client: TestClient, db: Session) -> None:
        """신규 채팅방 생성 → 201, chat_room_members 2개 생성."""
        seller = _make_user(db, "seller")
        buyer = _make_user(db, "buyer")
        dong_id = _get_dong_id(client)
        product = _create_product(db, seller.id, dong_id)

        resp = client.post(
            f"{BASE}/chat-rooms",
            json={"product_id": str(product.id)},
            headers=_make_auth_headers(buyer),
        )

        assert resp.status_code == 201
        data = resp.json()
        assert data["is_new"] is True
        assert data["product_id"] == str(product.id)

        members = db.exec(
            select(ChatRoomMember).where(
                ChatRoomMember.chat_room_id == uuid.UUID(data["id"])
            )
        ).all()
        assert len(members) == 2
        member_ids = {m.user_id for m in members}
        assert buyer.id in member_ids
        assert seller.id in member_ids

    def test_create_room_idempotent_200(self, client: TestClient, db: Session) -> None:
        """동일 상품·구매자로 두 번 POST → 두 번째는 200, 방 중복 생성 없음."""
        seller = _make_user(db, "seller2")
        buyer = _make_user(db, "buyer2")
        dong_id = _get_dong_id(client)
        product = _create_product(db, seller.id, dong_id, title="중복방 테스트")

        resp1 = client.post(
            f"{BASE}/chat-rooms",
            json={"product_id": str(product.id)},
            headers=_make_auth_headers(buyer),
        )
        assert resp1.status_code == 201
        room_id_1 = resp1.json()["id"]

        resp2 = client.post(
            f"{BASE}/chat-rooms",
            json={"product_id": str(product.id)},
            headers=_make_auth_headers(buyer),
        )
        assert resp2.status_code == 200
        assert resp2.json()["is_new"] is False
        assert resp2.json()["id"] == room_id_1  # 같은 방 반환

        # DB에 채팅방이 1개만 존재하는지 확인
        rooms = db.exec(
            select(ChatRoom).where(ChatRoom.product_id == product.id)
        ).all()
        assert len(rooms) == 1

    def test_seller_cannot_create_own_room(self, client: TestClient, db: Session) -> None:
        """판매자가 본인 상품 채팅방 생성 시도 → 400 SELLER_CANNOT_CHAT."""
        seller = _make_user(db, "seller3")
        dong_id = _get_dong_id(client)
        product = _create_product(db, seller.id, dong_id, title="판매자 채팅 테스트")

        resp = client.post(
            f"{BASE}/chat-rooms",
            json={"product_id": str(product.id)},
            headers=_make_auth_headers(seller),
        )

        assert resp.status_code == 400
        assert resp.json()["code"] == "SELLER_CANNOT_CHAT"

    def test_create_room_requires_auth(self, client: TestClient) -> None:
        """미인증 → 401."""
        resp = client.post(
            f"{BASE}/chat-rooms",
            json={"product_id": str(uuid.uuid4())},
        )
        assert resp.status_code == 401

    def test_create_room_nonexistent_product_404(
        self, client: TestClient, db: Session
    ) -> None:
        """존재하지 않는 상품 → 404 PRODUCT_NOT_FOUND."""
        buyer = _make_user(db, "buyer_404")
        resp = client.post(
            f"{BASE}/chat-rooms",
            json={"product_id": str(uuid.uuid4())},
            headers=_make_auth_headers(buyer),
        )
        assert resp.status_code == 404
        assert resp.json()["code"] == "PRODUCT_NOT_FOUND"


# ─── GET /chat-rooms ──────────────────────────────────────────────────────────

class TestListChatRooms:
    def test_list_rooms_only_own(self, client: TestClient, db: Session) -> None:
        """user_a 채팅방은 user_b 목록에 미포함."""
        seller = _make_user(db, "list_seller")
        buyer_a = _make_user(db, "list_buyer_a")
        buyer_b = _make_user(db, "list_buyer_b")
        dong_id = _get_dong_id(client)
        product = _create_product(db, seller.id, dong_id, title="목록 테스트 상품")

        _create_chat_room(db, product, buyer_a.id)

        # buyer_a 목록에는 1개
        resp_a = client.get(f"{BASE}/chat-rooms", headers=_make_auth_headers(buyer_a))
        assert resp_a.status_code == 200
        assert len(resp_a.json()) == 1

        # buyer_b 목록에는 0개
        resp_b = client.get(f"{BASE}/chat-rooms", headers=_make_auth_headers(buyer_b))
        assert resp_b.status_code == 200
        assert len(resp_b.json()) == 0

    def test_list_rooms_contains_product_info(self, client: TestClient, db: Session) -> None:
        """채팅방 목록에 상품 정보 포함."""
        seller = _make_user(db, "info_seller")
        buyer = _make_user(db, "info_buyer")
        dong_id = _get_dong_id(client)
        product = _create_product(db, seller.id, dong_id, title="정보 확인 상품")

        _create_chat_room(db, product, buyer.id)

        resp = client.get(f"{BASE}/chat-rooms", headers=_make_auth_headers(buyer))
        assert resp.status_code == 200
        items = resp.json()
        assert len(items) >= 1
        room = next(r for r in items if r["product"]["id"] == str(product.id))
        assert room["product"]["title"] == "정보 확인 상품"
        assert room["product"]["price"] == 10000
        assert room["product"]["status"] == "SALE"
        assert "unread_count" in room

    def test_list_rooms_unread_count(self, client: TestClient, db: Session) -> None:
        """미읽음 수가 정확히 계산된다."""
        seller = _make_user(db, "unread_seller")
        buyer = _make_user(db, "unread_buyer")
        dong_id = _get_dong_id(client)
        product = _create_product(db, seller.id, dong_id, title="미읽음 테스트")
        room = _create_chat_room(db, product, buyer.id)

        # 판매자가 2개 메시지 전송
        _add_message(db, room.id, seller.id, "첫 번째 메시지")
        _add_message(db, room.id, seller.id, "두 번째 메시지")

        # buyer 목록에서 unread_count == 2
        resp = client.get(f"{BASE}/chat-rooms", headers=_make_auth_headers(buyer))
        assert resp.status_code == 200
        room_data = next(r for r in resp.json() if r["id"] == str(room.id))
        assert room_data["unread_count"] == 2

    def test_list_requires_auth(self, client: TestClient) -> None:
        """미인증 → 401."""
        resp = client.get(f"{BASE}/chat-rooms")
        assert resp.status_code == 401


# ─── GET /chat-rooms/{room_id}/messages ───────────────────────────────────────

class TestGetMessages:
    def test_get_messages_pagination(self, client: TestClient, db: Session) -> None:
        """60개 메시지 → page=1, limit=50 → items 50개, total=60."""
        seller = _make_user(db, "pag_seller")
        buyer = _make_user(db, "pag_buyer")
        dong_id = _get_dong_id(client)
        product = _create_product(db, seller.id, dong_id, title="페이지네이션 테스트")
        room = _create_chat_room(db, product, buyer.id)

        for i in range(60):
            _add_message(db, room.id, buyer.id, f"메시지 {i}")

        resp = client.get(
            f"{BASE}/chat-rooms/{room.id}/messages",
            params={"page": 1, "limit": 50},
            headers=_make_auth_headers(buyer),
        )
        assert resp.status_code == 200
        data = resp.json()
        assert data["total"] == 60
        assert len(data["items"]) == 50
        assert data["page"] == 1
        assert data["limit"] == 50

    def test_get_messages_page2(self, client: TestClient, db: Session) -> None:
        """page=2, limit=50 → 10개 반환."""
        seller = _make_user(db, "page2_seller")
        buyer = _make_user(db, "page2_buyer")
        dong_id = _get_dong_id(client)
        product = _create_product(db, seller.id, dong_id, title="2페이지 테스트")
        room = _create_chat_room(db, product, buyer.id)

        for i in range(60):
            _add_message(db, room.id, buyer.id, f"msg {i}")

        resp = client.get(
            f"{BASE}/chat-rooms/{room.id}/messages",
            params={"page": 2, "limit": 50},
            headers=_make_auth_headers(buyer),
        )
        assert resp.status_code == 200
        data = resp.json()
        assert len(data["items"]) == 10

    def test_get_messages_contains_sender_info(self, client: TestClient, db: Session) -> None:
        """메시지에 sender_id, sender_nickname, content, created_at 포함."""
        seller = _make_user(db, "sender_seller")
        buyer = _make_user(db, "sender_buyer")
        dong_id = _get_dong_id(client)
        product = _create_product(db, seller.id, dong_id, title="발신자 정보 테스트")
        room = _create_chat_room(db, product, buyer.id)
        _add_message(db, room.id, seller.id, "테스트 메시지")

        resp = client.get(
            f"{BASE}/chat-rooms/{room.id}/messages",
            headers=_make_auth_headers(buyer),
        )
        assert resp.status_code == 200
        items = resp.json()["items"]
        assert len(items) >= 1
        msg = items[0]
        assert "sender_id" in msg
        assert "sender_nickname" in msg
        assert "content" in msg
        assert "created_at" in msg

    def test_get_messages_forbids_non_member(self, client: TestClient, db: Session) -> None:
        """비멤버 → 403 FORBIDDEN."""
        seller = _make_user(db, "forbid_seller")
        buyer = _make_user(db, "forbid_buyer")
        non_member = _make_user(db, "non_member")
        dong_id = _get_dong_id(client)
        product = _create_product(db, seller.id, dong_id, title="비멤버 테스트")
        room = _create_chat_room(db, product, buyer.id)

        resp = client.get(
            f"{BASE}/chat-rooms/{room.id}/messages",
            headers=_make_auth_headers(non_member),
        )
        assert resp.status_code == 403
        assert resp.json()["code"] == "FORBIDDEN"

    def test_get_messages_requires_auth(self, client: TestClient, db: Session) -> None:
        """미인증 → 401."""
        seller = _make_user(db, "auth_seller")
        buyer = _make_user(db, "auth_buyer")
        dong_id = _get_dong_id(client)
        product = _create_product(db, seller.id, dong_id)
        room = _create_chat_room(db, product, buyer.id)

        resp = client.get(f"{BASE}/chat-rooms/{room.id}/messages")
        assert resp.status_code == 401


# ─── PATCH /chat-rooms/{room_id}/read ─────────────────────────────────────────

class TestMarkAsRead:
    def test_read_updates_last_read_at(self, client: TestClient, db: Session) -> None:
        """PATCH /read → last_read_at이 갱신되고 미읽음 수가 0으로 감소."""
        seller = _make_user(db, "read_seller")
        buyer = _make_user(db, "read_buyer")
        dong_id = _get_dong_id(client)
        product = _create_product(db, seller.id, dong_id, title="읽음 처리 테스트")
        room = _create_chat_room(db, product, buyer.id)
        _add_message(db, room.id, seller.id, "읽지 않은 메시지")

        # 읽기 전 unread_count == 1
        list_resp = client.get(f"{BASE}/chat-rooms", headers=_make_auth_headers(buyer))
        room_before = next(r for r in list_resp.json() if r["id"] == str(room.id))
        assert room_before["unread_count"] == 1

        # 읽음 처리
        resp = client.patch(
            f"{BASE}/chat-rooms/{room.id}/read",
            headers=_make_auth_headers(buyer),
        )
        assert resp.status_code == 200
        assert "last_read_at" in resp.json()

        # DB에서 last_read_at 갱신 확인
        db.expire_all()
        member = db.exec(
            select(ChatRoomMember).where(
                ChatRoomMember.chat_room_id == room.id,
                ChatRoomMember.user_id == buyer.id,
            )
        ).first()
        assert member is not None
        assert member.last_read_at is not None

        # 읽기 후 unread_count == 0
        list_resp2 = client.get(f"{BASE}/chat-rooms", headers=_make_auth_headers(buyer))
        room_after = next(r for r in list_resp2.json() if r["id"] == str(room.id))
        assert room_after["unread_count"] == 0

    def test_read_forbids_non_member(self, client: TestClient, db: Session) -> None:
        """비멤버가 읽음 처리 시도 → 403 FORBIDDEN."""
        seller = _make_user(db, "read_forbid_seller")
        buyer = _make_user(db, "read_forbid_buyer")
        non_member = _make_user(db, "read_non_member")
        dong_id = _get_dong_id(client)
        product = _create_product(db, seller.id, dong_id, title="비멤버 읽음 테스트")
        room = _create_chat_room(db, product, buyer.id)

        resp = client.patch(
            f"{BASE}/chat-rooms/{room.id}/read",
            headers=_make_auth_headers(non_member),
        )
        assert resp.status_code == 403
        assert resp.json()["code"] == "FORBIDDEN"

    def test_read_requires_auth(self, client: TestClient, db: Session) -> None:
        """미인증 → 401."""
        seller = _make_user(db, "read_auth_seller")
        buyer = _make_user(db, "read_auth_buyer")
        dong_id = _get_dong_id(client)
        product = _create_product(db, seller.id, dong_id)
        room = _create_chat_room(db, product, buyer.id)

        resp = client.patch(f"{BASE}/chat-rooms/{room.id}/read")
        assert resp.status_code == 401
