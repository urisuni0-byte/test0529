import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants.dart';
import '../storage/secure_storage.dart';
import 'auth_interceptor.dart';
import 'auth_signal.dart';

/// Bare Dio for auth-only endpoints (login, refresh) — no auth interceptor.
final refreshDioProvider = Provider<Dio>((ref) {
  return Dio(BaseOptions(
    baseUrl: AppConstants.apiV1,
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 15),
    headers: {'Content-Type': 'application/json'},
  ));
});

/// Main authenticated Dio — adds Bearer token and handles 401 refresh.
final dioProvider = Provider<Dio>((ref) {
  final storage = ref.watch(secureStorageProvider);
  final refreshDio = ref.watch(refreshDioProvider);

  final dio = Dio(BaseOptions(
    baseUrl: AppConstants.apiV1,
    connectTimeout: const Duration(seconds: 10),
    // sendTimeout guards stalled uploads; receiveTimeout guards stalled responses.
    sendTimeout: const Duration(seconds: 30),
    receiveTimeout: const Duration(seconds: 15),
    headers: {'Content-Type': 'application/json'},
  ));

  dio.interceptors.add(
    AuthInterceptor(
      storage: storage,
      refreshDio: refreshDio,
      refreshEndpoint: '/auth/refresh',
      onSignedOut: () {
        // Signal authNotifierProvider to transition to Unauthenticated.
        // Using a signal counter avoids a circular import between api_client
        // and auth_notifier (which depends on auth_repository → api_client).
        ref.read(authSignedOutSignalProvider.notifier).state++;
      },
    ),
  );

  return dio;
});
