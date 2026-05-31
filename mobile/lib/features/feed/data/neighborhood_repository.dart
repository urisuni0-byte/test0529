import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/app_error.dart';
import '../../../core/network/api_client.dart';
import 'models/neighborhood_model.dart';

class NeighborhoodRepository {
  const NeighborhoodRepository({
    required Dio publicDio,
    required Dio authedDio,
  })  : _publicDio = publicDio, // ignore: prefer_initializing_formals
        _authedDio = authedDio; // ignore: prefer_initializing_formals

  /// Unauthenticated Dio — used for the public GET /neighborhoods endpoint.
  final Dio _publicDio;

  /// Authenticated Dio — used for PATCH /users/me (requires Bearer token).
  final Dio _authedDio;

  /// Fetches all neighborhoods (public endpoint — no auth required).
  Future<List<NeighborhoodModel>> getNeighborhoods() async {
    try {
      final resp = await _publicDio.get('/neighborhoods');
      final data = resp.data;
      if (data is! Map) {
        throw const AppError(
          message: '동네 목록 응답 형식이 올바르지 않습니다.',
          code: AppErrorCode.serverError,
        );
      }
      final items = data['items'] as List<dynamic>?;
      if (items == null) {
        throw const AppError(
          message: '동네 목록 응답 형식이 올바르지 않습니다.',
          code: AppErrorCode.serverError,
        );
      }
      return items
          .map((e) => NeighborhoodModel.fromJson(e as Map<String, dynamic>))
          .toList();
    } on AppError {
      rethrow;
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  /// Saves the selected neighborhood for the current user (auth required).
  Future<void> saveNeighborhood(int neighborhoodId) async {
    try {
      await _authedDio.patch(
        '/users/me',
        data: {'neighborhood_id': neighborhoodId},
      );
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }
}

final neighborhoodRepositoryProvider = Provider<NeighborhoodRepository>((ref) {
  return NeighborhoodRepository(
    publicDio: ref.watch(refreshDioProvider), // public GET — no auth header
    authedDio: ref.watch(dioProvider),        // PATCH /users/me — auth required
  );
});
