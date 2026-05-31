import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/chat_repository.dart';
import '../data/models/chat_models.dart';

class ChatListNotifier
    extends AutoDisposeAsyncNotifier<List<ChatListItem>> {
  @override
  Future<List<ChatListItem>> build() =>
      ref.read(chatRepositoryProvider).getChatList();

  Future<void> refresh() async {
    ref.invalidateSelf();
    try {
      await future;
    } catch (_) {
      // build() 오류는 AsyncError 상태로 반영됨 — 여기서 삼킴
    }
  }
}

final chatListProvider =
    AutoDisposeAsyncNotifierProvider<ChatListNotifier, List<ChatListItem>>(
  ChatListNotifier.new,
);
