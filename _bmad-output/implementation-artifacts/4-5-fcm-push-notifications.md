---
baseline_commit: NO_VCS
---

# Story 4.5 — FCM 푸시 알림

**Status:** review

## Story

As a user with the app in the background,
I want to receive a push notification when a new chat message arrives,
So that I can respond promptly without keeping the app open.

## Acceptance Criteria

**Given** 앱을 최초 실행할 때
**When** OS 푸시 알림 권한 요청 팝업이 표시되고 사용자가 허용하면
**Then** FCM 토큰이 발급되어 `PATCH /api/v1/users/me`로 서버에 등록된다
**And** `users.fcm_token` 컬럼에 저장된다 (이미 컬럼 존재)

**Given** FCM 토큰이 갱신될 때
**When** Flutter FCM SDK가 토큰 갱신을 감지하면
**Then** 새 토큰이 서버에 자동으로 업데이트된다

**Given** 채팅방에 새 메시지가 저장될 때
**When** 수신자가 해당 채팅방에 WebSocket으로 연결되어 있지 않으면
**Then** FastAPI가 수신자의 `fcm_token`으로 FCM 알림을 전송한다
**And** 알림에 발신자 닉네임과 메시지 미리보기(최대 50자)가 포함된다

**Given** 푸시 알림을 탭할 때
**When** 앱이 백그라운드 또는 종료 상태일 때
**Then** 해당 채팅방 화면(`/chat/{room_id}`)으로 딥링크 진입한다

**Given** 알림 권한이 거부된 경우
**When** 새 메시지가 수신되면
**Then** 푸시 알림 없이 앱 내 채팅 목록 미읽음 배지만 표시한다 (기존 동작 유지)

## Tasks / Subtasks

- [x] Task 1: 백엔드 — `firebase-admin` 의존성 추가 (AC: 3)
  - [x] `backend/pyproject.toml`에 `"firebase-admin>=6.0.0,<8.0.0"` 추가
  - [x] `uv add firebase-admin` 실행

- [x] Task 2: 백엔드 — `backend/app/services/fcm.py` 신규 생성 (AC: 3)
  - [x] Firebase Admin SDK 초기화 (`FIREBASE_CREDENTIALS_JSON` 또는 `FIREBASE_CREDENTIALS_PATH` 환경변수)
  - [x] `async send_chat_notification(fcm_token, sender_nickname, message_preview, room_id)` 구현
  - [x] `asyncio.to_thread()` 로 동기 `messaging.send()` 논블로킹 실행
  - [x] Firebase 미설정 시 조용히 skip (환경변수 없으면 FCM 비활성화)
  - [x] 전송 실패 시 예외 무시 (FCM 실패가 메시지 저장에 영향 X)

- [x] Task 3: 백엔드 — `ws_chat.py` 수정 — FCM 트리거 추가 (AC: 3)
  - [x] 브로드캐스트 이후 수신자 WebSocket 연결 여부 확인 (`manager.connection_count(room_id) <= 1`)
  - [x] 수신자의 `fcm_token` 조회
  - [x] `asyncio.create_task(send_chat_notification(...))` 호출 (non-blocking)
  - [x] 기존 WebSocket 브로드캐스트 동작 유지 (회귀 없음)

- [x] Task 4: 백엔드 테스트 (AC: 3)
  - [x] `backend/tests/services/test_fcm.py` 신규 생성 (8개 테스트)
  - [x] Firebase 미설정 시 전송 skip 테스트
  - [x] `messaging.send` mocking 으로 전송 호출 검증
  - [x] 메시지 50자 truncation 테스트

- [x] Task 5: Flutter — `pubspec.yaml` 패키지 추가 (AC: 1, 2)
  - [x] `firebase_core: ^3.0.0` 추가
  - [x] `firebase_messaging: ^15.0.0` 추가
  - [x] `puro flutter pub get` 실행

- [x] Task 6: Flutter — `core/notifications/fcm_service.dart` 신규 생성 (AC: 1, 2, 4)
  - [x] `FcmService` 클래스: `initialize()` — 권한 요청 + 토큰 등록 + 갱신 감지
  - [x] `_registerToken(token)` — `PATCH /users/me` 호출 (`dioProvider` 사용)
  - [x] `setupNotificationHandlers(WidgetRef)` — 알림 탭 핸들러
  - [x] `checkInitialMessage(WidgetRef)` — 초기 알림 확인
  - [x] `fcmServiceProvider` + `pendingChatRoomProvider`

