import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/app_error.dart';
import '../../../core/network/api_client.dart';

class ProductRegisterRepository {
  const ProductRegisterRepository({required Dio authDio}) : _dio = authDio;

  final Dio _dio;

  Future<List<String>> uploadImages(List<Uint8List> images) async {
    try {
      final formData = FormData.fromMap({
        'files': images
            .map((b) => MultipartFile.fromBytes(b, filename: 'image.jpg'))
            .toList(),
      });
      // receiveTimeout 연장 — 서버 이미지 처리(리사이징 등)에 충분한 여유 확보
      final resp = await _dio.post(
        '/products/images',
        data: formData,
        options: Options(receiveTimeout: const Duration(seconds: 60)),
      );
      return (resp.data['urls'] as List<dynamic>).cast<String>();
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  Future<String> createProduct({
    required String title,
    required int price,
    required String category,
    String? description,
    required List<String> imageUrls,
    required int neighborhoodId,
  }) async {
    try {
      final resp = await _dio.post('/products', data: {
        'title': title,
        'price': price,
        'category': category,
        if (description != null && description.isNotEmpty)
          'description': description,
        'image_urls': imageUrls,
        'neighborhood_id': neighborhoodId,
      });
      return resp.data['id'] as String;
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }
}

final productRegisterRepositoryProvider =
    Provider<ProductRegisterRepository>((ref) {
  return ProductRegisterRepository(authDio: ref.watch(dioProvider));
});
