"""Tests for Story 4.2 — WebSocket 채팅 엔드포인트."""
import uuid

import pytest
from fastapi.testclient import TestClient
from sqlmodel import Session, select
from starlette.websockets import WebSocketDisconnect

from app import crud
from app.core import security
from app.models import ChatMessage, ChatRoom, ChatRoomMember, Product
from app.services.websocket import manager

WS_BASE = "/ws/chat"


# ─── Helpers ──────────────────────────────────────────────────────────────────

def _make_user(db: Session, prefix: str = "wsuser") -> crud.User:
    email = f"{prefix}_{uuid.uuid4().hex[:8]}@test.com"
    return crud.upsert_google_user(
        session=db, email=email, google_sub=uuid.uuid4().hex, name=prefix.capitalize()
    )


def _make_token(user: crud.User) -> str:
    return security.create_access_token(str(user.id), role=user.role)


def _get_dong_id(client: TestClient) -> int:
    from app.core.config import settings
    resp = client.get(f"{settings.API_V1_STR}/neighborhoods")
    dongs = [n for n in resp.json()["items"] if n["level"] == "dong"]
    return dongs[0]["id"]


def _create_product(db: Session, seller_id: uuid.UUID, neighborhood_id: int) -> Product:
    product = Product(
        seller_id=seller_id,
        title="WS테스트상품",
        price=10000,
        category="의류",
        status="SALE",
        neighborhood_id=neighborhood_id,
        image_urls=[],
    )
    db.add(product)
    db.commit()
    db.refresh(product)
    return product


def _create_room(db: Session, product: Product, buyer_id: uuid.UUID) -> ChatRoom:
    room = ChatRoom(product_id=product.id)
    db.add(room)
    db.flush()
    db.add(ChatRoomMember(chat_room_id=room.id, user_id=buyer_id))
    db.add(ChatRoomMember(chat_room_id=room.id, user_id=product.seller_id))
    db.commit()
    db.refresh(room)
    return room


# ─── ConnectionManager 단위 테스트 ────────────────────────────────────────────

class TestConnectionManager:
    def test_connect_increments_count(self) -> None:
        """connect 후 connection_count가 1 증가한다."""
        import asyncio
        from unittest.mock import AsyncMock, MagicMock

        cm = manager.__class__()  # 새 인스턴스 (싱글톤 오염 방지)
        room_id = uuid.uuid4()
        ws = MagicMock()
        ws.accept = AsyncMock()

        asyncio.run(cm.connect(room_id, ws))
        assert cm.connection_count(room_id) == 1

    def test_disconnect_removes_connection(self) -> None:
        """disconnect 후 connection_count가 0으로 감소한다."""
        import asyncio
        from unittest.mock import AsyncMock, MagicMock

        cm = manager.__class__()
        room_id = uuid.uuid4()
        ws = MagicMock()
        ws.accept = AsyncMock()

        asyncio.run(cm.connect(room_id, ws))
        cm.disconnect(room_id, ws)
        assert cm.connection_count(room_id) == 0
        assert cm.room_count == 0  # 빈 room 정리됨

    def test_broadcast_skips_failed_connections(self) -> None:
        """broadcast 중 실패한 연결은 제거하고 나머지에 계속 전송한다."""
        import asyncio
        from unittest.mock import AsyncMock, MagicMock

        cm = manager.__class__()
        room_id = uuid.uuid4()

        ws_ok = MagicMock()
        ws_ok.accept = AsyncMock()
        ws_ok.send_json = AsyncMock()

        ws_fail = MagicMock()
        ws_fail.accept = AsyncMock()
        ws_fail.send_json = AsyncMock(side_effect=RuntimeError("disconnected"))

        async def _run() -> None:
            await cm.connect(room_id, ws_ok)
            await cm.connect(room_id, ws_fail)
            await cm.broadcast_to_room(room_id, {"type": "test"})

        asyncio.run(_run())

        ws_ok.send_json.assert_called_once_with({"type": "test"})
        # 실패한 ws_fail은 레지스트리에서 제거됨
        assert cm.connection_count(room_id) == 1


# ─── WebSocket 연결 테스트 ────────────────────────────────────────────────────

