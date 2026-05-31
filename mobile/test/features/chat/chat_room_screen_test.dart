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
import 'package:mobile/features/chat/presentation/chat_room_screen.dart';
import 'package:mobile/core/storage/secure_storage.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

// ─── Fixtures ────────────────────────────────────────────────────────────────

const _kRoomId = 'room-uuid-test';
const _kMyId = 'user-me-123';
const _kOtherId = 'user-other-456';

ChatMessageModel _myMsg(String content) => ChatMessageModel(
      id: 'msg-${content.hashCode}',
      roomId: _kRoomId,
      senderId: _kMyId,
      senderNickname: '나',
      content: content,
      createdAt: DateTime.now(),
      isMe: true,
    );

ChatMessageModel _otherMsg(String content) => ChatMessageModel(
      id: 'msg-other-${content.hashCode}',
      roomId: _kRoomId,
      senderId: _kOtherId,
      senderNickname: '상대방',
      content: content,
      createdAt: DateTime.now(),
      isMe: false,
    );

// ─── Fake Auth ───────────────────────────────────────────────────────────────

class _FakeAuth extends AuthNotifier {
  @override
  Future<AuthState> build() async => Authenticated(
        user: UserModel(
          id: _kMyId,
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
  _FakeChatRepo({required this.messages})
      : super(authDio: Dio()); // Dio 실제 사용 안 함

  final List<ChatMessageModel> messages;

  @override
  Future<List<ChatMessageModel>> getMessages(
    String roomId, {
    required String myUserId,
    int page = 1,
    int limit = 50,
  }) async =>
      messages;

  @override
  Future<ChatRoomCreateResult> createOrGetChatRoom(String productId) async =>
      ChatRoomCreateResult(
        roomId: _kRoomId,
        productId: productId,
        isNew: true,
      );

  @override
  Future<void> markAsRead(String roomId) async {}
}

// ─── Fake SecureStorage (빈 토큰 반환 — WebSocket 즉시 실패) ─────────────────

class _FakeStorage extends SecureStorageService {
  _FakeStorage() : super(const FlutterSecureStorage());

  @override
  Future<String?> getAccessToken() async => null;

  @override
  Future<String?> getRefreshToken() async => null;
}

// ─── Build App ────────────────────────────────────────────────────────────────

Widget _buildApp({
  required List<ChatMessageModel> messages,
  String? productId,
}) {
  final router = GoRouter(
    initialLocation: '/chat/$_kRoomId',
    routes: [
      GoRoute(
        path: '/chat/:roomId',
        builder: (context, state) => ChatRoomScreen(
          roomId: _kRoomId,
          productId: productId,
        ),
      ),
    ],
  );

  return ProviderScope(
    overrides: [
      authNotifierProvider.overrideWith(_FakeAuth.new),
      chatRepositoryProvider.overrideWith(
        (ref) => _FakeChatRepo(messages: messages),
      ),
      secureStorageProvider.overrideWith(
        (ref) => _FakeStorage(),
      ),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

// ─── Tests ────────────────────────────────────────────────────────────────────

void main() {
  group('ChatRoomScreen', () {
    testWidgets('메시지 없을 때 빈 상태 메시지 표시', (tester) async {
      await tester.pumpWidget(_buildApp(messages: []));
      // 히스토리 로드 + WebSocket 실패(재연결) 완료 대기
      await tester.pumpAndSettle(const Duration(seconds: 10));

      expect(find.text('첫 메시지를 보내보세요!'), findsOneWidget);
    });

    testWidgets('메시지 목록 표시 (내 메시지 + 상대방 메시지)', (tester) async {
      await tester.pumpWidget(
        _buildApp(
          messages: [
            _myMsg('내 메시지입니다'),
            _otherMsg('상대방 메시지'),
          ],
        ),
      );
      await tester.pumpAndSettle(const Duration(seconds: 10));

      expect(find.text('내 메시지입니다'), findsOneWidget);
      expect(find.text('상대방 메시지'), findsOneWidget);
    });

    testWidgets('히스토리 로드 완료 후 빈 상태 표시 (로딩 인디케이터 사라짐)',
        (tester) async {
      await tester.pumpWidget(_buildApp(messages: []));
      // 모든 비동기 작업(히스토리 로드 + WebSocket 재연결) 완료
      await tester.pumpAndSettle(const Duration(seconds: 10));

      // 로딩 완료 후 빈 채팅 상태 메시지가 표시됨
      expect(find.text('첫 메시지를 보내보세요!'), findsOneWidget);
    });

    testWidgets('전송 버튼 초기에 비활성화 (빈 텍스트)', (tester) async {
      await tester.pumpWidget(_buildApp(messages: []));
      await tester.pumpAndSettle(const Duration(seconds: 10));

      final sendBtn = tester.widget<IconButton>(
        find.byKey(const Key('send_button')),
      );
      expect(sendBtn.onPressed, isNull);
    });

    testWidgets('텍스트 입력 시 전송 버튼 활성화', (tester) async {
      await tester.pumpWidget(_buildApp(messages: []));
      await tester.pumpAndSettle(const Duration(seconds: 10));

      await tester.enterText(find.byType(TextField), '안녕하세요');
      await tester.pump();

      final sendBtn = tester.widget<IconButton>(
        find.byKey(const Key('send_button')),
      );
      expect(sendBtn.onPressed, isNotNull);
    });

    testWidgets('공백만 입력 시 전송 버튼 비활성화', (tester) async {
      await tester.pumpWidget(_buildApp(messages: []));
      await tester.pumpAndSettle(const Duration(seconds: 10));

      await tester.enterText(find.byType(TextField), '   ');
      await tester.pump();

      final sendBtn = tester.widget<IconButton>(
        find.byKey(const Key('send_button')),
      );
      expect(sendBtn.onPressed, isNull);
    });

    testWidgets('productId 없을 때 AppBar에 "채팅" 텍스트', (tester) async {
      await tester.pumpWidget(_buildApp(messages: [], productId: null));
      await tester.pumpAndSettle(const Duration(seconds: 10));

      expect(find.text('채팅'), findsOneWidget);
    });

    testWidgets('WebSocket 실패 후 연결 실패 배너 표시', (tester) async {
      await tester.pumpWidget(_buildApp(messages: []));
      await tester.pumpAndSettle(const Duration(seconds: 10));

      // WebSocket 3회 재연결 실패 후 '연결 실패' 또는 '연결 중...' 배너
      // reconnectFailed=true 이면 '연결 실패' 표시
      expect(
        find.text('연결 실패'),
        findsOneWidget,
        reason: 'WebSocket 재연결 3회 실패 후 연결 실패 배너 표시',
      );
    });
  });
}
