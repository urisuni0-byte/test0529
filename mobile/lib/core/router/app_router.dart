import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/domain/auth_notifier.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/onboarding_screen.dart';
import '../../features/auth/presentation/settings_screen.dart';
import '../../features/feed/presentation/feed_screen.dart';
import '../../features/feed/presentation/neighborhood_picker_screen.dart';
import '../../features/product/data/models/product_detail_model.dart';
import '../../features/product/presentation/product_detail_screen.dart';
import '../../features/product/presentation/product_edit_screen.dart';
import '../../features/chat/presentation/chat_list_screen.dart';
import '../../features/chat/presentation/chat_room_screen.dart';
import '../../features/product/presentation/product_register_screen.dart';
import '../../features/splash/splash_screen.dart';

/// /product/:id 형태의 공개 상품 상세 경로인지 확인.
/// 'register' 등 인증 필요 하위 경로는 명시적으로 제외한다.
bool _isPublicProductRoute(String loc) =>
    RegExp(r'^/product/(?!register$)[^/]+$').hasMatch(loc);

/// Bridges Riverpod auth state to GoRouter's [refreshListenable].
class _RouterNotifier extends ChangeNotifier {
  _RouterNotifier(Ref ref) {
    ref.listen<AsyncValue<Object?>>(authNotifierProvider, (prev, next) {
      notifyListeners();
    });
  }
}

final routerProvider = Provider<GoRouter>((ref) {
  final notifier = _RouterNotifier(ref);

  final router = GoRouter(
    refreshListenable: notifier,
    initialLocation: '/splash',
    redirect: (context, state) {
      final authAsync = ref.read(authNotifierProvider);
      final loc = state.uri.path;

      // Error state — clear to login; error handling is shown in LoginScreen
      if (authAsync.hasError) {
        return loc == '/login' ? null : '/login';
      }

      if (authAsync.isLoading) {
        return loc == '/splash' ? null : '/splash';
      }

      final authState = authAsync.valueOrNull;
      final isAuthenticated = authState?.isAuthenticated ?? false;
      final needsOnboarding = authState?.needsOnboarding ?? false;

      if (!isAuthenticated) {
        // /product/:id는 공개 경로 — 비인증 사용자도 상세 열람 가능 (FR-2)
        if (_isPublicProductRoute(loc)) return null;
        return loc == '/login' ? null : '/login';
      }

      // 아래 두 incomplete-auth 가드도 /product/:id 접근은 허용 (FR-2)
      if (needsOnboarding && loc != '/onboarding') {
        if (_isPublicProductRoute(loc)) return null;
        return '/onboarding';
      }

      // 동네 미설정 사용자 → 동네 설정 화면으로 강제 이동
      final hasNeighborhood = authState?.user?.hasNeighborhood ?? false;
      if (!hasNeighborhood && loc != '/neighborhood') {
        if (_isPublicProductRoute(loc)) return null;
        return '/neighborhood';
      }

      if (loc == '/login' || loc == '/splash') {
        return '/feed';
      }

      return null;
    },
    routes: [
      GoRoute(
        path: '/splash',
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/onboarding',
        builder: (context, state) => const OnboardingScreen(),
      ),
      GoRoute(
        path: '/feed',
        builder: (context, state) => const FeedScreen(),
      ),
      GoRoute(
        path: '/neighborhood',
        builder: (context, state) => const NeighborhoodPickerScreen(),
      ),
      GoRoute(
        path: '/settings',
        builder: (context, state) => const SettingsScreen(),
      ),
      GoRoute(
        path: '/product/register',
        builder: (context, state) => const ProductRegisterScreen(),
      ),
      GoRoute(
        path: '/product/:productId/edit',
        builder: (context, state) {
          final product = state.extra as ProductDetailModel;
          return ProductEditScreen(product: product);
        },
      ),
      GoRoute(
        path: '/product/:productId',
        builder: (context, state) => ProductDetailScreen(
          productId: state.pathParameters['productId']!,
        ),
      ),
      GoRoute(
        path: '/chat-list',
        builder: (context, state) => const ChatListScreen(),
      ),
      GoRoute(
        path: '/chat/:roomId',
        builder: (context, state) => ChatRoomScreen(
          roomId: state.pathParameters['roomId']!,
          productId: state.extra as String?,
        ),
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      body: Center(child: Text('페이지를 찾을 수 없습니다: ${state.error}')),
    ),
  );

  // Dispose GoRouter (and its ChangeNotifier) when the provider is torn down
  ref.onDispose(router.dispose);

  return router;
});
