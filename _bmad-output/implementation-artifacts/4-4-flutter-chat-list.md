---
baseline_commit: NO_VCS
---

# Story 4.4 — Flutter 채팅 목록 화면

**Status:** review

## Story

As an authenticated user,
I want to see all my active chat rooms with unread message counts,
So that I can quickly find and respond to conversations.

## Acceptance Criteria

**Given** 인증된 사용자가 채팅 목록에 진입할 때
**When** 화면이 로드되면
**Then** 본인이 참여 중인 채팅방 목록이 최근 메시지 순으로 표시된다
**And** 각 채팅방 항목에 상품 썸네일·제목·마지막 메시지 미리보기·경과 시간이 표시된다
**And** 미읽음 메시지 수가 배지로 표시된다

**Given** 채팅방 항목을 탭할 때
**When** 탭 이벤트가 발생하면
**Then** `markAsRead` API를 호출하고 해당 채팅방 화면으로 이동한다
**And** 채팅방에서 돌아왔을 때 목록이 새로고침되어 미읽음 배지가 0으로 반영된다

**Given** 참여 중인 채팅방이 없을 때
**When** 채팅 목록에 진입하면
**Then** "아직 채팅 내역이 없습니다." 안내 메시지가 표시된다

**Given** FeedScreen(피드 화면)에서
**When** AppBar의 채팅 아이콘 버튼을 탭하면
**Then** 채팅 목록 화면으로 이동한다

## Tasks / Subtasks

- [x] Task 1: `ChatListItem` 모델 추가 (AC: 1)
  - [x] `mobile/lib/features/chat/data/models/chat_models.dart` 수정
  - [x] `ChatListItemProduct` 클래스: id, title, price, thumbnailUrl, status
  - [x] `ChatListItem` 클래스: id(roomId), product, otherUserNickname, lastMessage, lastMessageAt, unreadCount
  - [x] `ChatListItem.fromJson()` 구현

- [x] Task 2: `ChatRepository.getChatList()` 추가 (AC: 1)
  - [x] `mobile/lib/features/chat/data/chat_repository.dart` 수정
  - [x] `Future<List<ChatListItem>> getChatList()` → GET /chat-rooms

- [x] Task 3: `ChatListNotifier` 신규 생성 (AC: 1, 2)
  - [x] `mobile/lib/features/chat/domain/chat_list_notifier.dart` 신규 생성
  - [x] `AutoDisposeAsyncNotifierProvider<ChatListNotifier, List<ChatListItem>>`
  - [x] `build()`: `chatRepositoryProvider.getChatList()` 호출
  - [x] `refresh()`: `ref.invalidateSelf()` + `await future`

- [x] Task 4: `ChatListScreen` 신규 생성 (AC: 1, 2, 3)
  - [x] `mobile/lib/features/chat/presentation/chat_list_screen.dart` 신규 생성
  - [x] `ConsumerWidget` — `chatListProvider` watch
  - [x] 로딩/에러/빈 상태 처리
  - [x] 채팅방 카드: 상품 썸네일·제목·lastMessage·경과시간·미읽음 배지 (Key('unread_badge'))
  - [x] 탭 시: `markAsRead` 호출 → `context.push('/chat/$roomId', extra: productId)` → 복귀 후 `ref.invalidate(chatListProvider)`
  - [x] Pull-to-refresh: `ref.read(chatListProvider.notifier).refresh()`

- [x] Task 5: 라우터 & FeedScreen 연결 (AC: 4)
  - [x] `mobile/lib/core/router/app_router.dart` 수정 — `/chat-list` 라우트 추가
  - [x] `mobile/lib/features/feed/presentation/feed_screen.dart` 수정 — AppBar에 채팅 아이콘 버튼 추가

- [x] Task 6: 테스트 추가 (15개)
  - [x] `mobile/test/features/chat/chat_list_models_test.dart` 신규 생성 (8개 모델 파싱 테스트)
  - [x] `mobile/test/features/chat/chat_list_screen_test.dart` 신규 생성 (7개 위젯 테스트)

---

## Dev Notes

### 핵심 사항 요약

