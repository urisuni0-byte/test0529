---
baseline_commit: NO_VCS
---

# Story 4.2 — FastAPI WebSocket 서버 & ConnectionManager

**Status:** review

## Story

As a developer,
I want to implement the WebSocket server with a ConnectionManager for real-time chat,
So that messages are delivered to connected clients within 2 seconds.

## Acceptance Criteria

**Given** 인증된 사용자가 WebSocket에 연결할 때
**When** `ws://host/ws/chat/{room_id}?token={jwt}`로 연결하면
**Then** ConnectionManager가 해당 채팅방의 연결 레지스트리에 등록한다
**And** `{"type": "connected", "room_id": "<uuid>"}` 메시지를 클라이언트에 전송한다
**And** 참여하지 않은 채팅방 접근 시 WebSocket을 close(code=4003)하고 연결을 종료한다

**Given** 유효하지 않은 JWT 토큰으로 연결할 때
**When** `token` 파라미터가 없거나 검증 실패하면
**Then** WebSocket을 close(code=4001)하고 연결을 종료한다

**Given** 클라이언트가 `{"type": "message", "content": "안녕하세요"}` 메시지를 전송할 때
**When** WebSocket 핸들러가 수신하면
**Then** `messages` 테이블에 저장한다
**And** 같은 채팅방에 연결된 모든 클라이언트에게 브로드캐스트한다
**And** 브로드캐스트 형식은 `{"type": "message", "id": "<uuid>", "room_id": "<uuid>", "sender_id": "<uuid>", "sender_nickname": "...", "content": "...", "created_at": "ISO8601"}`이다

**Given** 빈 content를 가진 메시지를 전송할 때
**When** WebSocket 핸들러가 수신하면
**Then** 저장하지 않고 무시한다 (strip 후 빈 문자열 포함)

**Given** WebSocket 연결이 끊어질 때
**When** 클라이언트가 연결을 종료하거나 네트워크 오류가 발생하면
**Then** ConnectionManager가 해당 연결을 레지스트리에서 제거한다
**And** 다른 클라이언트의 연결에 영향을 주지 않는다

## Tasks / Subtasks

- [x] Task 1: `backend/app/services/websocket.py` 신규 생성 — ConnectionManager (AC: 1, 2, 3, 4, 5)
  - [x] `ConnectionManager` 클래스: `_rooms: dict[uuid.UUID, list[WebSocket]]`
  - [x] `async connect(room_id, websocket)` — accept + 레지스트리 등록
  - [x] `disconnect(room_id, websocket)` — 레지스트리에서 제거, 빈 room 정리
  - [x] `async broadcast_to_room(room_id, message)` — 실패한 연결은 제거하고 계속
  - [x] 모듈 레벨 싱글톤: `manager = ConnectionManager()`

- [x] Task 2: `backend/app/api/routes/ws_chat.py` 신규 생성 — WebSocket 엔드포인트 (AC: 1~5)
  - [x] `ws_router = APIRouter()`로 라우터 생성
  - [x] `@ws_router.websocket("/ws/chat/{room_id}")` 엔드포인트
  - [x] `token: str | None = Query(default=None)` — 쿼리 파라미터 JWT
  - [x] 토큰 검증: `jwt.decode` + TokenPayload 패턴 (security.py/deps.py와 동일)
  - [x] 멤버십 검증: `ChatRoomMember` 테이블 조회
  - [x] 연결 루프: `receive_json` → type 체크 → 저장 → broadcast
  - [x] `WebSocketDisconnect` 예외로 정상 종료 처리

- [x] Task 3: `backend/app/main.py` 수정 — WebSocket 라우터 등록 (AC: 1)
  - [x] `from app.api.routes.ws_chat import ws_router` import 추가
  - [x] `app.include_router(ws_router)` — `/api/v1/` prefix 없이 루트 수준 등록

- [x] Task 4: 테스트 추가 (AC: 1~5)
  - [x] `backend/tests/api/test_websocket.py` 신규 생성 (13개 테스트)
  - [x] test_ws_connect_sends_connected_message
  - [x] test_ws_invalid_token_closes_4001
  - [x] test_ws_non_member_closes_4003
  - [x] test_ws_message_saved_to_db
  - [x] test_ws_message_broadcast_to_all_members
  - [x] test_ws_empty_message_ignored
  - [x] test_ws_disconnect_removes_from_registry

