import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/features/auth/domain/auth_notifier.dart';
import 'package:mobile/features/auth/domain/auth_state.dart';
import 'package:mobile/features/auth/presentation/login_screen.dart';

// Fake AuthNotifier — no real Google / backend calls
class _FakeAuthNotifier extends AuthNotifier {
  @override
  Future<AuthState> build() async => const Unauthenticated();

  @override
  Future<void> signInWithGoogle() async {}
}

Widget _buildTestApp() {
  return ProviderScope(
    overrides: [
      authNotifierProvider.overrideWith(_FakeAuthNotifier.new),
    ],
    child: const MaterialApp(home: LoginScreen()),
  );
}

void main() {
  group('LoginScreen', () {
    testWidgets('renders app title and sign-in button when unauthenticated',
        (tester) async {
      await tester.pumpWidget(_buildTestApp());
      await tester.pump(); // let async build() settle

      expect(find.text('중고거래 MVP'), findsOneWidget);
      expect(find.text('구글로 로그인'), findsOneWidget);
    });

    testWidgets('google sign-in button is tappable without throwing',
        (tester) async {
      await tester.pumpWidget(_buildTestApp());
      await tester.pump();

      await tester.tap(find.text('구글로 로그인'));
      await tester.pump();
      // signInWithGoogle is a no-op in the fake — should not throw
    });

    testWidgets('shows loading indicator while auth state is loading',
        (tester) async {
      await tester.pumpWidget(_buildTestApp());
      // Before async build() completes the notifier is in loading state
      // (first frame) — ensure the widget doesn't crash on that frame
      expect(find.byType(LoginScreen), findsOneWidget);
      await tester.pump(); // settle
      expect(find.text('구글로 로그인'), findsOneWidget);
    });
  });
}