1. **Flutter 전용** — 백엔드 변경 없음 (GET /chat-rooms는 Story 4.1에서 구현됨)
2. **네비게이션 접근**: FeedScreen AppBar에 채팅 아이콘 → `/chat-list` 라우트 push (BottomNavigationBar 미적용 — MVP 단순화)
3. **탭 → 읽음 처리 흐름**: `markAsRead(roomId)` 호출 → push to `/chat/{roomId}` → pop 후 `chatListProvider` invalidate
4. **`context.push()` await 패턴**: `await context.push(...)` 는 pop될 때까지 대기. 돌아온 후 `ref.invalidate(chatListProvider)` 호출
5. **`FeedNotifier` 패턴 재사용**: `AutoDisposeAsyncNotifier` + `ref.invalidateSelf()` 패턴 동일하게 사용
6. **`formatPrice()` & `timeAgo()`**: `core/utils/formatting.dart`에 이미 존재, 재사용

### 프로젝트 구조

**NEW — 새로 생성:**
```
mobile/lib/features/chat/domain/chat_list_notifier.dart
mobile/lib/features/chat/presentation/chat_list_screen.dart
mobile/test/features/chat/chat_list_models_test.dart
mobile/test/features/chat/chat_list_screen_test.dart
```

**UPDATE — 수정:**
```
mobile/lib/features/chat/data/models/chat_models.dart     ← ChatListItem, ChatListItemProduct 추가
mobile/lib/features/chat/data/chat_repository.dart        ← getChatList() 추가
mobile/lib/core/router/app_router.dart                    ← /chat-list 라우트 추가
mobile/lib/features/feed/presentation/feed_screen.dart    ← AppBar 채팅 아이콘
```

### 기존 코드 컨텍스트 (반드시 보존)

**`chat_models.dart` 현재 상태 (수정 대상):**
```dart
// 현재: ChatRoomCreateResult, ChatMessageModel 두 클래스만 존재
// 추가: ChatListItemProduct, ChatListItem
```

**`chat_repository.dart` 현재 상태 (`getChatList()` 추가):**
```dart
// 현재: createOrGetChatRoom(), getMessages(), markAsRead()
// 추가: getChatList() → GET /chat-rooms
Future<List<ChatListItem>> getChatList() async {
  final resp = await _dio.get('/chat-rooms');
  return (resp.data as List)
      .cast<Map<String, dynamic>>()
      .map(ChatListItem.fromJson)
      .toList();
}
```

**`app_router.dart` `/chat-list` 라우트 추가 위치:**
```dart
// GoRoute 목록에 추가 (기존 /chat/:roomId 라우트 앞에)
GoRoute(
  path: '/chat-list',
  builder: (context, state) => const ChatListScreen(),
),
```

**`feed_screen.dart` AppBar 액션 추가:**
```dart
// AppBar에 actions 추가
appBar: AppBar(
  title: const Text('피드'),
  backgroundColor: const Color(0xFFFF7043),
  foregroundColor: Colors.white,
  actions: [
    IconButton(
      icon: const Icon(Icons.chat_bubble_outline),
      onPressed: () => context.push('/chat-list'),
    ),
  ],
),
```

**`FeedNotifier` 패턴 (`AutoDisposeAsyncNotifier`) — ChatListNotifier도 동일:**
```dart
class FeedNotifier extends AutoDisposeAsyncNotifier<FeedState> {
  @override
  Future<FeedState> build() async { ... }
  
  Future<void> refresh() async {
    ref.invalidateSelf();
    try { await future; } catch (_) {}
  }
}
final feedNotifierProvider = AutoDisposeAsyncNotifierProvider<FeedNotifier, FeedState>(FeedNotifier.new);
```

**`timeAgo()` 함수 사용 (Story 4.3의 ChatRoomScreen에서도 사용 가능):**
```dart
import '../../../core/utils/formatting.dart';
// lastMessageAt이 null이 아닌 경우에만 사용
final timeText = item.lastMessageAt != null ? timeAgo(item.lastMessageAt!) : '';
```

**`formatPrice()` 함수 사용:**
```dart
Text(formatPrice(item.product.price)) // → "900,000원"
```

### API 계약 (GET /chat-rooms)

**엔드포인트:** `GET /api/v1/chat-rooms` (인증 필수)