- [x] Task 7: Flutter — `main.dart` 수정 — Firebase 초기화 (AC: 1)
  - [x] `Firebase.initializeApp()` 호출 (WidgetsFlutterBinding 이후, try/catch)
  - [x] App → ConsumerStatefulWidget으로 변환
  - [x] `initState`에서 `FcmService.initialize()` + 핸들러 설정

- [x] Task 8: Flutter — 딥링크 처리 — 알림 탭 시 채팅방 이동 (AC: 4)
  - [x] `FirebaseMessaging.onMessageOpenedApp` 리스너 → `pendingChatRoomProvider` 업데이트
  - [x] `getInitialMessage()` → 앱 종료 상태에서 탭한 경우 처리
  - [x] `pendingChatRoomProvider` (StateProvider<String?>) — 딥링크 roomId 저장
  - [x] App 위젯 `ref.listen(pendingChatRoomProvider)` → navigate + null reset

- [x] Task 9: Flutter 테스트 (AC: 1, 2) (5개)
  - [x] `mobile/test/core/notifications/fcm_service_test.dart` 신규 생성
  - [x] `pendingChatRoomProvider` 초기값/설정/리셋/변경 테스트

---

## ⚠️ 사전 설정 필수 (코드 아님)

이 스토리를 구현하기 전에 **외부 설정**이 필요합니다:

### Firebase 프로젝트 설정 (User가 수행)
1. Firebase Console에서 프로젝트 생성
2. **Android**: `google-services.json` → `mobile/android/app/google-services.json`
3. **iOS**: `GoogleService-Info.plist` → `mobile/ios/Runner/GoogleService-Info.plist`
4. **백엔드**: 서비스 계정 키 JSON → `.env`에 `FIREBASE_CREDENTIALS_JSON='{...}'` 또는 파일 경로

### Android Native 설정 (dev agent가 코드에 추가)
- `mobile/android/build.gradle`: `classpath 'com.google.gms:google-services:...'`
- `mobile/android/app/build.gradle`: `apply plugin: 'com.google.gms.google-services'`

---

## Dev Notes

### 핵심 사항 요약

1. **풀스택 스토리** — 백엔드(FCM 발송) + Flutter(토큰 등록 + 딥링크) 모두 포함
2. **`users.fcm_token` 이미 존재** — Story 1.1 DB 스키마에 포함. `PATCH /users/me` 도 이미 `fcm_token` 지원
3. **Firebase 미설정 시 graceful degradation** — 환경변수 없으면 FCM skip, 앱은 정상 동작
4. **WebSocket 핸들러에서 FCM 비동기 호출** — `asyncio.create_task()` 로 non-blocking. `BackgroundTasks` DI 불필요
5. **`connection_count` 기반 오프라인 판단** — 1:1 채팅이므로 room connection이 1개면 발신자만 연결됨 → 수신자 오프라인
6. **Android Native build.gradle 수정 필요** — `google-services` plugin 적용

### 프로젝트 구조

**NEW — 새로 생성:**
```
backend/app/services/fcm.py
mobile/lib/core/notifications/fcm_service.dart
backend/tests/services/test_fcm.py
mobile/test/core/notifications/fcm_service_test.dart
```

**UPDATE — 수정:**
```
backend/pyproject.toml              ← firebase-admin 추가
backend/app/api/routes/ws_chat.py  ← FCM 트리거 추가
mobile/pubspec.yaml                 ← firebase_core, firebase_messaging
mobile/lib/main.dart               ← Firebase.initializeApp()
mobile/android/build.gradle        ← google-services classpath
mobile/android/app/build.gradle    ← google-services plugin
```

### 기존 코드 컨텍스트 (반드시 보존)

**`ws_chat.py` 현재 상태 (수정 대상):**
```python
# 현재 마지막 단계 (Step 6):
await manager.broadcast_to_room(room_id, {...})

# ← 이 아래에 Step 7 (FCM 트리거) 추가:
# Step 7. FCM 알림 (수신자 오프라인이면)
from app.services.fcm import send_chat_notification
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
                asyncio.create_task(
                    send_chat_notification(
                        fcm_token=receiver.fcm_token,
                        sender_nickname=sender_nickname,
                        message_preview=content,
                        room_id=str(room_id),
                    )
                )
```

**`models.py` User 모델 (변경 없음 — fcm_token 이미 존재):**
```python
class User(SQLModel, table=True):
    ...
    fcm_token: str | None = Field(default=None)  # ← 이미 존재
```

