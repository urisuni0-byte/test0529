import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/chat/data/models/chat_models.dart';

void main() {
  group('ChatListItemProduct', () {
    Map<String, dynamic> productJson({
      String? thumbnailUrl,
      String status = 'SALE',
    }) =>
        {
          'id': 'prod-1',
          'title': '아이폰 15',
          'price': 900000,
          'thumbnail_url': thumbnailUrl,
          'status': status,
        };

    test('fromJson 기본 파싱', () {
      final p = ChatListItemProduct.fromJson(
        productJson(thumbnailUrl: 'https://r2.../thumb.jpg'),
      );
      expect(p.id, 'prod-1');
      expect(p.title, '아이폰 15');
      expect(p.price, 900000);
      expect(p.thumbnailUrl, 'https://r2.../thumb.jpg');
      expect(p.status, 'SALE');
      expect(p.isSold, isFalse);
    });

    test('thumbnailUrl null 처리', () {
      final p = ChatListItemProduct.fromJson(productJson());
      expect(p.thumbnailUrl, isNull);
    });

    test('isSold SOLD 상태', () {
      final p = ChatListItemProduct.fromJson(productJson(status: 'SOLD'));
      expect(p.isSold, isTrue);
    });
  });

  group('ChatListItem', () {
    Map<String, dynamic> roomJson({
      String? lastMessage,
      String? lastMessageAt,
      int unreadCount = 0,
    }) =>
        {
          'id': 'room-uuid-1',
          'product': {
            'id': 'prod-1',
            'title': '아이폰 15',
            'price': 900000,
            'thumbnail_url': null,
            'status': 'SALE',
          },
          'other_user_nickname': '김지수',
          'last_message': lastMessage,
          'last_message_at': lastMessageAt,
          'unread_count': unreadCount,
        };

    test('fromJson 기본 파싱', () {
      final item = ChatListItem.fromJson(roomJson(
        lastMessage: '안녕하세요!',
        lastMessageAt: '2026-05-30T10:00:00Z',
        unreadCount: 3,
      ));
      expect(item.id, 'room-uuid-1');
      expect(item.otherUserNickname, '김지수');
      expect(item.lastMessage, '안녕하세요!');
      expect(item.lastMessageAt, isNotNull);
      expect(item.unreadCount, 3);
      expect(item.hasUnread, isTrue);
    });

    test('lastMessage null 처리', () {
      final item = ChatListItem.fromJson(roomJson());
      expect(item.lastMessage, isNull);
      expect(item.lastMessageAt, isNull);
    });

    test('unreadCount = 0 → hasUnread = false', () {
      final item = ChatListItem.fromJson(roomJson(unreadCount: 0));
      expect(item.hasUnread, isFalse);
    });

    test('lastMessageAt toLocal 변환', () {
      final item = ChatListItem.fromJson(roomJson(
        lastMessageAt: '2026-05-30T10:00:00Z',
      ));
      expect(item.lastMessageAt!.isUtc, isFalse);
    });

    test('product 중첩 파싱', () {
      final item = ChatListItem.fromJson(roomJson());
      expect(item.product.title, '아이폰 15');
      expect(item.product.price, 900000);
    });
  });
}
