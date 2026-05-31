---
baseline_commit: NO_VCS
---

# Story 4.3 — Flutter 채팅방 화면

**Status:** review

## Story

As a buyer or seller,
I want to enter a chat room and exchange real-time messages,
So that I can coordinate the transaction with the other party.

## Acceptance Criteria

**Given** 구매자가 상품 상세 화면에서 "채팅하기"를 탭할 때
**When** POST /chat-rooms API가 성공하면
**Then** 해당 채팅방 화면으로 이동한다
**And** 채팅방이 이미 존재하면 중복 생성 없이 기존 방으로 진입한다

**Given** 채팅방 화면에 진입할 때
**When** 화면이 로드되면
**Then** 채팅 상단에 연결된 상품의 썸네일·제목·가격·판매 상태가 표시된다
**And** 기존 메시지 내역이 최신순으로 로드된다 (최신이 화면 하단)
**And** WebSocket 연결이 수립되고 `{"type": "connected"}` 수신된다

**Given** 메시지를 입력하고 전송 버튼을 탭할 때
**When** WebSocket으로 메시지를 전송하면
**Then** 본인 화면에 즉시 표시된다 (낙관적 업데이트)
**And** 빈 메시지는 전송되지 않는다 (trim 후 빈 문자열 포함)

**Given** 상대방이 메시지를 전송할 때
**When** WebSocket 브로드캐스트가 수신되면
**Then** 2초 이내에 메시지가 화면에 표시된다
**And** 스크롤이 자동으로 최하단으로 이동한다

**Given** WebSocket 연결이 끊어질 때
**When** 네트워크 오류가 감지되면
**Then** 자동 재연결을 3회 시도한다 (1초, 2초, 4초 backoff)
**And** 3회 실패 시 "오프라인" 안내 스낵바를 표시한다

## Tasks / Subtasks

- [x] Task 1: `mobile/lib/core/constants.dart` 수정 — `wsBase` getter 추가 (AC: 3)
  - [x] `static String get wsBase => baseUrl.replaceFirst('http', 'ws');` 추가

- [x] Task 2: 채팅 데이터 모델 & 리포지토리 (AC: 1, 2, 3)
  - [x] `mobile/lib/features/chat/data/models/chat_models.dart` 신규 생성
    - [x] `ChatRoomCreateResult` (id, productId, isNew)
    - [x] `ChatMessageModel` (id, roomId, senderId, senderNickname, content, createdAt, isMe)
  - [x] `mobile/lib/features/chat/data/chat_repository.dart` 신규 생성
    - [x] `createOrGetChatRoom(productId)` → POST /chat-rooms
    - [x] `getMessages(roomId, {page=1, limit=50})` → GET /chat-rooms/{id}/messages
    - [x] `markAsRead(roomId)` → PATCH /chat-rooms/{id}/read
    - [x] `chatRepositoryProvider` (dioProvider 사용 — 인증 필수)

- [x] Task 3: `ChatRoomNotifier` — 상태 관리 & WebSocket (AC: 3, 4, 5)
  - [x] `mobile/lib/features/chat/domain/chat_room_notifier.dart` 신규 생성
  - [x] `ChatRoomState` 클래스: messages, isConnected, isLoadingHistory, historyError
  - [x] `StateNotifierProvider.autoDispose.family<ChatRoomNotifier, ChatRoomState, String>` (roomId 키)
  - [x] `_init()`: 히스토리 로드 + WebSocket 연결 (unawaited 병렬)
  - [x] `sendMessage(content)`: WS 전송
  - [x] `_connectWithRetry()`: dart:io WebSocket, `?token=` 쿼리 파라미터
  - [x] 재연결: 3회 시도, 1·2·4초 backoff, 실패 시 `reconnectFailed = true`
  - [x] `dispose()`: `_ws?.close()` + `_wsSub?.cancel()` + `_disposed = true`