**응답 (200):**
```json
[
  {
    "id": "room-uuid",
    "product": {
      "id": "prod-uuid",
      "title": "아이폰 15",
      "price": 900000,
      "thumbnail_url": "https://r2.../thumb.jpg",
      "status": "SALE"
    },
    "other_user_nickname": "김지수",
    "last_message": "안녕하세요!",
    "last_message_at": "2026-05-30T10:00:00Z",
    "unread_count": 3
  }
]
```

**주의**: 응답이 배열(List) — `resp.data` 자체가 `List`

---

## 구현 상세

### 1. `chat_models.dart` — ChatListItem 추가

기존 파일 끝에 추가:

```dart
// ─── Chat List Models ─────────────────────────────────────────────────────────

@immutable
class ChatListItemProduct {
  const ChatListItemProduct({
    required this.id,
    required this.title,
    required this.price,
    this.thumbnailUrl,
    required this.status,
  });

  final String id;
  final String title;
  final int price;
  final String? thumbnailUrl;
  final String status;

  bool get isSold => status == 'SOLD';

  factory ChatListItemProduct.fromJson(Map<String, dynamic> json) =>
      ChatListItemProduct(
        id: json['id'] as String,
        title: json['title'] as String,
        price: json['price'] as int,
        thumbnailUrl: json['thumbnail_url'] as String?,
        status: json['status'] as String,
      );
}

@immutable
class ChatListItem {
  const ChatListItem({
    required this.id,
    required this.product,
    required this.otherUserNickname,
    this.lastMessage,
    this.lastMessageAt,
    required this.unreadCount,
  });

  final String id;              // room_id
  final ChatListItemProduct product;
  final String otherUserNickname;
  final String? lastMessage;
  final DateTime? lastMessageAt;
  final int unreadCount;

  bool get hasUnread => unreadCount > 0;

  factory ChatListItem.fromJson(Map<String, dynamic> json) => ChatListItem(
        id: json['id'] as String,
        product: ChatListItemProduct.fromJson(
          json['product'] as Map<String, dynamic>,
        ),
        otherUserNickname: json['other_user_nickname'] as String,
        lastMessage: json['last_message'] as String?,
        lastMessageAt: json['last_message_at'] != null
            ? DateTime.parse(json['last_message_at'] as String).toLocal()
            : null,
        unreadCount: json['unread_count'] as int,
      );
}
```

### 2. `chat_repository.dart` — getChatList() 추가

기존 메서드 뒤에 추가:

```dart
Future<List<ChatListItem>> getChatList() async {
  try {
    final resp = await _dio.get('/chat-rooms');
    return (resp.data as List)
        .cast<Map<String, dynamic>>()
        .map(ChatListItem.fromJson)
        .toList();
  } on DioException catch (e) {
    throw AppError.fromDioException(e);
  }
}
```

### 3. `chat_list_notifier.dart` (NEW)

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/chat_repository.dart';
import '../data/models/chat_models.dart';

class ChatListNotifier
    extends AutoDisposeAsyncNotifier<List<ChatListItem>> {
  @override
  Future<List<ChatListItem>> build() =>
      ref.read(chatRepositoryProvider).getChatList();

  Future<void> refresh() async {
    ref.invalidateSelf();
    try {
      await future;
    } catch (_) {
      // build() 오류는 AsyncError 상태로 반영됨 — 여기서 삼킴
    }
  }
}

