import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/app_error.dart';
import '../../../core/network/api_client.dart';
import 'models/product_detail_model.dart';

class ProductManagementRepository {
  const ProductManagementRepository({required Dio authDio}) : _dio = authDio;

  final Dio _dio;

  Future<void> likeProduct(String productId) async {
    try {
      await _dio.post('/products/$productId/likes');
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  Future<void> unlikeProduct(String productId) async {
    try {
      await _dio.delete('/products/$productId/likes');
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  Future<ProductDetailModel> updateProduct(
    String productId,
    Map<String, dynamic> data,
  ) async {
    try {
      final resp = await _dio.patch('/products/$productId', data: data);
      return ProductDetailModel.fromJson(resp.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  Future<void> deleteProduct(String productId) async {
    try {
      await _dio.delete('/products/$productId');
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }
}

final productManagementRepositoryProvider =
    Provider<ProductManagementRepository>((ref) {
  return ProductManagementRepository(authDio: ref.watch(dioProvider));
});
