import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/chat/data/models/chat_models.dart';

void main() {
  group('ChatRoomCreateResult', () {
    test('fromJson 201 신규 생성 파싱', () {
      final json = {
        'id': 'room-uuid-1',
        'product_id': 'prod-uuid-1',
        'created_at': '2026-05-30T10:00:00Z',
        'is_new': true,
      };
      final result = ChatRoomCreateResult.fromJson(json);
      expect(result.roomId, 'room-uuid-1');
      expect(result.productId, 'prod-uuid-1');
      expect(result.isNew, isTrue);
    });

    test('fromJson 200 기존 방 파싱', () {
      final json = {
        'id': 'room-uuid-existing',
        'product_id': 'prod-uuid-1',
        'created_at': '2026-05-29T08:00:00Z',
        'is_new': false,
      };
      final result = ChatRoomCreateResult.fromJson(json);
      expect(result.roomId, 'room-uuid-existing');
      expect(result.isNew, isFalse);
    });
  });

  group('ChatMessageModel', () {
    const myUserId = 'user-me-123';

    Map<String, dynamic> msgJson({
      String senderId = myUserId,
      String content = '안녕하세요',
    }) =>
        {
          'id': 'msg-uuid-1',
          'room_id': 'room-uuid-1',
          'sender_id': senderId,
          'sender_nickname': '테스터',
          'content': content,
          'created_at': '2026-05-30T10:00:00Z',
        };

    test('fromJson isMe=true (본인 발신)', () {
      final msg = ChatMessageModel.fromJson(
        msgJson(senderId: myUserId),
        myUserId: myUserId,
      );
      expect(msg.isMe, isTrue);
      expect(msg.senderId, myUserId);
      expect(msg.content, '안녕하세요');
    });

    test('fromJson isMe=false (상대방 발신)', () {
      final msg = ChatMessageModel.fromJson(
        msgJson(senderId: 'other-user-456'),
        myUserId: myUserId,
      );
      expect(msg.isMe, isFalse);
    });

    test('createdAt toLocal 변환', () {
      final msg = ChatMessageModel.fromJson(
        msgJson(),
        myUserId: myUserId,
      );
      // toLocal()로 변환되어야 함
      expect(msg.createdAt.isUtc, isFalse);
    });

    test('fromJson 필드 파싱 완전성', () {
      final msg = ChatMessageModel.fromJson(
        msgJson(content: '테스트 내용'),
        myUserId: myUserId,
      );
      expect(msg.id, 'msg-uuid-1');
      expect(msg.roomId, 'room-uuid-1');
      expect(msg.senderNickname, '테스터');
      expect(msg.content, '테스트 내용');
    });
  });
}