- [x] Task 4: `ChatRoomScreen` UI (AC: 2, 3, 4, 5)
  - [x] `mobile/lib/features/chat/presentation/chat_room_screen.dart` 신규 생성
  - [x] `ConsumerStatefulWidget` (TextEditingController + ScrollController 로컬 상태)
  - [x] 상단 상품 헤더: `productDetailProvider(productId)` watch — 썸네일·제목·가격·상태
  - [x] 메시지 목록: `ListView.builder` — 나/상대방 구분 말풍선
  - [x] 입력 + 전송 버튼: 빈/공백 메시지 비활성화 (Key('send_button'))
  - [x] 새 메시지 수신 시 자동 스크롤 최하단
  - [x] 재연결 실패 시 오프라인 스낵바

- [x] Task 5: 라우터 & 상품 상세 연결 (AC: 1)
  - [x] `mobile/lib/core/router/app_router.dart` 수정
    - [x] placeholder GoRoute 교체: `ChatRoomScreen(roomId:, productId:)`
    - [x] `state.extra as String?`로 productId 전달
  - [x] `mobile/lib/features/product/presentation/product_detail_screen.dart` 수정
    - [x] `_chatLoading` 필드 추가, `_onChatTap()` async 변환
    - [x] API 호출 → 성공 시 `context.push('/chat/${result.roomId}', extra: widget.productId)`
    - [x] `_ActionBar`에 `isChatLoading` 파라미터 추가 + 로딩 인디케이터

- [x] Task 6: 테스트 추가 (14개)
  - [x] `mobile/test/features/chat/chat_repository_test.dart` 신규 생성 (6개 모델 파싱 테스트)
  - [x] `mobile/test/features/chat/chat_room_screen_test.dart` 신규 생성 (8개 위젯 테스트)

---

## Dev Notes

### 핵심 사항 요약

1. **Flutter 전용** — 백엔드 변경 없음 (4.1 REST, 4.2 WebSocket 이미 완료)
2. **추가 패키지 불필요** — `dart:io` WebSocket 사용 (`web_socket_channel` 금지)
3. **`AppConstants.wsBase`** — `baseUrl.replaceFirst('http', 'ws')` 추가 (http→ws, https→wss 자동)
4. **라우터 placeholder 교체**: `/chat/:roomId`에 이미 scaffold 있음 → `ChatRoomScreen`으로 교체
5. **`_onChatTap()` 현재 상태**: 플레이스홀더 스낵바 → API 호출 + navigation으로 교체
6. **`productId`는 GoRouter extra로 전달**: `context.push('/chat/$roomId', extra: productId)` → `state.extra as String?`
7. **메시지 ID**: 낙관적 업데이트 시 임시 UUID, 서버 브로드캐스트 수신 후 교체 불필요 (서버가 broadcast하면 같은 roomId로 도달)
8. **history 순서**: REST API는 최신순 DESC → Flutter `ListView.reverse: true`로 최신이 하단에 표시

### 프로젝트 구조

**NEW — 새로 생성:**
```
mobile/lib/features/chat/data/models/chat_models.dart
mobile/lib/features/chat/data/chat_repository.dart
mobile/lib/features/chat/domain/chat_room_notifier.dart
mobile/lib/features/chat/presentation/chat_room_screen.dart
mobile/test/features/chat/chat_repository_test.dart
mobile/test/features/chat/chat_room_screen_test.dart
```

**UPDATE — 수정:**
```
mobile/lib/core/constants.dart              ← wsBase getter 추가
mobile/lib/core/router/app_router.dart     ← /chat/:roomId 교체
mobile/lib/features/product/presentation/product_detail_screen.dart  ← _onChatTap()
```

### 기존 코드 컨텍스트 (반드시 보존)

**`AppConstants` 현재 상태 (`core/constants.dart`):**
```dart
class AppConstants {
  AppConstants._();
  static const String baseUrl = String.fromEnvironment(..., defaultValue: 'http://10.0.2.2:8000');
  static const String apiV1 = '$baseUrl/api/v1';
  static const String googleClientId = String.fromEnvironment(..., defaultValue: '');
  // ← 여기에 wsBase 추가
}
```

**`app_router.dart` 현재 `/chat/:roomId` 라우트 (교체 대상):**
```dart
GoRoute(
  path: '/chat/:roomId',
  builder: (context, state) => Scaffold(
    appBar: AppBar(title: Text('채팅방 ${state.pathParameters['roomId']}')),
    body: const Center(child: Text('채팅 화면 (Story 4.3에서 구현)')),
  ),
),
// ↓ 교체 후:
GoRoute(
  path: '/chat/:roomId',
  builder: (context, state) {
    final productId = state.extra as String?;
    return ChatRoomScreen(
      roomId: state.pathParameters['roomId']!,
      productId: productId,
    );
  },
),
```