class TestWebSocketConnect:
    def test_ws_connect_sends_connected_message(
        self, client: TestClient, db: Session
    ) -> None:
        """정상 연결 → connected 메시지 수신."""
        seller = _make_user(db, "ws_seller_conn")
        buyer = _make_user(db, "ws_buyer_conn")
        dong_id = _get_dong_id(client)
        product = _create_product(db, seller.id, dong_id)
        room = _create_room(db, product, buyer.id)
        token = _make_token(buyer)

        with client.websocket_connect(f"{WS_BASE}/{room.id}?token={token}") as ws:
            data = ws.receive_json()
            assert data["type"] == "connected"
            assert data["room_id"] == str(room.id)

    def test_ws_invalid_token_closes_4001(
        self, client: TestClient, db: Session
    ) -> None:
        """유효하지 않은 토큰 → WebSocketDisconnect code=4001."""
        seller = _make_user(db, "ws_seller_badtok")
        buyer = _make_user(db, "ws_buyer_badtok")
        dong_id = _get_dong_id(client)
        product = _create_product(db, seller.id, dong_id)
        room = _create_room(db, product, buyer.id)

        with pytest.raises(WebSocketDisconnect) as exc_info:
            with client.websocket_connect(
                f"{WS_BASE}/{room.id}?token=invalid_token_value"
            ) as ws:
                ws.receive_json()
        assert exc_info.value.code == 4001

    def test_ws_no_token_closes_4001(
        self, client: TestClient, db: Session
    ) -> None:
        """토큰 없음 → WebSocketDisconnect code=4001."""
        seller = _make_user(db, "ws_seller_notok")
        buyer = _make_user(db, "ws_buyer_notok")
        dong_id = _get_dong_id(client)
        product = _create_product(db, seller.id, dong_id)
        room = _create_room(db, product, buyer.id)

        with pytest.raises(WebSocketDisconnect) as exc_info:
            with client.websocket_connect(f"{WS_BASE}/{room.id}") as ws:
                ws.receive_json()
        assert exc_info.value.code == 4001

    def test_ws_non_member_closes_4003(
        self, client: TestClient, db: Session
    ) -> None:
        """채팅방 비멤버 → WebSocketDisconnect code=4003."""
        seller = _make_user(db, "ws_seller_nonmem")
        buyer = _make_user(db, "ws_buyer_nonmem")
        non_member = _make_user(db, "ws_nonmember")
        dong_id = _get_dong_id(client)
        product = _create_product(db, seller.id, dong_id)
        room = _create_room(db, product, buyer.id)
        token = _make_token(non_member)

        with pytest.raises(WebSocketDisconnect) as exc_info:
            with client.websocket_connect(f"{WS_BASE}/{room.id}?token={token}") as ws:
                ws.receive_json()
        assert exc_info.value.code == 4003


# ─── 메시지 전송 테스트 ───────────────────────────────────────────────────────

