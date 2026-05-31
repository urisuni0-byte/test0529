import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/auth_notifier.dart';
import 'widgets/google_sign_in_button.dart';

class LoginScreen extends ConsumerWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authNotifierProvider);

    ref.listen(authNotifierProvider, (_, next) {
      if (next.hasError) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(next.error?.toString() ?? '로그인 중 오류가 발생했습니다.'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    });

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.storefront, size: 80, color: Color(0xFFFF7043)),
                const SizedBox(height: 16),
                const Text(
                  '중고거래 MVP',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF212121),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  '우리 동네 중고 거래',
                  style: TextStyle(fontSize: 15, color: Color(0xFF757575)),
                ),
                const SizedBox(height: 56),
                if (authState.isLoading)
                  const CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation(Color(0xFFFF7043)),
                  )
                else
                  GoogleSignInButton(
                    onPressed: () =>
                        ref.read(authNotifierProvider.notifier).signInWithGoogle(),
                  ),
                if (kDebugMode) ...[
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: () =>
                        ref.read(authNotifierProvider.notifier).signInAsTestUser(),
                    child: const Text(
                      '테스트로 계속 (디버그)',
                      style: TextStyle(color: Color(0xFF9E9E9E)),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
