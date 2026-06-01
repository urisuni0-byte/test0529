import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../../core/constants.dart';
import '../../../core/error/app_error.dart';
import '../../../core/network/api_client.dart';
import '../../../core/storage/secure_storage.dart';
import 'models/auth_token.dart';
import 'models/user_model.dart';

class AuthRepository {
  AuthRepository({
    required Dio refreshDio,
    required SecureStorageService storage,
    GoogleSignIn? googleSignIn,
  })  : _refreshDio = refreshDio, // ignore: prefer_initializing_formals
        _storage = storage, // ignore: prefer_initializing_formals
        _googleSignIn = googleSignIn ??
            GoogleSignIn(
              scopes: ['email', 'profile'],
              serverClientId: AppConstants.googleClientId.isEmpty
                  ? null
                  : AppConstants.googleClientId,
            );

  final Dio _refreshDio;
  final SecureStorageService _storage;
  final GoogleSignIn _googleSignIn;

  Future<UserModel> signInWithGoogle() async {
    final account = await _googleSignIn.signIn();
    if (account == null) {
      throw const AppError(message: '로그인이 취소되었습니다.', code: AppErrorCode.unknown);
    }

    final auth = await account.authentication;
    final idToken = auth.idToken;
    if (idToken == null) {
      throw const AppError(
        message: 'Google 인증 토큰을 받을 수 없습니다.',
        code: AppErrorCode.unknown,
      );
    }

    try {
      final resp = await _refreshDio.post(
        '/auth/google',
        data: {'id_token': idToken},
      );
      final token = AuthToken.fromJson(resp.data as Map<String, dynamic>);

      // Fetch user profile BEFORE persisting tokens.
      // This ensures tokens are only stored when we can confirm the account
      // is active and the backend is reachable. If /users/me fails, the user
      // is not silently auto-authenticated on the next app launch.
      //
      // Note: refreshDio is intentionally used here with a manual Authorization
      // header because this is a one-time post-login call with a fresh token
      // that has not yet been persisted to storage.
      final userResp = await _refreshDio.get(
        '/users/me',
        options: Options(
          headers: {'Authorization': 'Bearer ${token.accessToken}'},
        ),
      );
      final user = UserModel.fromJson(userResp.data as Map<String, dynamic>);

      // Only persist tokens after the full login flow succeeds
      await _storage.saveTokens(
        accessToken: token.accessToken,
        refreshToken: token.refreshToken,
      );

      return user;
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  Future<UserModel> signInWithEmail(String email, String password) async {
    try {
      final resp = await _refreshDio.post(
        '/auth/login',
        data: {'email': email, 'password': password},
      );
      final token = AuthToken.fromJson(resp.data as Map<String, dynamic>);
      final userResp = await _refreshDio.get(
        '/users/me',
        options: Options(headers: {'Authorization': 'Bearer ${token.accessToken}'}),
      );
      final user = UserModel.fromJson(userResp.data as Map<String, dynamic>);
      await _storage.saveTokens(
        accessToken: token.accessToken,
        refreshToken: token.refreshToken,
      );
      return user;
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  Future<UserModel> registerWithEmail(
    String email,
    String password,
    String nickname,
  ) async {
    try {
      final resp = await _refreshDio.post(
        '/auth/register',
        data: {'email': email, 'password': password, 'nickname': nickname},
      );
      final token = AuthToken.fromJson(resp.data as Map<String, dynamic>);
      final userResp = await _refreshDio.get(
        '/users/me',
        options: Options(headers: {'Authorization': 'Bearer ${token.accessToken}'}),
      );
      final user = UserModel.fromJson(userResp.data as Map<String, dynamic>);
      await _storage.saveTokens(
        accessToken: token.accessToken,
        refreshToken: token.refreshToken,
      );
      return user;
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  Future<UserModel> getMe(String accessToken) async {
    try {
      final resp = await _refreshDio.get(
        '/users/me',
        options: Options(
          headers: {'Authorization': 'Bearer $accessToken'},
        ),
      );
      return UserModel.fromJson(resp.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  Future<String?> refreshAccessToken() async {
    final refreshToken = await _storage.getRefreshToken();
    if (refreshToken == null) return null;
    try {
      final resp = await _refreshDio.post(
        '/auth/refresh',
        data: {'refresh_token': refreshToken},
      );
      final newToken = resp.data['access_token'] as String;
      await _storage.saveAccessToken(newToken);
      return newToken;
    } catch (_) {
      return null;
    }
  }

  Future<void> signOut() async {
    try {
      await _googleSignIn.signOut();
    } catch (_) {}
    await _storage.deleteAll();
  }
}

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(
    refreshDio: ref.watch(refreshDioProvider),
    storage: ref.watch(secureStorageProvider),
  );
});