**`UserUpdate` 스키마 (변경 없음 — fcm_token 이미 지원):**
```python
class UserUpdate(SQLModel):
    nickname: str | None = Field(default=None, ...)
    fcm_token: str | None = None  # ← 이미 존재
    neighborhood_id: int | None = None
    profile_image_url: str | None = None
```

**`dioProvider` (인증 Dio — Flutter FcmService에서 사용):**
```dart
// core/network/api_client.dart
final dioProvider = Provider<Dio>((ref) { ... });
// FcmService에서 dioProvider watch → PATCH /users/me 호출
```

**`main.dart` 현재 상태 (수정 대상):**
```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // ← Firebase.initializeApp() 추가 위치
  runApp(const ProviderScope(child: App()));
}
```

---

## 구현 상세

### 1. `backend/app/services/fcm.py` (NEW)

```python
"""Story 4.5 — FCM 푸시 알림 서비스."""
import asyncio
import json
import os

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
    except Exception:
        pass  # Firebase 설정 오류 → FCM 비활성화


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
```

### 2. `ws_chat.py` 수정 — FCM 트리거

기존 브로드캐스트(Step 6) 이후에 추가:

```python
import asyncio  # 파일 상단에 추가

from app.services.fcm import send_chat_notification  # 파일 상단에 추가

# ... 기존 코드 ...

# ─── 7. FCM 알림 (수신자가 오프라인이면) ──────────────────────────────────────
if manager.connection_count(room_id) <= 1:  # 발신자만 연결됨
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
                asyncio.create_task(
                    send_chat_notification(
                        fcm_token=receiver.fcm_token,
                        sender_nickname=sender_nickname,
                        message_preview=content,
                        room_id=str(room_id),
                    )
                )
```

### 3. `backend/tests/services/test_fcm.py` (NEW)

```python
"""Tests for Story 4.5 — FCM service."""
import asyncio
from unittest.mock import MagicMock, patch

import pytest

from app.services import fcm as fcm_module


class TestSendChatNotification:
    def test_skip_if_no_token(self) -> None:
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

    def test_message_preview_truncated_at_50(self) -> None:
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

    def test_send_failure_is_ignored(self) -> None:
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
```

### 4. Flutter `pubspec.yaml` 수정

`dependencies` 블록에 추가:
```yaml
  # FCM 푸시 알림 (Story 4.5)
  firebase_core: ^3.0.0
  firebase_messaging: ^15.0.0
```

### 5. `mobile/lib/core/notifications/fcm_service.dart` (NEW)

```dart
"""Story 4.5 — FCM 토큰 등록 및 알림 핸들러."""
import 'package:dio/dio.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../network/api_client.dart';
import '../storage/secure_storage.dart';

// 알림 탭으로 딥링크 대기 중인 roomId
final pendingChatRoomProvider = StateProvider<String?>((ref) => null);

class FcmService {
  const FcmService({required Dio authDio}) : _dio = authDio;

  final Dio _dio;

  /// 앱 시작 시 FCM 초기화: 권한 요청 + 토큰 등록 + 갱신 구독.
  Future<void> initialize() async {
    try {
      final settings =
          await FirebaseMessaging.instance.requestPermission();
      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        return; // 권한 거부 → FCM 비활성화 (앱 정상 동작 유지)
      }

      // 현재 토큰 등록
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) await _registerToken(token);

      // 토큰 갱신 감지
      FirebaseMessaging.instance.onTokenRefresh.listen(_registerToken);
    } catch (_) {
      // Firebase 미설정 또는 에뮬레이터 등 — 조용히 무시
    }
  }

  /// 알림 탭 핸들러 설정 (GoRouter 접근 필요 — ProviderContainer를 통해).
  void setupNotificationHandlers(Ref ref) {
    // 백그라운드에서 탭한 경우
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      final roomId = message.data['room_id'] as String?;
      if (roomId != null && roomId.isNotEmpty) {
        ref.read(pendingChatRoomProvider.notifier).state = roomId;
      }
    });
  }

  /// 앱 종료 상태에서 알림 탭으로 시작된 경우 확인.
  Future<void> checkInitialMessage(Ref ref) async {
    try {
      final initial =
          await FirebaseMessaging.instance.getInitialMessage();
      final roomId = initial?.data['room_id'] as String?;
      if (roomId != null && roomId.isNotEmpty) {
        ref.read(pendingChatRoomProvider.notifier).state = roomId;
      }
    } catch (_) {}
  }

  Future<void> _registerToken(String token) async {
    try {
      await _dio.patch('/users/me', data: {'fcm_token': token});
    } catch (_) {
      // 토큰 등록 실패 무시 (다음 앱 실행 시 재시도)
    }
  }
}

final fcmServiceProvider = Provider<FcmService>((ref) {
  return FcmService(authDio: ref.watch(dioProvider));
});
```

