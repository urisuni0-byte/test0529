"""Story 4.2 — ConnectionManager: 채팅방별 WebSocket 연결 레지스트리."""
import uuid

from fastapi import WebSocket


class ConnectionManager:
    """채팅방별 활성 WebSocket 연결을 관리한다."""

    def __init__(self) -> None:
        # room_id → 연결된 WebSocket 목록
        self._rooms: dict[uuid.UUID, list[WebSocket]] = {}

    async def connect(self, room_id: uuid.UUID, websocket: WebSocket) -> None:
        """WebSocket을 accept하고 레지스트리에 등록한다."""
        await websocket.accept()
        self._rooms.setdefault(room_id, []).append(websocket)

    def disconnect(self, room_id: uuid.UUID, websocket: WebSocket) -> None:
        """연결을 레지스트리에서 제거한다. 빈 room은 정리한다."""
        connections = self._rooms.get(room_id, [])
        if websocket in connections:
            connections.remove(websocket)
        if not connections:
            self._rooms.pop(room_id, None)

    async def broadcast_to_room(
        self, room_id: uuid.UUID, message: dict
    ) -> None:
        """room의 모든 클라이언트에게 메시지를 전송한다.

        개별 전송 실패 시 해당 연결을 제거하고 계속 진행한다.
        disconnect() 호출 대신 직접 정리 — concurrent coroutine 간 이중 pop 방지.
        """
        connections = self._rooms.get(room_id, [])
        failed: list[WebSocket] = []
        for connection in list(connections):  # 스냅샷으로 반복
            try:
                await connection.send_json(message)
            except Exception:
                failed.append(connection)
        for ws in failed:
            if ws in connections:
                connections.remove(ws)
        if room_id in self._rooms and not self._rooms[room_id]:
            self._rooms.pop(room_id, None)

    @property
    def room_count(self) -> int:
        """테스트용: 활성 room 수."""
        return len(self._rooms)

    def connection_count(self, room_id: uuid.UUID) -> int:
        """테스트용: 특정 room의 활성 연결 수."""
        return len(self._rooms.get(room_id, []))


# 프로세스 전역 싱글톤 — MVP 단일 서버 가정
manager = ConnectionManager()
