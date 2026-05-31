"""Story 4.5 — FCM 푸시 알림 서비스."""
import asyncio
import json
import logging
import os

logger = logging.getLogger(__name__)

_firebase_available = False


def _init_firebase() -> None:
    global _firebase_available
    try:
        import firebase_admin
        from firebase_admin import credentials

        cred_json = os.getenv("FIREBASE_CREDENTIALS_JSON", "")
        cred_path = os.getenv("FIREBASE_CREDENTIALS_PATH", "")

        if cred_json:
            cred = credentials.Certificate(json.loads(cred_json))
        elif cred_path and os.path.exists(cred_path):
            cred = credentials.Certificate(cred_path)
        else:
            return  # Firebase 미설정 — FCM 비활성화

        # 이미 초기화된 경우 skip (테스트 등에서 중복 호출 방지)
        if not firebase_admin._apps:
            firebase_admin.initialize_app(cred)
        _firebase_available = True
    except Exception as exc:
        logger.warning("FCM init failed — push notifications disabled: %s", exc)


_init_firebase()


def _send_fcm_sync(
    token: str, title: str, body: str, data: dict[str, str]
) -> None:
    """동기 FCM 전송 — asyncio.to_thread()에서 실행."""
    from firebase_admin import messaging

    message = messaging.Message(
        notification=messaging.Notification(title=title, body=body),
        data=data,
        token=token,
    )
    messaging.send(message)


async def send_chat_notification(
    *,
    fcm_token: str,
    sender_nickname: str,
    message_preview: str,
    room_id: str,
) -> None:
    """채팅 FCM 알림 전송 (논블로킹). 미설정 또는 실패 시 무시."""
    if not _firebase_available or not fcm_token:
        return
    try:
        preview = message_preview[:50]
        await asyncio.to_thread(
            _send_fcm_sync,
            fcm_token,
            sender_nickname,
            preview,
            {"type": "chat", "room_id": room_id},
        )
    except Exception:
        pass  # FCM 전송 실패는 무시


def is_available() -> bool:
    """FCM 활성화 여부 (테스트용)."""
    return _firebase_available