**`product_detail_screen.dart` 현재 `_onChatTap()` (교체 대상):**
```dart
// 현재 (플레이스홀더):
void _onChatTap() {
  if (!mounted) return;
  final isAuth = ref.read(authNotifierProvider).valueOrNull?.isAuthenticated ?? false;
  if (!isAuth) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('로그인이 필요합니다.')));
    return;
  }
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('채팅하기 (Story 4.x에서 구현)')),
  );
}

// ↓ 교체 후 (async):
bool _chatLoading = false;

Future<void> _onChatTap() async {
  if (!mounted) return;
  final isAuth = ref.read(authNotifierProvider).valueOrNull?.isAuthenticated ?? false;
  if (!isAuth) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('로그인이 필요합니다.')));
    return;
  }
  setState(() => _chatLoading = true);
  try {
    final result = await ref.read(chatRepositoryProvider).createOrGetChatRoom(widget.productId);
    if (!mounted) return;
    context.push('/chat/${result.roomId}', extra: widget.productId);
  } on AppError catch (e) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
  } finally {
    if (mounted) setState(() => _chatLoading = false);
  }
}
```

`_ActionBar`의 `onChat` 버튼: `_chatLoading` 시 `CircularProgressIndicator`로 교체:
```dart
// _ActionBar에 isLoading 파라미터 추가
child: _chatLoading
    ? const CircularProgressIndicator(color: Colors.white)
    : Text(product.isSold ? '판매완료' : '채팅하기'),
```

**기존 Repository 패턴 (chat_repository.dart에서 동일하게 따를 것):**
```dart
// product_management_repository.dart 패턴
class ChatRepository {
  const ChatRepository({required Dio authDio}) : _dio = authDio;
  final Dio _dio;
  // ... methods
}

final chatRepositoryProvider = Provider<ChatRepository>((ref) {
  return ChatRepository(authDio: ref.watch(dioProvider));
});
```

**기존 StateNotifier 사용 사례 없음** — FeedNotifier는 AsyncNotifier. 아래 채팅 패턴:
```dart
class ChatRoomNotifier extends StateNotifier<ChatRoomState> {
  ChatRoomNotifier(this.ref, this.roomId) : super(const ChatRoomState()) {
    _init();
  }
  // ...
}

final chatRoomNotifierProvider =
    StateNotifierProvider.autoDispose.family<ChatRoomNotifier, ChatRoomState, String>(
  (ref, roomId) => ChatRoomNotifier(ref, roomId),
);
```

**`secureStorageProvider` 접근 (WebSocket 토큰):**
```dart
// StateNotifier 내부에서:
final token = await ref.read(secureStorageProvider).getAccessToken();
final wsUrl = '${AppConstants.wsBase}/ws/chat/$roomId?token=$token';
```

**`productDetailProvider` 재사용 (채팅방 상품 헤더):**
```dart
// ChatRoomScreen에서:
final productAsync = ref.watch(productDetailProvider(productId ?? ''));
// 기존 Provider 재사용 — 별도 상품 조회 불필요
```

---

## API 연동

### POST /api/v1/chat-rooms

**요청:**
```json
{"product_id": "<uuid>"}
```

**응답 201 (신규) / 200 (기존):**
```json
{"id": "<uuid>", "product_id": "<uuid>", "created_at": "...", "is_new": true/false}
```

### GET /api/v1/chat-rooms/{id}/messages

**파라미터:** `page=1&limit=50`

**응답:**
```json
{
  "items": [{"id":"<uuid>","room_id":"<uuid>","sender_id":"<uuid>","sender_nickname":"홍길동","content":"안녕","created_at":"..."}],
  "total": 42, "page": 1, "limit": 50
}
```

**주의**: 최신순 DESC — Flutter `ListView.reversed: true`로 표시

### WebSocket `/ws/chat/{room_id}?token={jwt}`

