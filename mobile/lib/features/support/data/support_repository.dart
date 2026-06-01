import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/app_error.dart';
import '../../../core/network/api_client.dart';

class SupportMessage {
  const SupportMessage({required this.role, required this.content});
  final String role;
  final String content;
}

class SupportRepository {
  SupportRepository(this._dio);
  final Dio _dio;

  Future<({String conversationId, String answer})> sendMessage({
    required String message,
    String? conversationId,
  }) async {
    try {
      final resp = await _dio.post('/support/chat', data: {
        'message': message,
        if (conversationId != null) 'conversation_id': conversationId,
      });
      return (
        conversationId: resp.data['conversation_id'] as String,
        answer: resp.data['answer'] as String,
      );
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }
}

final supportRepositoryProvider = Provider<SupportRepository>((ref) {
  return SupportRepository(ref.watch(dioProvider));
});
