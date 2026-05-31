import 'dart:async';

import 'package:dio/dio.dart';

import '../storage/secure_storage.dart';

/// Adds Bearer token to every request and handles 401 by refreshing the token.
/// Uses a Completer list to serialise concurrent 401 races.
class AuthInterceptor extends Interceptor {
  AuthInterceptor({
    required this.storage,
    required this.refreshDio,
    required this.refreshEndpoint,
    required this.onSignedOut,
  });

  final SecureStorageService storage;
  final Dio refreshDio;
  final String refreshEndpoint;
  final void Function() onSignedOut;

  bool _isRefreshing = false;
  final _refreshWaiters = <Completer<String?>>[];

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    try {
      final token = await storage.getAccessToken();
      if (token != null) {
        options.headers['Authorization'] = 'Bearer $token';
      }
      handler.next(options);
    } catch (e, st) {
      // Storage platform error — reject rather than silently hang
      handler.reject(
        DioException(requestOptions: options, error: e, stackTrace: st),
      );
    }
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    if (err.response?.statusCode != 401) {
      handler.next(err);
      return;
    }

    if (_isRefreshing) {
      final completer = Completer<String?>();
      _refreshWaiters.add(completer);
      final newToken = await completer.future;
      if (newToken != null) {
        err.requestOptions.headers['Authorization'] = 'Bearer $newToken';
        try {
          final response = await refreshDio.fetch(err.requestOptions);
          handler.resolve(response);
        } catch (e) {
          handler.next(err);
        }
      } else {
        handler.next(err);
      }
      return;
    }

    _isRefreshing = true;
    String? newToken;
    try {
      newToken = await _performRefresh();
    } finally {
      _isRefreshing = false;
      // Always resolve all waiters — null signals sign-out to each one
      for (final c in _refreshWaiters) {
        c.complete(newToken);
      }
      _refreshWaiters.clear();
    }

    if (newToken != null) {
      err.requestOptions.headers['Authorization'] = 'Bearer $newToken';
      try {
        final response = await refreshDio.fetch(err.requestOptions);
        handler.resolve(response);
      } catch (e) {
        handler.next(err);
      }
    } else {
      handler.next(err);
    }
  }

  Future<String?> _performRefresh() async {
    final refreshToken = await storage.getRefreshToken();
    if (refreshToken == null) {
      await _signOut();
      return null;
    }
    try {
      final resp = await refreshDio.post(
        refreshEndpoint,
        data: {'refresh_token': refreshToken},
      );
      final newAccessToken = resp.data['access_token'] as String;
      await storage.saveAccessToken(newAccessToken);
      return newAccessToken;
    } catch (_) {
      await _signOut();
      return null;
    }
  }

  Future<void> _signOut() async {
    await storage.deleteAll(); // await before notifying to avoid token write race
    onSignedOut();
  }
}
