import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/app_error.dart';
import '../../../core/network/api_client.dart';
import 'models/product_model.dart';

class ProductListResponse {
  const ProductListResponse({
    required this.items,
    required this.total,
    required this.page,
    required this.limit,
  });

  final List<ProductModel> items;
  final int total;
  final int page;
  final int limit;
}

class ProductRepository {
  const ProductRepository({required Dio publicDio})
      : _publicDio = publicDio; // ignore: prefer_initializing_formals

  /// 공개 엔드포인트 — 인증 없는 Dio 사용 (FR-2: 비인증 사용자도 피드 열람 가능)
  final Dio _publicDio;

  Future<ProductListResponse> getProducts({
    required int neighborhoodId,
    int page = 1,
    int limit = 20,
  }) async {
    try {
      final resp = await _publicDio.get('/products', queryParameters: {
        'neighborhood_id': neighborhoodId,
        'page': page,
        'limit': limit,
      });
      final data = resp.data as Map<String, dynamic>;
      final items = (data['items'] as List<dynamic>)
          .map((e) => ProductModel.fromJson(e as Map<String, dynamic>))
          .toList();
      return ProductListResponse(
        items: items,
        total: data['total'] as int,
        page: data['page'] as int,
        limit: data['limit'] as int,
      );
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }
}

final productRepositoryProvider = Provider<ProductRepository>((ref) {
  return ProductRepository(publicDio: ref.watch(refreshDioProvider));
});
