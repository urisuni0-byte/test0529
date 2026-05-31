import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/app_error.dart';
import '../../../core/network/api_client.dart';
import 'models/chat_models.dart';

class ChatRepository {
  const ChatRepository({required Dio authDio}) : _dio = authDio;

  final Dio _dio;

  Future<ChatRoomCreateResult> createOrGetChatRoom(String productId) async {
    try {
      final resp = await _dio.post(
        '/chat-rooms',
        data: {'product_id': productId},
      );
      return ChatRoomCreateResult.fromJson(resp.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  Future<List<ChatMessageModel>> getMessages(
    String roomId, {
    required String myUserId,
    int page = 1,
    int limit = 50,
  }) async {
    try {
      final resp = await _dio.get(
        '/chat-rooms/$roomId/messages',
        queryParameters: {'page': page, 'limit': limit},
      );
      final items =
          (resp.data['items'] as List).cast<Map<String, dynamic>>();
      return items
          .map((j) => ChatMessageModel.fromJson(j, myUserId: myUserId))
          .toList();
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  Future<void> markAsRead(String roomId) async {
    try {
      await _dio.patch('/chat-rooms/$roomId/read');
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  Future<List<ChatListItem>> getChatList() async {
    try {
      final resp = await _dio.get('/chat-rooms');
      return (resp.data as List)
          .cast<Map<String, dynamic>>()
          .map(ChatListItem.fromJson)
          .toList();
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }
}

final chatRepositoryProvider = Provider<ChatRepository>((ref) {
  return ChatRepository(authDio: ref.watch(dioProvider));
});
