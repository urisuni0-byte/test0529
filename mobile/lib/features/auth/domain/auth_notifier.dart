import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jwt_decoder/jwt_decoder.dart';

import '../../../core/error/app_error.dart';
import '../../../core/network/auth_signal.dart';
import '../../../core/storage/secure_storage.dart';
import '../data/auth_repository.dart';
import '../data/models/user_model.dart';
import 'auth_state.dart';

class AuthNotifier extends AsyncNotifier<AuthState> {
  @override
  Future<AuthState> build() async {
    // Listen for forced sign-out signals from AuthInterceptor
    ref.listen<int>(authSignedOutSignalProvider, (prev, next) {
      if (next != prev) forceSignOut();
    });

    return _resolveInitialState();
  }

  Future<AuthState> _resolveInitialState() async {
    final storage = ref.read(secureStorageProvider);
    final accessToken = await storage.getAccessToken();

    if (accessToken == null) return const Unauthenticated();

    // Check expiry — JwtDecoder.isExpired throws FormatException on malformed tokens
    bool isExpired;
    try {
      isExpired = JwtDecoder.isExpired(accessToken);
    } catch (_) {
      await storage.deleteAll();
      return const Unauthenticated();
    }

    if (!isExpired) {
      try {
        final user = await ref.read(authRepositoryProvider).getMe(accessToken);
        return Authenticated(user: user);
      } catch (_) {
        await storage.deleteAll();
        return const Unauthenticated();
      }
    }

    // Access token expired — attempt refresh
    final newToken = await ref.read(authRepositoryProvider).refreshAccessToken();
    if (newToken == null) {
      await storage.deleteAll();
      return const Unauthenticated();
    }

    try {
      final user = await ref.read(authRepositoryProvider).getMe(newToken);
      return Authenticated(user: user);
    } catch (_) {
      await storage.deleteAll();
      return const Unauthenticated();
    }
  }

  Future<void> signInWithGoogle() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final user = await ref.read(authRepositoryProvider).signInWithGoogle();
      return Authenticated(user: user);
    });
    // Ensure errors are always AppError for consistent UI handling
    if (state.hasError && state.error is! AppError) {
      state = AsyncError(
        AppError(message: state.error.toString(), code: AppErrorCode.unknown),
        state.stackTrace ?? StackTrace.current,
      );
    }
  }

  Future<void> signInWithEmail(String email, String password) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final user = await ref.read(authRepositoryProvider).signInWithEmail(email, password);
      return Authenticated(user: user);
    });
    if (state.hasError && state.error is! AppError) {
      state = AsyncError(
        AppError(message: state.error.toString(), code: AppErrorCode.unknown),
        state.stackTrace ?? StackTrace.current,
      );
    }
  }

  Future<void> registerWithEmail(String email, String password, String nickname) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final user = await ref
          .read(authRepositoryProvider)
          .registerWithEmail(email, password, nickname);
      return Authenticated(user: user);
    });
    if (state.hasError && state.error is! AppError) {
      state = AsyncError(
        AppError(message: state.error.toString(), code: AppErrorCode.unknown),
        state.stackTrace ?? StackTrace.current,
      );
    }
  }

  Future<void> signOut() async {
    await ref.read(authRepositoryProvider).signOut();
    state = const AsyncData(Unauthenticated());
  }

  /// Called when AuthInterceptor signals a forced sign-out after token refresh failure.
  void forceSignOut() {
    state = const AsyncData(Unauthenticated());
  }

  /// 디버그 전용: Google 로그인 없이 테스트 유저로 진입.
  void signInAsTestUser() {
    const testUser = UserModel(
      id: 'test-user-id',
      email: 'test@test.com',
      role: 'user',
      isActive: true,
      nickname: '테스트유저',
      neighborhoodId: 2,
    );
    state = const AsyncData(Authenticated(user: testUser));
  }

  /// Optimistically update the in-memory user without a network round-trip.
  /// Used by screens that already confirmed a successful PATCH /users/me.
  void updateUser(UserModel updated) {
    if (state.valueOrNull?.isAuthenticated == true) {
      state = AsyncData(Authenticated(user: updated));
    }
  }
}

final authNotifierProvider =
    AsyncNotifierProvider<AuthNotifier, AuthState>(AuthNotifier.new);