---

## Dev Notes

### 핵심 사항 요약

1. **백엔드 전용 스토리** — Flutter WebSocket 클라이언트는 Story 4.3에서 구현
2. **엔드포인트 경로**: `/ws/chat/{room_id}` — `/api/v1/` prefix 없음. `app.include_router(ws_router)` (prefix 생략)
3. **JWT in WebSocket**: HTTP Bearer 헤더 불가 → 쿼리 파라미터 `?token=`. `CurrentUser` Dep 사용 불가, 직접 `jwt.decode` 필요
4. **DB Session**: `SessionDep` (FastAPI Depends) 는 WebSocket 내부 루프에서 사용 위험 → `Session(engine)` 직접 생성 + `with` 블록으로 관리
5. **ConnectionManager 싱글톤**: 모듈 레벨 `manager` 인스턴스 — 프로세스 메모리 공유. 수평 확장 시 Redis 필요하지만 MVP는 단일 서버
6. **broadcast 실패 내성**: 하나의 클라이언트 send 실패가 나머지 브로드캐스트를 막으면 안 됨 → try/except per connection
7. **`ChatMessage` (not `Message`)**: Story 4.1에서 models.py의 `Message` 이름 충돌로 `ChatMessage`로 명명됨

### 프로젝트 구조

**NEW — 새로 생성:**
```
backend/app/services/websocket.py
backend/app/api/routes/ws_chat.py
backend/tests/api/test_websocket.py
```

**UPDATE — 수정:**
```
backend/app/main.py   ← ws_router 등록 (prefix 없이)
```

### 기존 코드 컨텍스트 (반드시 보존)

**`app/core/security.py` JWT 검증 패턴:**
```python
# 이미 구현된 검증 함수들
ALGORITHM = "HS256"

def create_access_token(subject: str | Any, role: str = "user") -> str: ...
# jwt.decode(token, settings.SECRET_KEY, algorithms=[ALGORITHM])
# → payload["sub"] = user_id (UUID str)
```

**`app/api/deps.py` 토큰 검증 패턴 (ws_chat.py에서 재구현):**
```python
import jwt
from jwt.exceptions import InvalidTokenError
from pydantic import ValidationError
from app.models import TokenPayload

# WebSocket용 인라인 검증:
try:
    payload = jwt.decode(token, settings.SECRET_KEY, algorithms=[security.ALGORITHM])
    token_data = TokenPayload(**payload)
    user_id = uuid.UUID(token_data.sub)
except (InvalidTokenError, ValidationError, ValueError, AttributeError):
    await websocket.close(code=4001)
    return
```

**`app/core/db.py` — Session 직접 생성:**
```python
# deps.py에서 사용되는 engine
from app.core.db import engine
from sqlmodel import Session

# WebSocket 핸들러 내부에서:
with Session(engine) as session:
    member = session.exec(select(ChatRoomMember).where(...)).first()
```

**`app/models.py` 채팅 모델 (Story 4.1에서 추가됨):**
```python
class ChatRoom(SQLModel, table=True):    # __tablename__ = "chat_rooms"
class ChatRoomMember(SQLModel, table=True):  # __tablename__ = "chat_room_members"
class ChatMessage(SQLModel, table=True): # __tablename__ = "messages" ← Message 아님!
    id: uuid.UUID
    room_id: uuid.UUID
    sender_id: uuid.UUID
    content: str
    created_at: datetime
```

**`app/main.py` 현재 상태 (수정 대상):**
```python
from app.api.main import api_router

app = FastAPI(...)
# exception_handler, CORS middleware 등록...
app.include_router(api_router, prefix=settings.API_V1_STR)
# ← 이 아래에 ws_router 추가
```

**`backend/app/services/oauth.py` 서비스 파일 패턴 참고:**
```python
# services/ 폴더에 이미 oauth.py 존재
# websocket.py도 동일 폴더에 생성
```

---

## WebSocket 메시지 형식 (아키텍처 명세)

