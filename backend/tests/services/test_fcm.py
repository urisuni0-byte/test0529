"""Tests for Story 4.5 — FCM service."""
import asyncio
from unittest.mock import patch

from app.services import fcm as fcm_module


class TestFcmAvailability:
    def test_unavailable_without_firebase_config(self) -> None:
        """환경변수 없으면 FCM 비활성화."""
        assert not fcm_module.is_available()


class TestSendChatNotification:
    def test_skip_if_empty_token(self) -> None:
        """fcm_token이 빈 문자열이면 전송하지 않는다."""
        original = fcm_module._firebase_available
        fcm_module._firebase_available = True
        try:
            asyncio.run(
                fcm_module.send_chat_notification(
                    fcm_token="",
                    sender_nickname="홍길동",
                    message_preview="안녕하세요",
                    room_id="room-1",
                )
            )
        finally:
            fcm_module._firebase_available = original
        # 예외 없이 통과하면 OK

    def test_skip_if_firebase_unavailable(self) -> None:
        """Firebase 미설정이면 전송하지 않는다."""
        original = fcm_module._firebase_available
        fcm_module._firebase_available = False
        try:
            asyncio.run(
                fcm_module.send_chat_notification(
                    fcm_token="some-token",
                    sender_nickname="홍길동",
                    message_preview="안녕하세요",
                    room_id="room-1",
                )
            )
        finally:
            fcm_module._firebase_available = original

    def test_message_preview_truncated_at_50_chars(self) -> None:
        """메시지 미리보기가 50자로 잘린다."""
        long_msg = "가" * 60
        captured: list[str] = []

        def fake_send(token: str, title: str, body: str, data: dict) -> None:
            captured.append(body)

        original = fcm_module._firebase_available
        fcm_module._firebase_available = True
        try:
            with patch.object(fcm_module, "_send_fcm_sync", fake_send):
                asyncio.run(
                    fcm_module.send_chat_notification(
                        fcm_token="token",
                        sender_nickname="홍길동",
                        message_preview=long_msg,
                        room_id="room-1",
                    )
                )
        finally:
            fcm_module._firebase_available = original

        assert len(captured) == 1
        assert len(captured[0]) == 50

    def test_send_called_with_correct_args(self) -> None:
        """FCM 전송 시 올바른 인수로 호출된다."""
        captured: list[tuple] = []

        def fake_send(token: str, title: str, body: str, data: dict) -> None:
            captured.append((token, title, body, data))

        original = fcm_module._firebase_available
        fcm_module._firebase_available = True
        try:
            with patch.object(fcm_module, "_send_fcm_sync", fake_send):
                asyncio.run(
                    fcm_module.send_chat_notification(
                        fcm_token="test-token-123",
                        sender_nickname="홍길동",
                        message_preview="안녕하세요",
                        room_id="room-uuid",
                    )
                )
        finally:
            fcm_module._firebase_available = original

        assert len(captured) == 1
        token, title, body, data = captured[0]
        assert token == "test-token-123"
        assert title == "홍길동"
        assert body == "안녕하세요"
        assert data["type"] == "chat"
        assert data["room_id"] == "room-uuid"

    def test_send_50_char_preview_exact(self) -> None:
        """50자 이하 메시지는 그대로 전달된다."""
        captured: list[str] = []

        def fake_send(token: str, title: str, body: str, data: dict) -> None:
            captured.append(body)

        original = fcm_module._firebase_available
        fcm_module._firebase_available = True
        try:
            with patch.object(fcm_module, "_send_fcm_sync", fake_send):
                asyncio.run(
                    fcm_module.send_chat_notification(
                        fcm_token="token",
                        sender_nickname="홍",
                        message_preview="짧은 메시지",
                        room_id="room",
                    )
                )
        finally:
            fcm_module._firebase_available = original

        assert captured[0] == "짧은 메시지"

    def test_send_failure_is_silently_ignored(self) -> None:
        """FCM 전송 실패 시 예외를 무시한다."""
        def fake_send_fail(*args: object) -> None:
            raise RuntimeError("FCM 서버 오류")

        original = fcm_module._firebase_available
        fcm_module._firebase_available = True
        try:
            with patch.object(fcm_module, "_send_fcm_sync", fake_send_fail):
                asyncio.run(
                    fcm_module.send_chat_notification(
                        fcm_token="token",
                        sender_nickname="홍",
                        message_preview="내용",
                        room_id="room",
                    )
                )
        finally:
            fcm_module._firebase_available = original
        # 예외 없이 통과하면 OK

    def test_preview_exactly_50_chars_not_truncated(self) -> None:
        """정확히 50자인 메시지는 그대로 전달된다."""
        msg_50 = "나" * 50
        captured: list[str] = []

        def fake_send(token: str, title: str, body: str, data: dict) -> None:
            captured.append(body)

        original = fcm_module._firebase_available
        fcm_module._firebase_available = True
        try:
            with patch.object(fcm_module, "_send_fcm_sync", fake_send):
                asyncio.run(
                    fcm_module.send_chat_notification(
                        fcm_token="token",
                        sender_nickname="sender",
                        message_preview=msg_50,
                        room_id="room",
                    )
                )
        finally:
            fcm_module._firebase_available = original

        assert len(captured[0]) == 50