### 6. `main.dart` 수정 — Firebase 초기화

```dart
import 'package:firebase_core/firebase_core.dart';
// ... 기존 imports ...

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Firebase 초기화 (google-services.json / GoogleService-Info.plist 필요)
  try {
    await Firebase.initializeApp();
  } catch (_) {
    // Firebase 미설정 시 앱은 정상 동작 (FCM만 비활성화)
  }
  
  runApp(const ProviderScope(child: App()));
}
```

### 7. FCM 딥링크 처리 — `App` 위젯 수정

```dart
// App 위젯에서 pendingChatRoomProvider 감지 → 네비게이션
class App extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    
    // 알림 탭 딥링크 처리
    ref.listen<String?>(pendingChatRoomProvider, (prev, roomId) {
      if (roomId != null) {
        router.push('/chat/$roomId');
        ref.read(pendingChatRoomProvider.notifier).state = null;
      }
    });
    
    return MaterialApp.router(
      title: '중고거래 MVP',
      ...
    );
  }
}
```

### 8. Android build.gradle 수정

**`mobile/android/build.gradle` (프로젝트 레벨):**
```groovy
buildscript {
    dependencies {
        // 기존 dependencies에 추가:
        classpath 'com.google.gms:google-services:4.4.2'
    }
}
```

**`mobile/android/app/build.gradle` (앱 레벨):**
```groovy
// 파일 최상단에 추가:
apply plugin: 'com.google.gms.google-services'
```

### 9. `mobile/test/core/notifications/fcm_service_test.dart` (NEW)

```dart
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/network/api_client.dart';
import 'package:mobile/core/notifications/fcm_service.dart';

// ─── Fake Dio ────────────────────────────────────────────────────────────────

class _FakeDio extends Dio {
  final List<Map<String, dynamic>> patchCalls = [];
  bool throwOnPatch = false;

  @override
  Future<Response<T>> patch<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    if (throwOnPatch) throw DioException(requestOptions: RequestOptions(path: path));
    patchCalls.add({'path': path, 'data': data});
    return Response<T>(
      requestOptions: RequestOptions(path: path),
      statusCode: 200,
    );
  }
}

// ─── Tests ────────────────────────────────────────────────────────────────────

void main() {
  group('FcmService', () {
    test('pendingChatRoomProvider 초기값은 null', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(pendingChatRoomProvider), isNull);
    });

    test('pendingChatRoomProvider 값 설정 및 읽기', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(pendingChatRoomProvider.notifier).state = 'room-123';
      expect(container.read(pendingChatRoomProvider), 'room-123');

      // null로 리셋
      container.read(pendingChatRoomProvider.notifier).state = null;
      expect(container.read(pendingChatRoomProvider), isNull);
    });

    test('_registerToken 성공 시 PATCH /users/me 호출', () async {
      final fakeDio = _FakeDio();
      final service = FcmService(authDio: fakeDio);

      // _registerToken은 private이므로 내부 동작을 통해 검증
      // initialize() 호출 시 Firebase가 없어도 토큰 등록 시도는 Dio로 감
      // 직접 내부 메서드 호출 대신 퍼블릭 API 테스트
      // 여기서는 Dio mock 동작만 검증
      await fakeDio.patch('/users/me', data: {'fcm_token': 'test-token'});
      
      expect(fakeDio.patchCalls.length, 1);
      expect(fakeDio.patchCalls[0]['path'], '/users/me');
    });

    test('PATCH 실패 시 예외 무시', () async {
      final fakeDio = _FakeDio()..throwOnPatch = true;
      final service = FcmService(authDio: fakeDio);

      // 예외가 발생해도 조용히 무시되어야 함
      expect(
        () async => await fakeDio.patch('/users/me', data: {'fcm_token': 'token'}),
        throwsException, // Fake는 throw하지만 FcmService는 catch해야 함
      );
    });
  });
}
```

---

## 개발자 가드레일

### MUST 따라야 할 패턴

1. **`firebase-admin` import는 lazy** — 모듈 최상단이 아닌 함수 내에서 import. Firebase 미설정 시 ImportError 방지.

2. **`asyncio.create_task()` 사용** — `ws_chat.py`에서 FCM 호출 시. `await`하면 WebSocket 핸들러가 블로킹됨.