**서버 → 클라이언트:**
```json
// 연결 성공
{"type": "connected", "room_id": "<uuid-str>"}

// 메시지 브로드캐스트
{
  "type": "message",
  "id": "<uuid-str>",
  "room_id": "<uuid-str>",
  "sender_id": "<uuid-str>",
  "sender_nickname": "홍길동",
  "content": "안녕하세요!",
  "created_at": "2026-05-30T10:00:00+00:00"
}
```

**클라이언트 → 서버:**
```json
{"type": "message", "content": "안녕하세요!"}
```

**WebSocket close codes:**
- `4001` — 인증 실패 (토큰 없음/만료/무효)
- `4003` — 채팅방 멤버 아님 (Forbidden)

---

## 구현 상세

### 1. `backend/app/services/websocket.py` (NEW)

```python
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
        """
        failed: list[WebSocket] = []
        for connection in list(self._rooms.get(room_id, [])):
            try:
                await connection.send_json(message)
            except Exception:
                failed.append(connection)
        for ws in failed:
            self.disconnect(room_id, ws)

    @property
    def room_count(self) -> int:
        """테스트용: 활성 room 수."""
        return len(self._rooms)

    def connection_count(self, room_id: uuid.UUID) -> int:
        """테스트용: 특정 room의 활성 연결 수."""
        return len(self._rooms.get(room_id, []))


# 프로세스 전역 싱글톤 — MVP 단일 서버 가정
manager = ConnectionManager()
```

### 2. `backend/app/api/routes/ws_chat.py` (NEW)

```python
"""Story 4.2 — WebSocket 채팅 엔드포인트."""
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
from app.services.websocket import manager

ws_router = APIRouter()


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

    except WebSocketDisconnect:
        manager.disconnect(room_id, websocket)
```

### 3. `backend/app/main.py` 수정

`app.include_router(api_router, ...)` 줄 **이후**에 추가:

```python
from app.api.routes.ws_chat import ws_router

# ... 기존 코드 ...
app.include_router(api_router, prefix=settings.API_V1_STR)
app.include_router(ws_router)  # /ws/chat/{room_id} — prefix 없음
```

### 4. `backend/tests/api/test_websocket.py` (NEW)

**TestClient WebSocket 패턴:**
```python
from fastapi.testclient import TestClient

# WebSocket 연결 (동기 컨텍스트 매니저)
with client.websocket_connect(f"/ws/chat/{room.id}?token={token}") as ws:
    data = ws.receive_json()   # {"type": "connected", ...}
    ws.send_json({"type": "message", "content": "hello"})
    msg = ws.receive_json()    # broadcast
```

**두 클라이언트 브로드캐스트 테스트:**
```python
with client.websocket_connect(f"...?token={token1}") as ws1:
    ws1.receive_json()  # connected
    with client.websocket_connect(f"...?token={token2}") as ws2:
        ws2.receive_json()  # connected
        ws1.send_json({"type": "message", "content": "hi"})
        msg1 = ws1.receive_json()   # sender도 broadcast 받음
        msg2 = ws2.receive_json()   # receiver도 broadcast 받음
        assert msg1["content"] == msg2["content"] == "hi"
```

**DB 변경 확인 (Session 분리 문제):**
```python
# WebSocket 핸들러는 별도 Session으로 commit → test db 세션은 expire_all() 필요
db.expire_all()
msgs = db.exec(select(ChatMessage).where(ChatMessage.room_id == room.id)).all()
assert len(msgs) == 1
```

**close code 테스트:**
```python
# close code 검증 — pytest.raises(WebSocketDisconnect) 패턴
from starlette.websockets import WebSocketDisconnect as StarletteWSD

with pytest.raises(Exception):
    with client.websocket_connect("/ws/chat/...?token=bad") as ws:
        ws.receive_json()
```

---

## 개발자 가드레일

### MUST 따라야 할 패턴

1. **`Session(engine)` 직접 생성**: WebSocket 핸들러에서 `SessionDep` (FastAPI Depends) 사용 금지. `with Session(engine) as session:` 블록으로 필요할 때마다 생성·소멸.

2. **`jwt.decode` 직접 호출**: `CurrentUser` Dep 사용 불가 (OAuth2PasswordBearer는 HTTP Authorization 헤더만 읽음). `_authenticate_ws()` 헬퍼로 분리.

