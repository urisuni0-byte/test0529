import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/core/network/api_client.dart';
import 'package:mobile/features/auth/domain/auth_notifier.dart';
import 'package:mobile/features/auth/domain/auth_state.dart';
import 'package:mobile/features/auth/data/models/user_model.dart';
import 'package:mobile/features/auth/presentation/settings_screen.dart';

// ─── Fake AuthNotifier ────────────────────────────────────────────────────────

class _FakeAuthNotifier extends AuthNotifier {
  _FakeAuthNotifier({this._nickname});

  final String? _nickname;

  @override
  Future<AuthState> build() async => Authenticated(
        user: UserModel(
          id: 'test-id',
          email: 'test@example.com',
          role: 'user',
          isActive: true,
          nickname: _nickname ?? '테스트유저',
        ),
      );

  @override
  Future<void> signOut() async {
    state = const AsyncData(Unauthenticated());
  }
}

// ─── Fake Dio ─────────────────────────────────────────────────────────────────

class _FakeDio extends Fake implements Dio {
  _FakeDio({this.shouldFail = false});

  final bool shouldFail;
  Map<String, dynamic>? lastPatchData;

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
    lastPatchData = data as Map<String, dynamic>?;
    if (shouldFail) {
      throw DioException(
        requestOptions: RequestOptions(path: path),
        message: '네트워크 오류',
      );
    }
    return Response<T>(
      requestOptions: RequestOptions(path: path),
      statusCode: 200,
      data: {'nickname': lastPatchData?['nickname']} as T,
    );
  }
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

Widget _buildApp({
  String? nickname,
  _FakeDio? fakeDio,
  bool dioShouldFail = false,
}) {
  final dio = fakeDio ?? _FakeDio(shouldFail: dioShouldFail);
  return ProviderScope(
    overrides: [
      authNotifierProvider
          .overrideWith(() => _FakeAuthNotifier(nickname: nickname)),
      dioProvider.overrideWithValue(dio),
    ],
    child: const MaterialApp(home: SettingsScreen()),
  );
}

// ─── Tests ────────────────────────────────────────────────────────────────────

void main() {
  group('SettingsScreen', () {
    testWidgets('renders current nickname in display mode', (tester) async {
      await tester.pumpWidget(_buildApp(nickname: '홍길동'));
      await tester.pump();

      expect(find.text('홍길동'), findsOneWidget);
      expect(find.text('편집'), findsOneWidget);
      // Edit text field should NOT be visible in display mode
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('shows edit text field with current nickname when edit button tapped',
        (tester) async {
      await tester.pumpWidget(_buildApp(nickname: '홍길동'));
      await tester.pump();

      await tester.tap(find.text('편집'));
      await tester.pump();

      expect(find.byType(TextField), findsOneWidget);
      // TextField should be pre-filled with current nickname
      final tf = tester.widget<TextField>(find.byType(TextField));
      expect(tf.controller?.text, '홍길동');
    });

    testWidgets('save button disabled when nickname is invalid (too short)',
        (tester) async {
      await tester.pumpWidget(_buildApp(nickname: '홍길동'));
      await tester.pump();

      await tester.tap(find.text('편집'));
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'a');
      await tester.pump();

      expect(find.text('닉네임은 2자 이상이어야 합니다.'), findsOneWidget);
      final btn = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, '저장'),
      );
      expect(btn.onPressed, isNull,
          reason: 'Save button should be disabled for too-short nickname');
    });

    testWidgets('save button disabled for nickname with special characters',
        (tester) async {
      await tester.pumpWidget(_buildApp(nickname: '홍길동'));
      await tester.pump();

      await tester.tap(find.text('편집'));
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'abc!@#');
      await tester.pump();

      expect(find.text('한글, 영문, 숫자만 사용할 수 있습니다.'), findsOneWidget);
      final btn = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, '저장'),
      );
      expect(btn.onPressed, isNull);
    });

    testWidgets('save button enabled for valid nickname', (tester) async {
      await tester.pumpWidget(_buildApp(nickname: '홍길동'));
      await tester.pump();

      await tester.tap(find.text('편집'));
      await tester.pump();

      await tester.enterText(find.byType(TextField), '새닉네임');
      await tester.pump();

      final btn = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, '저장'),
      );
      expect(btn.onPressed, isNotNull,
          reason: 'Save button should be enabled for valid nickname');
    });

    testWidgets('logout button triggers confirmation dialog', (tester) async {
      await tester.pumpWidget(_buildApp());
      await tester.pump();

      await tester.tap(find.text('로그아웃'));
      await tester.pump();

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('로그아웃 하시겠습니까?'), findsOneWidget);
      expect(find.text('취소'), findsOneWidget);
    });

    testWidgets('cancel in logout dialog dismisses without signing out',
        (tester) async {
      await tester.pumpWidget(_buildApp());
      await tester.pump();

      await tester.tap(find.text('로그아웃'));
      await tester.pump();

      // Tap Cancel in dialog
      await tester.tap(find.text('취소'));
      await tester.pump();

      // Dialog dismissed, still on SettingsScreen
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(SettingsScreen), findsOneWidget);
    });

    testWidgets('calls PATCH /users/me with correct nickname on save',
        (tester) async {
      final fakeDio = _FakeDio();
      await tester.pumpWidget(_buildApp(nickname: '홍길동', fakeDio: fakeDio));
      await tester.pump();

      await tester.tap(find.text('편집'));
      await tester.pump();

      await tester.enterText(find.byType(TextField), '새닉네임');
      await tester.pump();

      await tester.tap(find.widgetWithText(ElevatedButton, '저장'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(fakeDio.lastPatchData, {'nickname': '새닉네임'});
    });

    testWidgets('shows snackbar on API failure', (tester) async {
      await tester.pumpWidget(_buildApp(nickname: '홍길동', dioShouldFail: true));
      await tester.pump();

      await tester.tap(find.text('편집'));
      await tester.pump();

      await tester.enterText(find.byType(TextField), '새닉네임');
      await tester.pump();

      await tester.tap(find.widgetWithText(ElevatedButton, '저장'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byType(SnackBar), findsOneWidget);
    });
  });
}
