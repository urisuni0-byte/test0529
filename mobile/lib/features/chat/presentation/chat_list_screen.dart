import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/error/app_error.dart';
import '../../../core/utils/formatting.dart';
import '../../../core/widgets/app_error_view.dart';
import '../data/chat_repository.dart';
import '../data/models/chat_models.dart';
import '../domain/chat_list_notifier.dart';

class ChatListScreen extends ConsumerWidget {
  const ChatListScreen({super.key});

  Future<void> _onTapRoom(
    BuildContext context,
    WidgetRef ref,
    ChatListItem room,
  ) async {
    // 읽음 처리 (탭 즉시)
    try {
      await ref.read(chatRepositoryProvider).markAsRead(room.id);
    } catch (_) {
      // 읽음 처리 실패는 무시 (비필수)
    }

    if (!context.mounted) return;

    // 채팅방으로 이동 (pop 대기)
    await context.push('/chat/${room.id}', extra: room.product.id);

    if (!context.mounted) return;

    // 돌아왔을 때 목록 새로고침
    ref.invalidate(chatListProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final listAsync = ref.watch(chatListProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('채팅'),
        backgroundColor: const Color(0xFFFF7043),
        foregroundColor: Colors.white,
      ),
      body: listAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => AppErrorView(
          message: err is AppError ? err.message : '오류가 발생했습니다.',
          onRetry: () => ref.invalidate(chatListProvider),
        ),
        data: (rooms) => rooms.isEmpty
            ? const _EmptyView()
            : RefreshIndicator(
                onRefresh: () =>
                    ref.read(chatListProvider.notifier).refresh(),
                child: ListView.separated(
                  physics: const AlwaysScrollableScrollPhysics(),
                  itemCount: rooms.length,
                  separatorBuilder: (_, _) =>
                      const Divider(height: 1, indent: 72),
                  itemBuilder: (ctx, i) => _ChatRoomCard(
                    room: rooms[i],
                    onTap: () => _onTapRoom(ctx, ref, rooms[i]),
                  ),
                ),
              ),
      ),
    );
  }
}

// ─── 빈 상태 ─────────────────────────────────────────────────────────────────

class _EmptyView extends StatelessWidget {
  const _EmptyView();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text(
        '아직 채팅 내역이 없습니다.',
        style: TextStyle(color: Colors.grey),
      ),
    );
  }
}

// ─── 채팅방 카드 ──────────────────────────────────────────────────────────────

class _ChatRoomCard extends StatelessWidget {
  const _ChatRoomCard({required this.room, required this.onTap});

  final ChatListItem room;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: _Thumbnail(url: room.product.thumbnailUrl),
      title: Row(
        children: [
          Expanded(
            child: Text(
              room.product.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          if (room.lastMessageAt != null)
            Text(
              timeAgo(room.lastMessageAt!),
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
        ],
      ),
      subtitle: Row(
        children: [
          Expanded(
            child: Text(
              room.lastMessage ?? '메시지 없음',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 13,
              ),
            ),
          ),
          if (room.hasUnread)
            Container(
              key: const Key('unread_badge'),
              margin: const EdgeInsets.only(left: 4),
              padding:
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFFFF7043),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '${room.unreadCount}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
      onTap: onTap,
    );
  }
}

// ─── 썸네일 ───────────────────────────────────────────────────────────────────

class _Thumbnail extends StatelessWidget {
  const _Thumbnail({this.url});

  final String? url;

  @override
  Widget build(BuildContext context) {
    if (url == null || url!.isEmpty) {
      return Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: Colors.grey.shade200,
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(Icons.image_not_supported, color: Colors.grey),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.network(
        url!,
        width: 52,
        height: 52,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => Container(
          width: 52,
          height: 52,
          color: Colors.grey.shade200,
          child: const Icon(Icons.image_not_supported, color: Colors.grey),
        ),
      ),
    );
  }
}
