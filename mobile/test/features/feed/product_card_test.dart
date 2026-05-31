import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/feed/data/models/product_model.dart';
import 'package:mobile/features/feed/presentation/product_card.dart';

ProductModel _makeProduct({
  String status = 'SALE',
  String? thumbnailUrl,
  int likeCount = 5,
  int price = 10000,
}) =>
    ProductModel(
      id: 'prod-1',
      sellerId: 'seller-1',
      title: '테스트 상품',
      price: price,
      createdAt: DateTime.now().toUtc().subtract(const Duration(minutes: 10)),
      likeCount: likeCount,
      status: status,
      thumbnailUrl: thumbnailUrl,
    );

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('ProductCard', () {
    testWidgets('제목·가격·관심수를 렌더링한다', (tester) async {
      await tester.pumpWidget(_wrap(
        ProductCard(product: _makeProduct(price: 12000), onTap: () {}),
      ));
      expect(find.text('테스트 상품'), findsOneWidget);
      expect(find.text('12,000원'), findsOneWidget);
      expect(find.text('5'), findsOneWidget);
    });

    testWidgets('thumbnailUrl이 null이면 플레이스홀더를 표시한다', (tester) async {
      await tester.pumpWidget(_wrap(
        ProductCard(product: _makeProduct(), onTap: () {}),
      ));
      expect(find.byIcon(Icons.image_outlined), findsOneWidget);
    });

    testWidgets('isReserved가 true이면 예약중 배지를 표시한다', (tester) async {
      await tester.pumpWidget(_wrap(
        ProductCard(product: _makeProduct(status: 'RESERVED'), onTap: () {}),
      ));
      expect(find.text('예약중'), findsOneWidget);
    });

    testWidgets('isReserved가 false이면 예약중 배지를 표시하지 않는다', (tester) async {
      await tester.pumpWidget(_wrap(
        ProductCard(product: _makeProduct(status: 'SALE'), onTap: () {}),
      ));
      expect(find.text('예약중'), findsNothing);
    });

    testWidgets('탭하면 onTap 콜백을 호출한다', (tester) async {
      var tapped = false;
      await tester.pumpWidget(_wrap(
        ProductCard(product: _makeProduct(), onTap: () => tapped = true),
      ));
      await tester.tap(find.byType(InkWell));
      expect(tapped, isTrue);
    });

    testWidgets('경과 시간을 표시한다', (tester) async {
      await tester.pumpWidget(_wrap(
        ProductCard(product: _makeProduct(), onTap: () {}),
      ));
      expect(find.text('10분 전'), findsOneWidget);
    });
  });
}
