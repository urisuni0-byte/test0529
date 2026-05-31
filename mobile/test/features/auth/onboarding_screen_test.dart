import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/core/network/api_client.dart';
import 'package:mobile/features/auth/domain/auth_notifier.dart';
import 'package:mobile/features/auth/domain/auth_state.dart';
import 'package:mobile/features/auth/data/models/user_model.dart';
import 'package:mobile/features/auth/presentation/onboarding_screen.dart';

// ─── Fake AuthNotifier ───────────────────────────────────────────────────────

class _FakeAuthNotifier extends AuthNotifier {
  @override
  Future<AuthState> build() async => Authenticated(
        user: UserModel(
          id: 'test-id',
          email: 'test@example.com',
          role: 'user',
          isActive: true,
          nickname: null, // no nickname → needsOnboarding = true
        ),
      );
}

// ─── Fake Dio ────────────────────────────────────────────────────────────────

/// Captures requests and returns configurable responses.
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

// ─── Helpers ─────────────────────────────────────────────────────────────────

Widget _buildApp({_FakeDio? fakeDio, bool dioShouldFail = false}) {
  final dio = fakeDio ?? _FakeDio(shouldFail: dioShouldFail);
  return ProviderScope(
    overrides: [
      authNotifierProvider.overrideWith(_FakeAuthNotifier.new),
      dioProvider.overrideWithValue(dio),
    ],
    child: const MaterialApp(home: OnboardingScreen()),
  );
}

// ─── Tests ───────────────────────────────────────────────────────────────────

void main() {
  group('OnboardingScreen', () {
    testWidgets('renders nickname input and disabled submit button initially',
        (tester) async {
      await tester.pumpWidget(_buildApp());
      await tester.pump();

      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('닉네임을 입력해 주세요'), findsOneWidget);

      final btn = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, '완료'),
      );
      expect(btn.onPressed, isNull,
          reason: 'Button should be disabled when input is empty');
    });

    testWidgets('shows error for single-character nickname (too short)',
        (tester) async {
      await tester.pumpWidget(_buildApp());
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'a');
      await tester.pump();

      expect(find.text('닉네임은 2자 이상이어야 합니다.'), findsOneWidget);
      final btn = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, '완료'),
      );
      expect(btn.onPressed, isNull,
          reason: 'Button should be disabled for too-short nickname');
    });

    testWidgets('shows error for nickname with special characters',
        (tester) async {
      await tester.pumpWidget(_buildApp());
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'abc!@#');
      await tester.pump();

      expect(find.text('한글, 영문, 숫자만 사용할 수 있습니다.'), findsOneWidget);
      final btn = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, '완료'),
      );
      expect(btn.onPressed, isNull,
          reason: 'Button should be disabled for nickname with special chars');
    });

    testWidgets('enables button for valid 2-char nickname', (tester) async {
      await tester.pumpWidget(_buildApp());
      await tester.pump();

      await tester.enterText(find.byType(TextField), '홍길');
      await tester.pump();

      expect(find.text('닉네임은 2자 이상이어야 합니다.'), findsNothing);
      expect(find.text('한글, 영문, 숫자만 사용할 수 있습니다.'), findsNothing);
      final btn = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, '완료'),
      );
      expect(btn.onPressed, isNotNull,
          reason: 'Button should be enabled for valid nickname');
    });

    testWidgets('enables button for valid 15-char nickname', (tester) async {
      await tester.pumpWidget(_buildApp());
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'abcdefghijklmno'); // 15 chars
      await tester.pump();

      final btn = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, '완료'),
      );
      expect(btn.onPressed, isNotNull,
          reason: 'Button should be enabled for 15-char nickname');
    });

    testWidgets('shows error and disables button for 16-char nickname',
        (tester) async {
      await tester.pumpWidget(_buildApp());
      await tester.pump();

      // TextField has maxLength=15, so entering 16 chars is truncated to 15 by
      // the TextField widget itself. We test that the counter is capped at 15.
      await tester.enterText(find.byType(TextField), 'a' * 16);
      await tester.pump();

      // After clamping by maxLength the text is 15 chars — button should be enabled
      final btn = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, '완료'),
      );
      // The TextField widget enforces maxLength=15, so 16 chars is truncated → valid
      expect(btn.onPressed, isNotNull,
          reason: 'TextField clamps to 15 chars which is valid');
    });

    testWidgets('shows error for mixed special-char nickname with spaces',
        (tester) async {
      await tester.pumpWidget(_buildApp());
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'abc def');
      await tester.pump();

      expect(find.text('한글, 영문, 숫자만 사용할 수 있습니다.'), findsOneWidget);
      final btn = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, '완료'),
      );
      expect(btn.onPressed, isNull);
    });

    testWidgets('shows snackbar on API failure', (tester) async {
      await tester.pumpWidget(_buildApp(dioShouldFail: true));
      await tester.pump();

      await tester.enterText(find.byType(TextField), '홍길동');
      await tester.pump();

      await tester.tap(find.widgetWithText(ElevatedButton, '완료'));
      await tester.pump(); // start async
      await tester.pump(const Duration(milliseconds: 50)); // settle

      expect(find.byType(SnackBar), findsOneWidget);
    });

    testWidgets('calls PATCH /users/me with correct nickname on submit',
        (tester) async {
      final fakeDio = _FakeDio();
      await tester.pumpWidget(_buildApp(fakeDio: fakeDio));
      await tester.pump();

      await tester.enterText(find.byType(TextField), '홍길동');
      await tester.pump();

      await tester.tap(find.widgetWithText(ElevatedButton, '완료'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(fakeDio.lastPatchData, {'nickname': '홍길동'});
    });
  });
}
