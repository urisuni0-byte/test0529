import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/formatting.dart';
import '../../product/domain/product_detail_provider.dart';
import '../data/models/chat_models.dart';
import '../domain/chat_room_notifier.dart';

class ChatRoomScreen extends ConsumerStatefulWidget {
  const ChatRoomScreen({
    super.key,
    required this.roomId,
    this.productId,
  });

  final String roomId;
  final String? productId;

  @override
  ConsumerState<ChatRoomScreen> createState() => _ChatRoomScreenState();
}

class _ChatRoomScreenState extends ConsumerState<ChatRoomScreen> {
  final _textController = TextEditingController();
  final _scrollController = ScrollController();
  bool _canSend = false;

  @override
  void initState() {
    super.initState();
    _textController.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _textController.removeListener(_onTextChanged);
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    final newCanSend = _textController.text.trim().isNotEmpty;
    if (newCanSend != _canSend) setState(() => _canSend = newCanSend);
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients &&
          _scrollController.position.maxScrollExtent > 0) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _send() {
    final content = _textController.text.trim();
    if (content.isEmpty) return;
    ref
        .read(chatRoomNotifierProvider(widget.roomId).notifier)
        .sendMessage(content);
    _textController.clear();
    setState(() => _canSend = false);
    _scrollToBottom();
  }

  @override
  Widget build(BuildContext context) {
    final chatState = ref.watch(chatRoomNotifierProvider(widget.roomId));

    ref.listen<ChatRoomState>(chatRoomNotifierProvider(widget.roomId),
        (prev, next) {
      // 새 메시지 수신 시 자동 스크롤
      if (prev != null && next.messages.length > prev.messages.length) {
        _scrollToBottom();
      }
      // 재연결 실패 시 오프라인 스낵바
      if (!(prev?.reconnectFailed ?? false) && next.reconnectFailed) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('오프라인 상태입니다. 네트워크를 확인해 주세요.')),
        );
      }
    });

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFFFF7043),
        foregroundColor: Colors.white,
        title: _ProductHeader(productId: widget.productId),
      ),
      body: Column(
        children: [
          Expanded(
            child: _buildMessageList(chatState),
          ),
          // 연결 상태 표시
          if (!chatState.isConnected && !chatState.isLoadingHistory)
            _ConnectionStatusBar(failed: chatState.reconnectFailed),
          _InputBar(
            controller: _textController,
            canSend: _canSend,
            onSend: _send,
          ),
        ],
      ),
    );
  }

  Widget _buildMessageList(ChatRoomState chatState) {
    if (chatState.isLoadingHistory) {
      return const Center(child: CircularProgressIndicator());
    }
    if (chatState.historyError != null) {
      return Center(
        child: Text(
          '메시지를 불러올 수 없습니다.',
          style: TextStyle(color: Colors.grey.shade600),
        ),
      );
    }
    if (chatState.messages.isEmpty) {
      return const Center(
        child: Text('첫 메시지를 보내보세요!'),
      );
    }
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: chatState.messages.length,
      itemBuilder: (_, i) => _MessageBubble(message: chatState.messages[i]),
    );
  }
}

// ─── 상단 상품 헤더 ───────────────────────────────────────────────────────────

class _ProductHeader extends ConsumerWidget {
  const _ProductHeader({this.productId});

  final String? productId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (productId == null || productId!.isEmpty) {
      return const Text('채팅');
    }

    final productAsync = ref.watch(productDetailProvider(productId!));
    return productAsync.when(
      loading: () => const Text('채팅'),
      error: (_, _) => const Text('채팅'),
      data: (product) => Row(
        children: [
          if (product.imageUrls.isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Image.network(
                product.imageUrls.first,
                width: 36,
                height: 36,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Container(
                  width: 36,
                  height: 36,
                  color: Colors.grey.shade300,
                  child: const Icon(Icons.image_not_supported, size: 18),
                ),
              ),
            ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  product.title,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  formatPrice(product.price),
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
          if (product.isSold)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.grey,
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                '판매완료',
                style: TextStyle(fontSize: 10, color: Colors.white),
              ),
            ),
        ],
      ),
    );
  }
}

// ─── 연결 상태 바 ─────────────────────────────────────────────────────────────

class _ConnectionStatusBar extends StatelessWidget {
  const _ConnectionStatusBar({required this.failed});

  final bool failed;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: Colors.orange.shade100,
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (!failed)
            const SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          const SizedBox(width: 8),
          Text(
            failed ? '연결 실패' : '연결 중...',
            style: const TextStyle(fontSize: 12),
          ),
        ],
      ),
    );
  }
}

// ─── 메시지 말풍선 ────────────────────────────────────────────────────────────

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});

  final ChatMessageModel message;

  @override
  Widget build(BuildContext context) {
    final isMe = message.isMe;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment:
            isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMe) ...[
            CircleAvatar(
              radius: 14,
              backgroundColor: Colors.grey.shade300,
              child: Text(
                message.senderNickname.isNotEmpty
                    ? message.senderNickname[0]
                    : '?',
                style: const TextStyle(fontSize: 12),
              ),
            ),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: isMe
                    ? const Color(0xFFFF7043)
                    : Colors.grey.shade200,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: isMe
                      ? const Radius.circular(16)
                      : const Radius.circular(4),
                  bottomRight: isMe
                      ? const Radius.circular(4)
                      : const Radius.circular(16),
                ),
              ),
              child: Text(
                message.content,
                style: TextStyle(
                  color: isMe ? Colors.white : Colors.black87,
                ),
              ),
            ),
          ),
          if (isMe) const SizedBox(width: 6),
        ],
      ),
    );
  }
}

// ─── 입력 바 ──────────────────────────────────────────────────────────────────

class _InputBar extends StatelessWidget {
  const _InputBar({
    required this.controller,
    required this.canSend,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool canSend;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                decoration: InputDecoration(
                  hintText: '메시지를 입력하세요',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 8),
                  isDense: true,
                ),
                textInputAction: TextInputAction.send,
                onSubmitted: canSend ? (_) => onSend() : null,
              ),
            ),
            const SizedBox(width: 6),
            IconButton(
              key: const Key('send_button'),
              onPressed: canSend ? onSend : null,
              icon: const Icon(Icons.send),
              style: IconButton.styleFrom(
                backgroundColor: canSend
                    ? const Color(0xFFFF7043)
                    : Colors.grey.shade300,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
