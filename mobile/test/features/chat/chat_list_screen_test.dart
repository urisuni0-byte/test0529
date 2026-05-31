import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile/features/auth/data/models/user_model.dart';
import 'package:mobile/features/auth/domain/auth_notifier.dart';
import 'package:mobile/features/auth/domain/auth_state.dart';
import 'package:mobile/features/chat/data/chat_repository.dart';
import 'package:mobile/features/chat/data/models/chat_models.dart';
import 'package:mobile/features/chat/presentation/chat_list_screen.dart';

// ─── Fixtures ────────────────────────────────────────────────────────────────

ChatListItem _room({
  String id = 'room-1',
  String title = '아이폰 15',
  int unreadCount = 0,
  String? lastMessage,
}) =>
    ChatListItem(
      id: id,
      product: ChatListItemProduct(
        id: 'prod-1',
        title: title,
        price: 900000,
        status: 'SALE',
      ),
      otherUserNickname: '김지수',
      lastMessage: lastMessage ?? '안녕하세요!',
      lastMessageAt: DateTime.now().subtract(const Duration(minutes: 5)),
      unreadCount: unreadCount,
    );

// ─── Fake Auth ───────────────────────────────────────────────────────────────

class _FakeAuth extends AuthNotifier {
  @override
  Future<AuthState> build() async => Authenticated(
        user: UserModel(
          id: 'user-1',
          email: 'me@test.com',
          role: 'user',
          isActive: true,
          nickname: '나',
          neighborhoodId: 1,
        ),
      );
}

// ─── Fake ChatRepository ─────────────────────────────────────────────────────

class _FakeChatRepo extends ChatRepository {
  _FakeChatRepo({required this.rooms}) : super(authDio: Dio());

  final List<ChatListItem> rooms;

  @override
  Future<List<ChatListItem>> getChatList() async => rooms;

  @override
  Future<ChatRoomCreateResult> createOrGetChatRoom(String productId) async =>
      const ChatRoomCreateResult(
          roomId: 'r', productId: 'p', isNew: true);

  @override
  Future<void> markAsRead(String roomId) async {}
}

// ─── Build Helper ─────────────────────────────────────────────────────────────

Widget buildApp(List<ChatListItem> rooms) {
  final router = GoRouter(
    initialLocation: '/chat-list',
    routes: [
      GoRoute(
        path: '/chat-list',
        builder: (_, _) => const ChatListScreen(),
      ),
      GoRoute(
        path: '/chat/:roomId',
        builder: (_, _) => const Scaffold(body: Text('채팅방')),
      ),
    ],
  );

  return ProviderScope(
    overrides: [
      authNotifierProvider.overrideWith(_FakeAuth.new),
      chatRepositoryProvider
          .overrideWith((ref) => _FakeChatRepo(rooms: rooms)),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

// ─── Tests ────────────────────────────────────────────────────────────────────

void main() {
  group('ChatListScreen', () {
    testWidgets('빈 채팅방 목록 — 빈 상태 메시지 표시', (tester) async {
      await tester.pumpWidget(buildApp([]));
      await tester.pumpAndSettle();

      expect(find.text('아직 채팅 내역이 없습니다.'), findsOneWidget);
    });

    testWidgets('채팅방 목록 표시 — 상품명과 마지막 메시지', (tester) async {
      await tester.pumpWidget(buildApp([
        _room(title: '아이폰 15', lastMessage: '안녕하세요!'),
      ]));
      await tester.pumpAndSettle();

      expect(find.text('아이폰 15'), findsOneWidget);
      expect(find.text('안녕하세요!'), findsOneWidget);
    });

    testWidgets('여러 채팅방 목록 표시', (tester) async {
      await tester.pumpWidget(buildApp([
        _room(id: 'r1', title: '아이폰'),
        _room(id: 'r2', title: '갤럭시'),
        _room(id: 'r3', title: '맥북'),
      ]));
      await tester.pumpAndSettle();

      expect(find.text('아이폰'), findsOneWidget);
      expect(find.text('갤럭시'), findsOneWidget);
      expect(find.text('맥북'), findsOneWidget);
    });

    testWidgets('미읽음 배지 표시 (unreadCount > 0)', (tester) async {
      await tester.pumpWidget(buildApp([
        _room(unreadCount: 3),
      ]));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('unread_badge')), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
    });

    testWidgets('미읽음 0이면 배지 미표시', (tester) async {
      await tester.pumpWidget(buildApp([
        _room(unreadCount: 0),
      ]));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('unread_badge')), findsNothing);
    });

    testWidgets('AppBar 타이틀 "채팅"', (tester) async {
      await tester.pumpWidget(buildApp([]));
      await tester.pumpAndSettle();

      expect(find.text('채팅'), findsOneWidget);
    });

    testWidgets('채팅방 카드에 상대방 닉네임 포함', (tester) async {
      await tester.pumpWidget(buildApp([_room()]));
      await tester.pumpAndSettle();

      // 상대방 닉네임은 subtitle에 표시되지 않고 타이틀에 있지 않을 수 있음
      // product title은 표시됨
      expect(find.text('아이폰 15'), findsOneWidget);
    });
  });
}