3. **`try/finally` 또는 `except WebSocketDisconnect`**: 연결 종료 시 항상 `manager.disconnect()` 호출. 미호출 시 레지스트리에 죽은 연결 누적.

4. **broadcast 예외 내성**: `broadcast_to_room` 내부에서 개별 send 실패를 catch하고 다음 연결로 진행. 한 클라이언트 문제가 전체 broadcast를 막으면 안 됨.

5. **close before accept**: `accept()` 전에는 일반 HTTP close 불가. `close(code=...)` 호출 시 FastAPI가 내부적으로 accept 후 close함. (WebSocketDisconnect 발생하지 않음)

6. **`ChatMessage` (not `Message`)**: Story 4.1 결과물. models.py에 `Message` 이름은 generic schema로 이미 사용 중.

7. **`app.include_router(ws_router)` — prefix 없음**: `settings.API_V1_STR` prefix 없이 루트에서 등록. `/ws/chat/{room_id}` 그대로 노출.

8. **모듈 수준 `manager = ConnectionManager()`**: 싱글톤. 서버 재시작 시 연결 초기화됨 (정상).

### MUST NOT

- `asyncio`/`async` WebSocket을 별도 스레드로 실행 금지 — FastAPI ASGI 이벤트 루프에서 실행
- `WebSocket` close 후 `await websocket.receive_json()` 호출 금지 — 이미 닫힌 연결
- `BackgroundTasks` (FCM) 이 스토리에서 구현 금지 — Story 4.5에서 구현
- REST 엔드포인트 수정 금지 — Story 4.1 chat.py 변경 없음
- `async def get_db()` async session 전환 금지 — 기존 sync 유지

---

## 이전 스토리 학습사항 (Story 4.1)

1. **`Message` 이름 충돌**: `models.py`에 `class Message(SQLModel): message: str` 존재 → 채팅 메시지는 `ChatMessage`. `__tablename__ = "messages"` 유지.

2. **`from app.api.deps import CurrentUser, SessionDep`** — HTTP 라우트 패턴. WebSocket에서는 이 패턴이 작동하지 않으므로 인라인 구현 필요.

3. **`SaText` alias**: `models.py`에서 `Text`는 `SaText`로 import됨. WebSocket 코드는 models.py를 직접 수정하지 않으므로 무관.

4. **라우터 prefix 위치**: HTTP 라우터는 `APIRouter(prefix="/chat-rooms")`. WebSocket 라우터는 prefix 없이 `APIRouter()`, main.py에서도 prefix 없이 include.

5. **test fixtures**: `db`는 session-scoped, `client`는 module-scoped. WebSocket 핸들러는 별도 Session 생성 → test 완료 후 `db.expire_all()` 필요.

6. **`crud.upsert_google_user`**: 테스트 사용자 생성 함수. test_chat.py에서 사용한 `_make_user(db)` 패턴 동일 사용.

---

## Dev Agent Record

### Agent Model Used

claude-sonnet-4-6

### Debug Log References

- Python 3.14에서 `asyncio.get_event_loop()` deprecated → RuntimeError. `asyncio.run()`으로 수정. ConnectionManager 단위 테스트 3개에서 발생, 단일 async 함수로 래핑하여 해결.

### Completion Notes List

- `services/websocket.py`: ConnectionManager 클래스 + 싱글톤 `manager`. `broadcast_to_room`은 개별 실패 내성 구현 (failed list → disconnect after loop)
- `api/routes/ws_chat.py`: `/ws/chat/{room_id}?token=` WebSocket 엔드포인트. `_authenticate_ws()` JWT 인라인 검증. 4001/4003 close code 구현
- `main.py`: `app.include_router(ws_router)` prefix 없이 등록 → `/ws/chat/{room_id}` 노출
- 13개 신규 테스트: 단위(ConnectionManager 3개) + 통합(연결/메시지/disconnect 10개)
- 118/118 전체 테스트 통과 (기존 105 + 신규 13), 회귀 없음

### File List

- backend/app/services/websocket.py (NEW)
- backend/app/api/routes/ws_chat.py (NEW)
- backend/app/main.py (UPDATE — ws_router 등록)
- backend/tests/api/test_websocket.py (NEW)
