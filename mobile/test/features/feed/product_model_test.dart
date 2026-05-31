import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/feed/data/models/product_model.dart';

void main() {
  group('ProductModel.fromJson', () {
    const fullJson = {
      'id': 'abc-123',
      'seller_id': 'seller-uuid',
      'title': '아이폰 15 Pro',
      'price': 1200000,
      'created_at': '2026-05-30T09:00:00.000Z',
      'like_count': 3,
      'status': 'SALE',
      'thumbnail_url': 'https://example.com/img.jpg',
    };

    test('모든 필드를 정상 파싱한다', () {
      final model = ProductModel.fromJson(fullJson);
      expect(model.id, 'abc-123');
      expect(model.sellerId, 'seller-uuid');
      expect(model.title, '아이폰 15 Pro');
      expect(model.price, 1200000);
      expect(model.likeCount, 3);
      expect(model.status, 'SALE');
      expect(model.thumbnailUrl, 'https://example.com/img.jpg');
      expect(model.createdAt, DateTime.utc(2026, 5, 30, 9, 0, 0));
    });

    test('thumbnail_url이 null이면 thumbnailUrl은 null', () {
      final json = {...fullJson, 'thumbnail_url': null};
      final model = ProductModel.fromJson(json);
      expect(model.thumbnailUrl, isNull);
    });
  });

  group('ProductModel.isReserved', () {
    test('status가 RESERVED이면 true', () {
      final m = ProductModel(
        id: 'x',
        sellerId: 's',
        title: 't',
        price: 100,
        createdAt: DateTime.now(),
        likeCount: 0,
        status: 'RESERVED',
      );
      expect(m.isReserved, isTrue);
    });

    test('status가 SALE이면 false', () {
      final m = ProductModel(
        id: 'x',
        sellerId: 's',
        title: 't',
        price: 100,
        createdAt: DateTime.now(),
        likeCount: 0,
        status: 'SALE',
      );
      expect(m.isReserved, isFalse);
    });

    test('status가 SOLD이면 false', () {
      final m = ProductModel(
        id: 'x',
        sellerId: 's',
        title: 't',
        price: 100,
        createdAt: DateTime.now(),
        likeCount: 0,
        status: 'SOLD',
      );
      expect(m.isReserved, isFalse);
    });
  });

  group('formatPrice', () {
    test('1200000 → 1,200,000원', () {
      expect(formatPrice(1200000), '1,200,000원');
    });

    test('10000 → 10,000원', () {
      expect(formatPrice(10000), '10,000원');
    });

    test('500 → 500원 (세 자리 미만)', () {
      expect(formatPrice(500), '500원');
    });

    test('1000 → 1,000원', () {
      expect(formatPrice(1000), '1,000원');
    });

    test('0 → 0원', () {
      expect(formatPrice(0), '0원');
    });

    test('-1000 → -1,000원 (음수 price)', () {
      expect(formatPrice(-1000), '-1,000원');
    });

    test('-1200000 → -1,200,000원 (음수 큰 값)', () {
      expect(formatPrice(-1200000), '-1,200,000원');
    });
  });

  group('timeAgo', () {
    test('30초 전 → 방금 전', () {
      final dt = DateTime.now().toUtc().subtract(const Duration(seconds: 30));
      expect(timeAgo(dt), '방금 전');
    });

    test('5분 전 → 5분 전', () {
      final dt = DateTime.now().toUtc().subtract(const Duration(minutes: 5));
      expect(timeAgo(dt), '5분 전');
    });

    test('3시간 전 → 3시간 전', () {
      final dt = DateTime.now().toUtc().subtract(const Duration(hours: 3));
      expect(timeAgo(dt), '3시간 전');
    });

    test('2일 전 → 2일 전', () {
      final dt = DateTime.now().toUtc().subtract(const Duration(days: 2));
      expect(timeAgo(dt), '2일 전');
    });

    test('35일 전 → 1달 전', () {
      final dt = DateTime.now().toUtc().subtract(const Duration(days: 35));
      expect(timeAgo(dt), '1달 전');
    });

    test('미래 날짜(서버 클럭 스큐) → 방금 전', () {
      final future = DateTime.now().toUtc().add(const Duration(minutes: 5));
      expect(timeAgo(future), '방금 전');
    });
  });
}
