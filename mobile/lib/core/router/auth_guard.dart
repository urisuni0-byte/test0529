import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/domain/auth_notifier.dart';

/// Shows a login-required dialog and optionally navigates to /login on confirm.
void requireAuth(
  BuildContext context,
  WidgetRef ref, {
  VoidCallback? onAuthenticated,
}) {
  final isAuth =
      ref.read(authNotifierProvider).valueOrNull?.isAuthenticated ?? false;
  if (isAuth) {
    onAuthenticated?.call();
    return;
  }

  showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('로그인이 필요합니다'),
      content: const Text('이 기능을 사용하려면 로그인이 필요합니다.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('취소'),
        ),
        TextButton(
          onPressed: () {
            Navigator.of(ctx).pop();
            context.go('/login');
          },
          child: const Text('로그인'),
        ),
      ],
    ),
  );
}