class TestWebSocketMessages:
    def test_ws_message_saved_to_db(self, client: TestClient, db: Session) -> None:
        """메시지 전송 → messages 테이블에 저장된다."""
        seller = _make_user(db, "ws_seller_save")
        buyer = _make_user(db, "ws_buyer_save")
        dong_id = _get_dong_id(client)
        product = _create_product(db, seller.id, dong_id)
        room = _create_room(db, product, buyer.id)
        token = _make_token(buyer)

        with client.websocket_connect(f"{WS_BASE}/{room.id}?token={token}") as ws:
            ws.receive_json()  # connected
            ws.send_json({"type": "message", "content": "저장 테스트"})
            broadcast = ws.receive_json()
            assert broadcast["type"] == "message"
            assert broadcast["content"] == "저장 테스트"

        # WebSocket 핸들러가 별도 Session으로 commit → expire_all() 후 확인
        db.expire_all()
        msgs = db.exec(
            select(ChatMessage).where(ChatMessage.room_id == room.id)
        ).all()
        assert len(msgs) == 1
        assert msgs[0].content == "저장 테스트"
        assert msgs[0].sender_id == buyer.id

    def test_ws_message_has_correct_broadcast_format(
        self, client: TestClient, db: Session
    ) -> None:
        """브로드캐스트 메시지 형식: id, room_id, sender_id, sender_nickname, content, created_at."""
        seller = _make_user(db, "ws_seller_fmt")
        buyer = _make_user(db, "ws_buyer_fmt")
        dong_id = _get_dong_id(client)
        product = _create_product(db, seller.id, dong_id)
        room = _create_room(db, product, buyer.id)
        token = _make_token(buyer)

        with client.websocket_connect(f"{WS_BASE}/{room.id}?token={token}") as ws:
            ws.receive_json()  # connected
            ws.send_json({"type": "message", "content": "형식 확인"})
            msg = ws.receive_json()

        assert msg["type"] == "message"
        assert "id" in msg
        assert msg["room_id"] == str(room.id)
        assert msg["sender_id"] == str(buyer.id)
        assert "sender_nickname" in msg
        assert msg["content"] == "형식 확인"
        assert "created_at" in msg

    def test_ws_empty_message_ignored(self, client: TestClient, db: Session) -> None:
        """빈 content 메시지 → 저장하지 않고 무시된다."""
        seller = _make_user(db, "ws_seller_empty")
        buyer = _make_user(db, "ws_buyer_empty")
        dong_id = _get_dong_id(client)
        product = _create_product(db, seller.id, dong_id)
        room = _create_room(db, product, buyer.id)
        token = _make_token(buyer)

        with client.websocket_connect(f"{WS_BASE}/{room.id}?token={token}") as ws:
            ws.receive_json()  # connected
            ws.send_json({"type": "message", "content": ""})
            ws.send_json({"type": "message", "content": "   "})  # 공백만
            # 무시됐으면 다음 유효한 메시지만 broadcast됨
            ws.send_json({"type": "message", "content": "유효한 메시지"})
            msg = ws.receive_json()
            assert msg["content"] == "유효한 메시지"

        db.expire_all()
        msgs = db.exec(
            select(ChatMessage).where(ChatMessage.room_id == room.id)
        ).all()
        assert len(msgs) == 1  # 유효한 메시지 1개만 저장

    def test_ws_unknown_type_ignored(self, client: TestClient, db: Session) -> None:
        """알 수 없는 type → 무시되고 다음 유효 메시지 처리."""
        seller = _make_user(db, "ws_seller_unk")
        buyer = _make_user(db, "ws_buyer_unk")
        dong_id = _get_dong_id(client)
        product = _create_product(db, seller.id, dong_id)
        room = _create_room(db, product, buyer.id)
        token = _make_token(buyer)

        with client.websocket_connect(f"{WS_BASE}/{room.id}?token={token}") as ws:
            ws.receive_json()  # connected
            ws.send_json({"type": "ping"})  # 알 수 없는 type
            ws.send_json({"type": "message", "content": "타입 무시 후 메시지"})
            msg = ws.receive_json()
            assert msg["content"] == "타입 무시 후 메시지"

    def test_ws_message_broadcast_to_all_members(
        self, client: TestClient, db: Session
    ) -> None:
        """판매자·구매자 모두 연결 시 broadcast → 둘 다 수신한다."""
        seller = _make_user(db, "ws_seller_bc")
        buyer = _make_user(db, "ws_buyer_bc")
        dong_id = _get_dong_id(client)
        product = _create_product(db, seller.id, dong_id)
        room = _create_room(db, product, buyer.id)

        buyer_token = _make_token(buyer)
        seller_token = _make_token(seller)

        with client.websocket_connect(
            f"{WS_BASE}/{room.id}?token={buyer_token}"
        ) as ws_buyer:
            ws_buyer.receive_json()  # connected

            with client.websocket_connect(
                f"{WS_BASE}/{room.id}?token={seller_token}"
            ) as ws_seller:
                ws_seller.receive_json()  # connected

                # 구매자가 메시지 전송
                ws_buyer.send_json({"type": "message", "content": "broadcast 테스트"})

                # 구매자와 판매자 모두 수신
                msg_buyer = ws_buyer.receive_json()
                msg_seller = ws_seller.receive_json()

        assert msg_buyer["type"] == "message"
        assert msg_buyer["content"] == "broadcast 테스트"
        assert msg_seller["type"] == "message"
        assert msg_seller["content"] == "broadcast 테스트"
        assert msg_buyer["id"] == msg_seller["id"]  # 동일 메시지 ID


# ─── 연결 해제 테스트 ─────────────────────────────────────────────────────────

class TestWebSocketDisconnect:
    def test_ws_disconnect_removes_from_registry(
        self, client: TestClient, db: Session
    ) -> None:
        """연결 해제 시 ConnectionManager 레지스트리에서 제거된다."""
        seller = _make_user(db, "ws_seller_disc")
        buyer = _make_user(db, "ws_buyer_disc")
        dong_id = _get_dong_id(client)
        product = _create_product(db, seller.id, dong_id)
        room = _create_room(db, product, buyer.id)
        token = _make_token(buyer)

        # 연결 전
        count_before = manager.connection_count(room.id)

        with client.websocket_connect(f"{WS_BASE}/{room.id}?token={token}") as ws:
            ws.receive_json()  # connected
            # 연결 중에는 레지스트리에 등록됨
            assert manager.connection_count(room.id) == count_before + 1

        # 컨텍스트 매니저 종료 → disconnect → 레지스트리 정리
        assert manager.connection_count(room.id) == count_before