**서버 → 클라이언트:**
```json
{"type": "connected", "room_id": "<uuid>"}
{"type": "message", "id": "<uuid>", "room_id": "<uuid>", "sender_id": "<uuid>", "sender_nickname": "홍길동", "content": "안녕", "created_at": "..."}
```

**클라이언트 → 서버:**
```json
{"type": "message", "content": "안녕하세요"}
```

---

## 구현 상세

### 1. `mobile/lib/features/chat/data/models/chat_models.dart` (NEW)

```dart
import 'package:flutter/foundation.dart';

class ChatRoomCreateResult {
  const ChatRoomCreateResult({
    required this.roomId,
    required this.productId,
    required this.isNew,
  });

  final String roomId;
  final String productId;
  final bool isNew;

  factory ChatRoomCreateResult.fromJson(Map<String, dynamic> json) =>
      ChatRoomCreateResult(
        roomId: json['id'] as String,
        productId: json['product_id'] as String,
        isNew: json['is_new'] as bool,
      );
}

@immutable
class ChatMessageModel {
  const ChatMessageModel({
    required this.id,
    required this.roomId,
    required this.senderId,
    required this.senderNickname,
    required this.content,
    required this.createdAt,
    required this.isMe,
  });

  final String id;
  final String roomId;
  final String senderId;
  final String senderNickname;
  final String content;
  final DateTime createdAt;
  final bool isMe;  // 현재 사용자가 발신자인지

  factory ChatMessageModel.fromJson(Map<String, dynamic> json, {required String myUserId}) =>
      ChatMessageModel(
        id: json['id'] as String,
        roomId: json['room_id'] as String,
        senderId: json['sender_id'] as String,
        senderNickname: json['sender_nickname'] as String,
        content: json['content'] as String,
        createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
        isMe: (json['sender_id'] as String) == myUserId,
      );
}
```

### 2. `mobile/lib/features/chat/data/chat_repository.dart` (NEW)

```dart
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/app_error.dart';
import '../../../core/network/api_client.dart';
import 'models/chat_models.dart';

class ChatRepository {
  const ChatRepository({required Dio authDio}) : _dio = authDio;
  final Dio _dio;

  Future<ChatRoomCreateResult> createOrGetChatRoom(String productId) async {
    try {
      final resp = await _dio.post(
        '/chat-rooms',
        data: {'product_id': productId},
      );
      return ChatRoomCreateResult.fromJson(resp.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  Future<List<ChatMessageModel>> getMessages(
    String roomId, {
    required String myUserId,
    int page = 1,
    int limit = 50,
  }) async {
    try {
      final resp = await _dio.get(
        '/chat-rooms/$roomId/messages',
        queryParameters: {'page': page, 'limit': limit},
      );
      final items = (resp.data['items'] as List).cast<Map<String, dynamic>>();
      return items
          .map((j) => ChatMessageModel.fromJson(j, myUserId: myUserId))
          .toList();
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  Future<void> markAsRead(String roomId) async {
    try {
      await _dio.patch('/chat-rooms/$roomId/read');
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }
}

final chatRepositoryProvider = Provider<ChatRepository>((ref) {
  return ChatRepository(authDio: ref.watch(dioProvider));
});
```

### 3. `mobile/lib/features/chat/domain/chat_room_notifier.dart` (NEW)

```dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants.dart';
import '../../../core/storage/secure_storage.dart';
import '../../auth/domain/auth_notifier.dart';
import '../data/chat_repository.dart';
import '../data/models/chat_models.dart';

class ChatRoomState {
  const ChatRoomState({
    this.messages = const [],
    this.isConnected = false,
    this.isLoadingHistory = true,
    this.historyError,
    this.reconnectFailed = false,
  });

  final List<ChatMessageModel> messages;
  final bool isConnected;
  final bool isLoadingHistory;
  final String? historyError;
  final bool reconnectFailed;

  ChatRoomState copyWith({
    List<ChatMessageModel>? messages,
    bool? isConnected,
    bool? isLoadingHistory,
    String? historyError,
    bool? reconnectFailed,
    bool clearHistoryError = false,
  }) =>
      ChatRoomState(
        messages: messages ?? this.messages,
        isConnected: isConnected ?? this.isConnected,
        isLoadingHistory: isLoadingHistory ?? this.isLoadingHistory,
        historyError: clearHistoryError ? null : (historyError ?? this.historyError),
        reconnectFailed: reconnectFailed ?? this.reconnectFailed,
      );
}

class ChatRoomNotifier extends StateNotifier<ChatRoomState> {
  ChatRoomNotifier(this.ref, this.roomId) : super(const ChatRoomState()) {
    _init();
  }

  final Ref ref;
  final String roomId;

  WebSocket? _ws;
  StreamSubscription? _wsSub;
  int _reconnectAttempts = 0;
  static const _maxReconnects = 3;
  bool _disposed = false;

  String get _myUserId =>
      ref.read(authNotifierProvider).valueOrNull?.user?.id ?? '';

  Future<void> _init() async {
    await Future.wait([_loadHistory(), _connect()]);
  }

  Future<void> _loadHistory() async {
    try {
      final msgs = await ref
          .read(chatRepositoryProvider)
          .getMessages(roomId, myUserId: _myUserId);
      if (!_disposed) {
        // history는 DESC → reversed하여 오래된 것이 앞에
        state = state.copyWith(
          messages: msgs.reversed.toList(),
          isLoadingHistory: false,
          clearHistoryError: true,
        );
      }
    } catch (e) {
      if (!_disposed) {
        state = state.copyWith(
          isLoadingHistory: false,
          historyError: e.toString(),
        );
      }
    }
  }

  Future<void> _connect() async {
    while (!_disposed && _reconnectAttempts <= _maxReconnects) {
      try {
        final token =
            await ref.read(secureStorageProvider).getAccessToken() ?? '';
        final uri = Uri.parse(
            '${AppConstants.wsBase}/ws/chat/$roomId?token=$token');

        _ws = await WebSocket.connect(uri.toString())
            .timeout(const Duration(seconds: 10));

        if (_disposed) {
          _ws?.close();
          return;
        }

        if (!_disposed) state = state.copyWith(isConnected: true);
        _reconnectAttempts = 0;

        final completer = Completer<void>();
        _wsSub = _ws!.listen(
          (raw) {
            if (raw is String) _handleMessage(raw);
          },
          onDone: () => completer.complete(),
          onError: (e) => completer.completeError(e),
          cancelOnError: true,
        );

        await completer.future; // WebSocket 닫힐 때까지 대기
        _wsSub = null;
      } catch (_) {
        // 연결 실패
      }

      if (!_disposed) state = state.copyWith(isConnected: false);

      _reconnectAttempts++;
      if (_reconnectAttempts > _maxReconnects) {
        if (!_disposed) state = state.copyWith(reconnectFailed: true);
        return;
      }

      // Exponential backoff: 1초, 2초, 4초
      if (!_disposed) {
        await Future.delayed(
            Duration(seconds: 1 << (_reconnectAttempts - 1)));
      }
    }
  }

  void _handleMessage(String raw) {
    if (_disposed) return;
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      if (data['type'] == 'message') {
        final msg = ChatMessageModel.fromJson(data, myUserId: _myUserId);
        state = state.copyWith(messages: [...state.messages, msg]);
      }
      // 'connected' type은 상태 변경 없이 무시 (isConnected는 connect()에서 관리)
    } catch (_) {
      // JSON 파싱 실패 무시
    }
  }

  void sendMessage(String content) {
    final trimmed = content.trim();
    if (trimmed.isEmpty || _ws == null) return;
    _ws!.add(jsonEncode({'type': 'message', 'content': trimmed}));
    // 낙관적 업데이트: 서버 broadcast 전에 로컬 추가
    // 서버가 같은 room으로 broadcast하면 같은 내용의 메시지 수신됨 → 중복 없음
    // (서버가 발신자에게도 broadcast하므로 _handleMessage에서 최종 반영)
  }

  @override
  void dispose() {
    _disposed = true;
    _wsSub?.cancel();
    _ws?.close();
    super.dispose();
  }
}

final chatRoomNotifierProvider =
    StateNotifierProvider.autoDispose.family<ChatRoomNotifier, ChatRoomState, String>(
  (ref, roomId) => ChatRoomNotifier(ref, roomId),
);
```