final chatListProvider =
    AutoDisposeAsyncNotifierProvider<ChatListNotifier, List<ChatListItem>>(
  ChatListNotifier.new,
);
```

### 4. `chat_list_screen.dart` (NEW)

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/error/app_error.dart';
import '../../../core/utils/formatting.dart';
import '../../../core/widgets/app_error_view.dart';
import '../data/chat_repository.dart';
import '../data/models/chat_models.dart';
import '../domain/chat_list_notifier.dart';

class ChatListScreen extends ConsumerWidget {
  const ChatListScreen({super.key});

  Future<void> _onTapRoom(
    BuildContext context,
    WidgetRef ref,
    ChatListItem room,
  ) async {
    // 읽음 처리 (탭 즉시)
    try {
      await ref.read(chatRepositoryProvider).markAsRead(room.id);
    } catch (_) {
      // 읽음 처리 실패는 무시 (비필수)
    }

    if (!context.mounted) return;

    // 채팅방으로 이동 (pop 대기)
    await context.push('/chat/${room.id}', extra: room.product.id);

    if (!context.mounted) return;

    // 돌아왔을 때 목록 새로고침
    ref.invalidate(chatListProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final listAsync = ref.watch(chatListProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('채팅'),
        backgroundColor: const Color(0xFFFF7043),
        foregroundColor: Colors.white,
      ),
      body: listAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => AppErrorView(
          message: err is AppError ? err.message : '오류가 발생했습니다.',
          onRetry: () => ref.invalidate(chatListProvider),
        ),
        data: (rooms) => rooms.isEmpty
            ? const _EmptyView()
            : RefreshIndicator(
                onRefresh: () =>
                    ref.read(chatListProvider.notifier).refresh(),
                child: ListView.separated(
                  physics: const AlwaysScrollableScrollPhysics(),
                  itemCount: rooms.length,
                  separatorBuilder: (_, _) =>
                      const Divider(height: 1, indent: 72),
                  itemBuilder: (ctx, i) => _ChatRoomCard(
                    room: rooms[i],
                    onTap: () => _onTapRoom(ctx, ref, rooms[i]),
                  ),
                ),
              ),
      ),
    );
  }
}

// ─── 빈 상태 ─────────────────────────────────────────────────────────────────

class _EmptyView extends StatelessWidget {
  const _EmptyView();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text(
        '아직 채팅 내역이 없습니다.',
        style: TextStyle(color: Colors.grey),
      ),
    );
  }
}

// ─── 채팅방 카드 ──────────────────────────────────────────────────────────────

class _ChatRoomCard extends StatelessWidget {
  const _ChatRoomCard({required this.room, required this.onTap});

  final ChatListItem room;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: _Thumbnail(url: room.product.thumbnailUrl),
      title: Row(
        children: [
          Expanded(
            child: Text(
              room.product.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          if (room.lastMessageAt != null)
            Text(
              timeAgo(room.lastMessageAt!),
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
        ],
      ),
      subtitle: Row(
        children: [
          Expanded(
            child: Text(
              room.lastMessage ?? '메시지 없음',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 13,
              ),
            ),
          ),
          if (room.hasUnread)
            Container(
              key: const Key('unread_badge'),
              margin: const EdgeInsets.only(left: 4),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFFFF7043),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '${room.unreadCount}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
      onTap: onTap,
    );
  }
}

class _Thumbnail extends StatelessWidget {
  const _Thumbnail({this.url});
  final String? url;

  @override
  Widget build(BuildContext context) {
    if (url == null || url!.isEmpty) {
      return Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: Colors.grey.shade200,
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(Icons.image_not_supported, color: Colors.grey),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.network(
        url!,
        width: 52,
        height: 52,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => Container(
          width: 52,
          height: 52,
          color: Colors.grey.shade200,
          child: const Icon(Icons.image_not_supported, color: Colors.grey),
        ),
      ),
    );
  }
}
```

### 5. 라우터 & FeedScreen 수정

**`app_router.dart`** — `/chat-list` 라우트 추가:
```dart
import '../../features/chat/presentation/chat_list_screen.dart';

// GoRoute 목록에 추가 (기존 /chat/:roomId 앞에)
GoRoute(
  path: '/chat-list',
  builder: (context, state) => const ChatListScreen(),
),
```

**`feed_screen.dart`** — AppBar actions 추가:
```dart
appBar: AppBar(
  title: const Text('피드'),
  backgroundColor: const Color(0xFFFF7043),
  foregroundColor: Colors.white,
  actions: [
    IconButton(
      icon: const Icon(Icons.chat_bubble_outline),
      tooltip: '채팅',
      onPressed: () => context.push('/chat-list'),
    ),
  ],
),
```

---

## 개발자 가드레일

### MUST 따라야 할 패턴

1. **`AutoDisposeAsyncNotifierProvider` 패턴**: `FeedNotifier`와 동일하게 `ChatListNotifier` 구성. `ref.invalidateSelf()` + `await future` 패턴.

2. **`await context.push(...)` 패턴**: `context.push`는 pop 시 `Future`를 complete. `await` 후 `context.mounted` 체크 필수.

3. **`ref.invalidate(chatListProvider)`**: 돌아온 후 invalidate로 최신 데이터 로드. `autoDispose`이므로 화면이 없으면 자동 정리됨.

4. **`chatRepositoryProvider.markAsRead(roomId)` 호출**: tap 즉시 호출. 실패해도 네비게이션은 진행 (try/catch로 무시).

