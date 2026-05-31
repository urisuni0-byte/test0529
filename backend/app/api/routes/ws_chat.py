"""Story 4.2 + 4.5 — WebSocket 채팅 엔드포인트 (FCM 알림 포함)."""
import asyncio
import uuid

import jwt
from fastapi import APIRouter, Query, WebSocket, WebSocketDisconnect
from jwt.exceptions import InvalidTokenError
from pydantic import ValidationError
from sqlmodel import Session, select

from app.core import security
from app.core.config import settings
from app.core.db import engine
from app.models import ChatMessage, ChatRoomMember, TokenPayload, User
from app.services.fcm import send_chat_notification
from app.services.websocket import manager

ws_router = APIRouter()

# create_task 반환 Task를 강참조로 유지 — GC에 의한 조기 수거 방지
_background_tasks: set[asyncio.Task] = set()



def _authenticate_ws(token: str | None) -> uuid.UUID | None:
    """JWT 토큰을 검증하고 user_id를 반환한다. 실패 시 None."""
    if not token:
        return None
    try:
        payload = jwt.decode(
            token, settings.SECRET_KEY, algorithms=[security.ALGORITHM]
        )
        token_data = TokenPayload(**payload)
        if not token_data.sub:
            return None
        return uuid.UUID(token_data.sub)
    except (InvalidTokenError, ValidationError, ValueError, AttributeError):
        return None


@ws_router.websocket("/ws/chat/{room_id}")
async def websocket_chat(
    websocket: WebSocket,
    room_id: uuid.UUID,
    token: str | None = Query(default=None),
) -> None:
    """채팅방 WebSocket 핸들러.

    인증: ?token={jwt} 쿼리 파라미터
    실패 close codes: 4001 (인증), 4003 (멤버십)
    """
    # ─── 1. JWT 인증 ──────────────────────────────────────────────────────────
    user_id = _authenticate_ws(token)
    if not user_id:
        await websocket.close(code=4001)
        return

    # ─── 2. 사용자 및 멤버십 조회 ─────────────────────────────────────────────
    with Session(engine) as session:
        user = session.get(User, user_id)
        if not user or not user.is_active:
            await websocket.close(code=4001)
            return

        member = session.exec(
            select(ChatRoomMember).where(
                ChatRoomMember.chat_room_id == room_id,
                ChatRoomMember.user_id == user_id,
            )
        ).first()

    if not member:
        await websocket.close(code=4003)
        return

    # ─── 3. 연결 등록 & 연결 확인 메시지 ────────────────────────────────────
    await manager.connect(room_id, websocket)
    try:
        await websocket.send_json({"type": "connected", "room_id": str(room_id)})

        # ─── 4. 메시지 수신 루프 ──────────────────────────────────────────────
        while True:
            data = await websocket.receive_json()

            if data.get("type") != "message":
                continue  # 알 수 없는 type 무시

            content: str = (data.get("content") or "").strip()
            if not content:
                continue  # 빈 메시지 무시

            # ─── 5. DB 저장 ───────────────────────────────────────────────────
            with Session(engine) as session:
                msg = ChatMessage(
                    room_id=room_id,
                    sender_id=user_id,
                    content=content,
                )
                session.add(msg)
                session.commit()
                session.refresh(msg)

                sender = session.get(User, user_id)
                sender_nickname = (
                    sender.nickname or "알 수 없음" if sender else "알 수 없음"
                )

            # ─── 6. 브로드캐스트 ──────────────────────────────────────────────
            await manager.broadcast_to_room(
                room_id,
                {
                    "type": "message",
                    "id": str(msg.id),
                    "room_id": str(msg.room_id),
                    "sender_id": str(msg.sender_id),
                    "sender_nickname": sender_nickname,
                    "content": msg.content,
                    "created_at": msg.created_at.isoformat(),
                },
            )

            # ─── 7. FCM 알림 (수신자가 오프라인이면) ──────────────────────────
            # connection_count <= 1: 발신자만 연결됨 = 수신자 오프라인 추정.
            # 주의: ConnectionManager는 프로세스 로컬 메모리 — 단일 uvicorn
            # 워커 환경 전제. 멀티 워커 시 다른 워커의 연결을 알 수 없어
            # 수신자가 온라인이어도 FCM이 발송될 수 있음. (MVP 허용 한계)
            if manager.connection_count(room_id) <= 1:
                with Session(engine) as session:
                    other_member = session.exec(
                        select(ChatRoomMember).where(
                            ChatRoomMember.chat_room_id == room_id,
                            ChatRoomMember.user_id != user_id,
                        )
                    ).first()
                    if other_member:
                        receiver = session.get(User, other_member.user_id)
                        if receiver and receiver.fcm_token:
                            task = asyncio.create_task(
                                send_chat_notification(
                                    fcm_token=receiver.fcm_token,
                                    sender_nickname=sender_nickname,
                                    message_preview=content,
                                    room_id=str(room_id),
                                )
                            )
                            _background_tasks.add(task)
                            task.add_done_callback(_background_tasks.discard)

    except WebSocketDisconnect:
        manager.disconnect(room_id, websocket)