> **낙관적 업데이트 전략**: `sendMessage()` 호출 시 로컬에 즉시 추가하지 않고, 서버가 WebSocket으로 broadcast 돌려보낸 메시지를 `_handleMessage()`에서 추가합니다 (서버는 발신자에게도 broadcast함). 이렇게 하면 DB 저장 실패 시 메시지가 사라지지 않는 이점이 있습니다. 필요 시 순수 낙관적 업데이트로 변경 가능.

### 4. `mobile/lib/features/chat/presentation/chat_room_screen.dart` (NEW)

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/app_error.dart';
import '../../product/data/models/product_detail_model.dart';
import '../../product/domain/product_detail_provider.dart';
import '../domain/chat_room_notifier.dart';
import '../data/models/chat_models.dart';

class ChatRoomScreen extends ConsumerStatefulWidget {
  const ChatRoomScreen({
    super.key,
    required this.roomId,
    this.productId,
  });

  final String roomId;
  final String? productId;

  @override
  ConsumerState<ChatRoomScreen> createState() => _ChatRoomScreenState();
}

class _ChatRoomScreenState extends ConsumerState<ChatRoomScreen> {
  final _textController = TextEditingController();
  final _scrollController = ScrollController();
  bool _canSend = false;

  @override
  void initState() {
    super.initState();
    _textController.addListener(() {
      final newCanSend = _textController.text.trim().isNotEmpty;
      if (newCanSend != _canSend) setState(() => _canSend = newCanSend);
    });
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _send() {
    final content = _textController.text.trim();
    if (content.isEmpty) return;
    ref.read(chatRoomNotifierProvider(widget.roomId).notifier).sendMessage(content);
    _textController.clear();
    _scrollToBottom();
  }

  @override
  Widget build(BuildContext context) {
    final chatState = ref.watch(chatRoomNotifierProvider(widget.roomId));

    // 새 메시지 수신 시 스크롤 최하단
    ref.listen(chatRoomNotifierProvider(widget.roomId), (prev, next) {
      if (prev != null && next.messages.length > prev.messages.length) {
        _scrollToBottom();
      }
      // 재연결 실패 시 스낵바
      if (!(prev?.reconnectFailed ?? false) && next.reconnectFailed) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('오프라인 상태입니다. 네트워크를 확인해 주세요.')),
        );
      }
    });

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFFFF7043),
        foregroundColor: Colors.white,
        title: _ProductHeader(productId: widget.productId),
      ),
      body: Column(
        children: [
          // 메시지 목록
          Expanded(
            child: chatState.isLoadingHistory
                ? const Center(child: CircularProgressIndicator())
                : chatState.historyError != null
                    ? Center(child: Text('오류: ${chatState.historyError}'))
                    : chatState.messages.isEmpty
                        ? const Center(child: Text('메시지가 없습니다.'))
                        : ListView.builder(
                            controller: _scrollController,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            itemCount: chatState.messages.length,
                            itemBuilder: (_, i) =>
                                _MessageBubble(message: chatState.messages[i]),
                          ),
          ),
          // 연결 상태 표시
          if (!chatState.isConnected && !chatState.isLoadingHistory)
            Container(
              color: Colors.orange.shade100,
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    chatState.reconnectFailed ? '연결 실패' : '연결 중...',
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
          // 입력 영역
          _InputBar(
            controller: _textController,
            canSend: _canSend,
            onSend: _send,
          ),
        ],
      ),
    );
  }
}

class _ProductHeader extends ConsumerWidget {
  const _ProductHeader({this.productId});
  final String? productId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (productId == null) return const Text('채팅');

