import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/app_error.dart';
import '../../../core/network/api_client.dart';
import 'models/product_detail_model.dart';

class ProductDetailRepository {
  const ProductDetailRepository({required Dio publicDio})
      : _publicDio = publicDio; // ignore: prefer_initializing_formals

  /// 공개 엔드포인트 — 인증 없는 Dio 사용 (FR-2)
  final Dio _publicDio;

  Future<ProductDetailModel> getProduct(String productId) async {
    try {
      final resp = await _publicDio.get('/products/$productId');
      return ProductDetailModel.fromJson(resp.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }
}

final productDetailRepositoryProvider =
    Provider<ProductDetailRepository>((ref) {
  return ProductDetailRepository(publicDio: ref.watch(refreshDioProvider));
});
