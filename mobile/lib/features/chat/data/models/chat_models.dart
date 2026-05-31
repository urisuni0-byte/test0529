import 'package:flutter/foundation.dart';

class ChatRoomCreateResult {
  const ChatRoomCreateResult({
    required this.roomId,
    required this.productId,
    required this.isNew,
  });

  final String roomId;
  final String productId;
  final bool isNew;

  factory ChatRoomCreateResult.fromJson(Map<String, dynamic> json) =>
      ChatRoomCreateResult(
        roomId: json['id'] as String,
        productId: json['product_id'] as String,
        isNew: json['is_new'] as bool,
      );
}

@immutable
class ChatMessageModel {
  const ChatMessageModel({
    required this.id,
    required this.roomId,
    required this.senderId,
    required this.senderNickname,
    required this.content,
    required this.createdAt,
    required this.isMe,
  });

  final String id;
  final String roomId;
  final String senderId;
  final String senderNickname;
  final String content;
  final DateTime createdAt;
  final bool isMe;

  factory ChatMessageModel.fromJson(
    Map<String, dynamic> json, {
    required String myUserId,
  }) =>
      ChatMessageModel(
        id: json['id'] as String,
        roomId: json['room_id'] as String,
        senderId: json['sender_id'] as String,
        senderNickname: json['sender_nickname'] as String,
        content: json['content'] as String,
        createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
        isMe: (json['sender_id'] as String) == myUserId,
      );
}

// ─── Chat List Models ─────────────────────────────────────────────────────────

@immutable
class ChatListItemProduct {
  const ChatListItemProduct({
    required this.id,
    required this.title,
    required this.price,
    this.thumbnailUrl,
    required this.status,
  });

  final String id;
  final String title;
  final int price;
  final String? thumbnailUrl;
  final String status;

  bool get isSold => status == 'SOLD';

  factory ChatListItemProduct.fromJson(Map<String, dynamic> json) =>
      ChatListItemProduct(
        id: json['id'] as String,
        title: json['title'] as String,
        price: json['price'] as int,
        thumbnailUrl: json['thumbnail_url'] as String?,
        status: json['status'] as String,
      );
}

@immutable
class ChatListItem {
  const ChatListItem({
    required this.id,
    required this.product,
    required this.otherUserNickname,
    this.lastMessage,
    this.lastMessageAt,
    required this.unreadCount,
  });

  final String id; // room_id
  final ChatListItemProduct product;
  final String otherUserNickname;
  final String? lastMessage;
  final DateTime? lastMessageAt;
  final int unreadCount;

  bool get hasUnread => unreadCount > 0;

  factory ChatListItem.fromJson(Map<String, dynamic> json) => ChatListItem(
        id: json['id'] as String,
        product: ChatListItemProduct.fromJson(
          json['product'] as Map<String, dynamic>,
        ),
        otherUserNickname: json['other_user_nickname'] as String,
        lastMessage: json['last_message'] as String?,
        lastMessageAt: json['last_message_at'] != null
            ? DateTime.parse(json['last_message_at'] as String).toLocal()
            : null,
        unreadCount: json['unread_count'] as int,
      );
}