    final productAsync = ref.watch(productDetailProvider(productId!));
    return productAsync.when(
      loading: () => const Text('채팅'),
      error: (_, __) => const Text('채팅'),
      data: (product) => Row(
        children: [
          if (product.imageUrls.isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Image.network(
                product.imageUrls.first,
                width: 36,
                height: 36,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox(
                  width: 36,
                  height: 36,
                  child: Icon(Icons.image_not_supported, color: Colors.white),
                ),
              ),
            ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  product.title,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${product.price.toFormattedPrice()}원',
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
          if (product.isSold)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.grey,
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                '판매완료',
                style: TextStyle(fontSize: 10, color: Colors.white),
              ),
            ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});
  final ChatMessageModel message;

  @override
  Widget build(BuildContext context) {
    final isMe = message.isMe;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment:
            isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMe) ...[
            CircleAvatar(
              radius: 14,
              backgroundColor: Colors.grey.shade300,
              child: Text(
                message.senderNickname.isNotEmpty
                    ? message.senderNickname[0]
                    : '?',
                style: const TextStyle(fontSize: 12),
              ),
            ),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color:
                    isMe ? const Color(0xFFFF7043) : Colors.grey.shade200,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: isMe
                      ? const Radius.circular(16)
                      : const Radius.circular(4),
                  bottomRight: isMe
                      ? const Radius.circular(4)
                      : const Radius.circular(16),
                ),
              ),
              child: Text(
                message.content,
                style: TextStyle(
                  color: isMe ? Colors.white : Colors.black87,
                ),
              ),
            ),
          ),
          if (isMe) const SizedBox(width: 6),
        ],
      ),
    );
  }
}