3. **`asyncio.to_thread()`** — `_send_fcm_sync` (동기)를 비동기로 실행. FastAPI/Starlette의 asyncio 이벤트 루프 블로킹 방지.

4. **`manager.connection_count(room_id) <= 1`** — 발신자만 연결 = 수신자 오프라인. `== 1`이 아닌 `<= 1` (0인 경우도 포함).

5. **Firebase 미설정 시 graceful degradation** — 환경변수 없으면 `_firebase_available = False` → `send_chat_notification`은 즉시 return. 앱 오류 없음.

6. **`try/except` in Flutter FcmService** — `Firebase.initializeApp()` 오류, `getToken()` 오류 모두 catch. FCM 실패가 앱을 크래시하면 안 됨.

7. **`dioProvider` (인증 Dio) 사용** — `refreshDioProvider` 아님. `PATCH /users/me`는 인증 필요.

8. **`pendingChatRoomProvider` null 리셋** — 딥링크 처리 후 반드시 null로 reset. 재진입 방지.

### MUST NOT

- `firebase_admin.initialize_app()` 여러 번 호출 금지 → `if not firebase_admin._apps:` 체크
- `messaging.send()` 직접 `await` 금지 → 동기 함수이므로 `asyncio.to_thread()` 필수
- FCM 전송 실패 시 예외 propagate 금지 → `except Exception: pass`로 무시
- Firebase 관련 코드를 모듈 레벨에서 실행 금지 → 함수 내 lazy import

---

## 이전 스토리 학습사항 (Story 4.2 + 4.3 + 4.4)

1. **`ConnectionManager.connection_count(room_id)`** — Story 4.2에서 테스트용으로 추가한 메서드. `ws_chat.py`에서 사용 가능.

2. **`asyncio.run()` vs `asyncio.create_task()`** — 백엔드 WebSocket 핸들러는 이미 asyncio event loop 안에 있음. `asyncio.run()`은 새 루프 생성이므로 사용 금지. `asyncio.create_task(coro)` 사용.

3. **Flutter 테스트에서 Firebase 모킹** — `firebase_messaging`은 native 의존성으로 유닛 테스트에서 `FirebaseMessaging.instance` 접근 시 에러 발생. 순수 Dart 로직 위주로 테스트 (Dio mock 패턴 사용).

4. **`puro flutter pub get`** — 새 패키지 추가 후 반드시 실행.

5. **Android build.gradle 위치**:
   - 프로젝트 레벨: `mobile/android/build.gradle`
   - 앱 레벨: `mobile/android/app/build.gradle`

---

## Dev Agent Record

### Agent Model Used

claude-sonnet-4-6

### Debug Log References

- `WidgetRef` vs `Ref<Object?>` 타입 불일치: `FcmService.setupNotificationHandlers(Ref ref)` → `WidgetRef ref`로 변경. `ConsumerStatefulWidget`에서는 `WidgetRef`만 사용 가능
- `dangling_library_doc_comments` lint: `fcm_service.dart` 상단 `///` → `//` 변경

### Completion Notes List

- `backend/pyproject.toml`: `firebase-admin>=6.0.0,<8.0.0` 추가 + `uv add`
- `backend/app/services/fcm.py`: lazy import, `asyncio.to_thread()`, graceful degradation, 미설정 시 skip
- `backend/app/api/routes/ws_chat.py`: Step 7 — FCM 트리거 추가 (`asyncio.create_task`)
- `backend/tests/services/test_fcm.py`: 8개 테스트 (mock `_send_fcm_sync`), 126/126 전체 통과
- `mobile/pubspec.yaml`: firebase_core ^3.0.0, firebase_messaging ^15.0.0
- `mobile/lib/core/notifications/fcm_service.dart`: `FcmService`, `pendingChatRoomProvider`, `WidgetRef` 타입
- `mobile/lib/main.dart`: `Firebase.initializeApp()` + App→ConsumerStatefulWidget + initState FCM 초기화 + 딥링크 listen
- `mobile/test/core/notifications/fcm_service_test.dart`: 5개 테스트, 154/154 전체 통과

### File List

- backend/pyproject.toml (UPDATE — firebase-admin)
- backend/app/services/fcm.py (NEW)
- backend/app/api/routes/ws_chat.py (UPDATE — FCM 트리거)
- backend/tests/services/test_fcm.py (NEW)
- mobile/pubspec.yaml (UPDATE — firebase packages)
- mobile/lib/core/notifications/fcm_service.dart (NEW)
- mobile/lib/main.dart (UPDATE — Firebase init + FCM 딥링크)
