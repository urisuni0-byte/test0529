import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/product/data/models/product_detail_model.dart';

void main() {
  const fullJson = {
    'id': 'prod-uuid',
    'seller_id': 'seller-uuid',
    'title': '아이폰 15 Pro',
    'price': 1200000,
    'description': '3개월 사용한 깨끗한 제품입니다.',
    'category': '전자기기',
    'image_urls': ['https://r2.example.com/a.jpg', 'https://r2.example.com/b.jpg'],
    'created_at': '2026-05-30T09:00:00.000Z',
    'like_count': 7,
    'status': 'SALE',
    'seller_nickname': '당근이',
  };

  group('ProductDetailModel.fromJson', () {
    test('모든 필드를 정상 파싱한다', () {
      final m = ProductDetailModel.fromJson(fullJson);
      expect(m.id, 'prod-uuid');
      expect(m.sellerId, 'seller-uuid');
      expect(m.title, '아이폰 15 Pro');
      expect(m.price, 1200000);
      expect(m.description, '3개월 사용한 깨끗한 제품입니다.');
      expect(m.category, '전자기기');
      expect(m.imageUrls, ['https://r2.example.com/a.jpg', 'https://r2.example.com/b.jpg']);
      expect(m.createdAt, DateTime.utc(2026, 5, 30, 9, 0, 0));
      expect(m.likeCount, 7);
      expect(m.status, 'SALE');
      expect(m.sellerNickname, '당근이');
    });

    test('description null 허용', () {
      final json = {...fullJson, 'description': null};
      expect(ProductDetailModel.fromJson(json).description, isNull);
    });

    test('seller_nickname null 허용', () {
      final json = {...fullJson, 'seller_nickname': null};
      expect(ProductDetailModel.fromJson(json).sellerNickname, isNull);
    });

    test('image_urls 빈 리스트 허용', () {
      final json = {...fullJson, 'image_urls': <dynamic>[]};
      expect(ProductDetailModel.fromJson(json).imageUrls, isEmpty);
    });
  });

  group('ProductDetailModel 상태 게터', () {
    ProductDetailModel make(String status) => ProductDetailModel(
          id: 'x', sellerId: 's', title: 't', price: 100,
          category: 'c', imageUrls: const [], createdAt: DateTime.now(),
          likeCount: 0, status: status,
        );

    test('isSold: SOLD → true', () => expect(make('SOLD').isSold, isTrue));
    test('isSold: SALE → false', () => expect(make('SALE').isSold, isFalse));
    test('isSold: RESERVED → false', () => expect(make('RESERVED').isSold, isFalse));
    test('isReserved: RESERVED → true', () => expect(make('RESERVED').isReserved, isTrue));
    test('isReserved: SALE → false', () => expect(make('SALE').isReserved, isFalse));
  });
}