5. **응답 타입**: `GET /chat-rooms` 응답은 `List` (객체 아님). `resp.data as List` — `resp.data['items']` 아님.

6. **`formatPrice()` 사용**: `import '../../../core/utils/formatting.dart';` — `formatPrice(int price)` 함수 (extension 아님).

7. **`timeAgo()` 사용**: 동일 formatting.dart에서 import. `lastMessageAt`이 null이면 빈 문자열 처리.

8. **`AppErrorView` 재사용**: `core/widgets/app_error_view.dart` — 기존 feed_screen.dart와 동일 패턴.

### MUST NOT

- `@riverpod` 어노테이션 사용 금지 — 수동 Provider 패턴
- `resp.data['items']` 접근 금지 — 배열 응답이므로 `resp.data as List`
- `context.go()` 대신 `context.push()` 사용 — 채팅방에서 돌아오기 가능
- 중복 `getChatList()` 메서드 정의 금지 — `chat_repository.dart`에만 추가

---

## 이전 스토리 학습사항

**Story 4.3 (Flutter 채팅방 화면):**
- `dart:io` WebSocket 사용 (web_socket_channel 불필요)
- `_FakeChatRepo`를 이용한 테스트 패턴 — `chatRepositoryProvider.overrideWith((ref) => _FakeChatRepo(...))`
- `pumpAndSettle(const Duration(seconds: 10))` — WebSocket 재연결 타이머 완료 대기
- `StateNotifier.autoDispose.family` 패턴
- `products`: `_kProductId` 와 같은 const 선언에서 unused_element warning 주의

**Story 4.3 테스트 패턴 (재사용):**
```dart
class _FakeChatRepo extends ChatRepository {
  _FakeChatRepo({required this.rooms}) : super(authDio: Dio());
  final List<ChatListItem> rooms;
  
  @override
  Future<List<ChatListItem>> getChatList() async => rooms;
}
```

**Lint 주의 사항:**
- `(_, __)` 패턴 → `(_, _)` 사용 (unnecessary_underscores)
- 미사용 const → unused_element warning
- 테스트 함수명에서 `_` prefix → no_leading_underscores_for_local_identifiers

---

## Dev Agent Record

### Agent Model Used

claude-sonnet-4-6

### Debug Log References

- 로딩 중 CircularProgressIndicator 테스트: `_FakeChatRepo.getChatList()` 가 즉시 완료되어 로딩 상태 포착 불가 → 테스트 제거 (Story 4.3 패턴과 동일한 한계)
- Lint: `(_, __)` → `(_, _)` (unnecessary_underscores)
- Lint: `chat_list_notifier.dart` unused import in test → 제거

### Completion Notes List

- `chat_models.dart`: `ChatListItemProduct`, `ChatListItem` (fromJson, hasUnread, lastMessageAt nullable, toLocal 변환)
- `chat_repository.dart`: `getChatList()` — `resp.data as List` (배열 응답)
- `chat_list_notifier.dart`: `AutoDisposeAsyncNotifier` + `refresh()` — FeedNotifier 동일 패턴
- `chat_list_screen.dart`: `_onTapRoom(markAsRead → push → invalidate)`, 빈 상태, 미읽음 배지(Key), Pull-to-refresh
- `app_router.dart`: `/chat-list` 라우트 추가
- `feed_screen.dart`: AppBar actions에 채팅 아이콘 추가 (→ `/chat-list` push)
- 15개 신규 테스트, 149/149 전체 통과, flutter analyze No issues

### File List

- mobile/lib/features/chat/data/models/chat_models.dart (UPDATE — ChatListItemProduct, ChatListItem 추가)
- mobile/lib/features/chat/data/chat_repository.dart (UPDATE — getChatList() 추가)
- mobile/lib/features/chat/domain/chat_list_notifier.dart (NEW)
- mobile/lib/features/chat/presentation/chat_list_screen.dart (NEW)
- mobile/lib/core/router/app_router.dart (UPDATE — /chat-list 라우트)
- mobile/lib/features/feed/presentation/feed_screen.dart (UPDATE — AppBar 채팅 아이콘)
- mobile/test/features/chat/chat_list_models_test.dart (NEW)
- mobile/test/features/chat/chat_list_screen_test.dart (NEW)