class _InputBar extends StatelessWidget {
  const _InputBar({
    required this.controller,
    required this.canSend,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool canSend;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                decoration: InputDecoration(
                  hintText: '메시지를 입력하세요',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 8),
                  isDense: true,
                ),
                textInputAction: TextInputAction.send,
                onSubmitted: canSend ? (_) => onSend() : null,
              ),
            ),
            const SizedBox(width: 6),
            IconButton(
              onPressed: canSend ? onSend : null,
              icon: const Icon(Icons.send),
              style: IconButton.styleFrom(
                backgroundColor: canSend
                    ? const Color(0xFFFF7043)
                    : Colors.grey.shade300,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

> `toFormattedPrice()` — 기존 코드베이스에 이 extension이 있는지 먼저 확인. 없으면 `NumberFormat('#,###').format(price)` 사용 또는 단순히 `price.toString()` 사용.

### 5. 라우터 & 상품 상세 수정 요약

**`app_router.dart`**: import 추가 + GoRoute 교체 (위 기존 코드 컨텍스트 참조)

**`product_detail_screen.dart`**: 
- `_chatLoading` 필드 추가
- `_onChatTap()` → async 변환
- `_ActionBar` 위젯에 `isLoading` 파라미터 추가
- import: `chat_repository.dart` 추가

---

## 개발자 가드레일

### MUST 따라야 할 패턴

1. **`dart:io` WebSocket만 사용**: `web_socket_channel` 패키지 추가 금지. `import 'dart:io';` 만 사용.

2. **`AppConstants.wsBase` 추가**: `http://...` → `ws://...` 변환. `baseUrl.replaceFirst('http', 'ws')` — HTTPS 환경도 자동으로 `wss://` 변환됨.

3. **`@riverpod` 어노테이션 금지**: 프로젝트 전체 수동 Provider 패턴 사용. `StateNotifierProvider.autoDispose.family` 사용.

4. **`productDetailProvider` 재사용**: 채팅방 상품 헤더에 별도 API 호출 불필요. 기존 `productDetailProvider(productId)` watch.

5. **메시지 목록 표시 방향**: REST API는 최신순(DESC) → `reversed.toList()`로 오래된 것이 앞. `ListView`는 reverse 없이 정방향 — 상단에 오래된 메시지, 하단에 최신.

6. **`_disposed` 플래그**: `StateNotifier.dispose()` 후 async 콜백에서 `state =` 접근 금지. `if (!_disposed)` 체크 필수.

7. **WebSocket 재연결 backoff**: `1 << (attempt - 1)` → 1, 2, 4초. `_maxReconnects = 3`으로 최대 3회.

8. **`mounted` 체크**: UI 스낵바·navigation 호출 전 항상 `if (!mounted) return;`.

9. **`_ActionBar` 확장**: `onChat` 콜백이 이미 있음. `isChatLoading` 파라미터 추가하여 로딩 표시.

### MUST NOT

- `web_socket_channel` 패키지 사용 금지 (pubspec.yaml 수정 불필요)
- 동일 메시지 ID 중복 추가 방지 — 서버 broadcast 수신만으로 UI 업데이트 (낙관적 로컬 추가 없음)
- `context.go('/chat/...')` 사용 금지 → `context.push('/chat/...')` 사용 (뒤로가기 가능해야 함)
- `@override void dispose()` 없이 WebSocket 연결 유지 금지 — autoDispose이지만 명시적 close 필수

---

## 이전 스토리 학습사항

**Story 4.1 (REST API):**
- POST /chat-rooms → 201(신규) / 200(기존) 둘 다 `is_new` 포함 응답
- GET /chat-rooms/{id}/messages → items 배열, 최신순 DESC
- PATCH /chat-rooms/{id}/read → 읽음 처리 (채팅방 진입 시 호출 권장)

**Story 4.2 (WebSocket):**
- WS URL: `ws://host/ws/chat/{room_id}?token={jwt}`
- 연결 성공 시 `{"type": "connected", "room_id": "..."}` 수신
- close code 4001 = 인증 실패, 4003 = 비멤버
- 서버는 발신자에게도 broadcast → UI에서 낙관적 추가 + broadcast 수신 두 번 추가 주의

**Story 3.4 (Flutter 패턴):**
- `ConsumerStatefulWidget` + `ConsumerState`
- `ref.listen()` 패턴으로 state 변화 감지
- `ref.read(provider.notifier).method()` 으로 notifier 메서드 호출
- `mounted` 체크 위치: 모든 async gap 이후

**Story 3.2 (Flutter 등록 화면):**
- `price.toFormattedPrice()` — NumberFormat extension이 있을 수 있음 → 확인 필요
- AppBar 배경색: `const Color(0xFFFF7043)`
- AppBar 전경색: `Colors.white`

---

## Dev Agent Record

### Agent Model Used

claude-sonnet-4-6

### Debug Log References

- Lint: `_FakeChatNotifier` 테스트에서 `ProviderContainer()` → `Ref` 타입 오류. Riverpod `overrideWith` 콜백에서 `ref` 직접 전달하는 방식으로 변경 → `_FakeChatRepo` 패턴으로 전환
- Lint: `error: (_, __)` → `error: (_, _)` (unnecessary_underscores, Dart 3.x)
- Timer 누수: `pump()` 이후 WebSocket 재연결 타이머 pending → `pumpAndSettle(Duration(seconds: 10))`으로 모든 타이머 완료 처리

### Completion Notes List

- `constants.dart`: `wsBase` getter 추가 (http→ws, https→wss 자동 변환)
- `chat_models.dart`: `ChatRoomCreateResult`, `ChatMessageModel` (isMe 판별 포함)
- `chat_repository.dart`: createOrGetChatRoom / getMessages / markAsRead, `chatRepositoryProvider` (dioProvider)
- `chat_room_notifier.dart`: `StateNotifier.autoDispose.family`, `dart:io` WebSocket, 3회 재연결 backoff, dispose 안전성 (`_disposed` 플래그)
- `chat_room_screen.dart`: 상품 헤더 / 말풍선 UI / 입력바 (Key('send_button')) / 자동 스크롤 / reconnectFailed 오프라인 배너
- `app_router.dart`: `/chat/:roomId` placeholder → 실제 `ChatRoomScreen`
- `product_detail_screen.dart`: `_onChatTap()` async 변환, `_chatLoading` 상태, `_ActionBar.isChatLoading`
- 14개 신규 테스트 (6 model + 8 widget), 134/134 전체 통과, flutter analyze 이슈 없음

### File List

- mobile/lib/core/constants.dart (UPDATE — wsBase getter)
- mobile/lib/features/chat/data/models/chat_models.dart (NEW)
- mobile/lib/features/chat/data/chat_repository.dart (NEW)
- mobile/lib/features/chat/domain/chat_room_notifier.dart (NEW)
- mobile/lib/features/chat/presentation/chat_room_screen.dart (NEW)
- mobile/lib/core/router/app_router.dart (UPDATE — ChatRoomScreen 교체)
- mobile/lib/features/product/presentation/product_detail_screen.dart (UPDATE — _onChatTap 구현)
- mobile/test/features/chat/chat_repository_test.dart (NEW)
- mobile/test/features/chat/chat_room_screen_test.dart (NEW)
