import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile/core/error/app_error.dart';
import 'package:mobile/features/auth/data/models/user_model.dart';
import 'package:mobile/features/auth/domain/auth_notifier.dart';
import 'package:mobile/features/auth/domain/auth_state.dart';
import 'package:mobile/features/product/data/models/product_detail_model.dart';
import 'package:mobile/features/product/domain/product_detail_provider.dart';
import 'package:mobile/features/product/presentation/product_detail_screen.dart';

// ─── Fixtures ───────────────────────────────────────────────────────────────

ProductDetailModel _product({
  String status = 'SALE',
  List<String> imageUrls = const ['https://example.com/img.jpg'],
  String? sellerNickname = '당근이',
  String? description = '좋은 상품입니다.',
}) =>
    ProductDetailModel(
      id: 'prod-1',
      sellerId: 'seller-1',
      title: '테스트 상품',
      price: 50000,
      category: '전자기기',
      imageUrls: imageUrls,
      createdAt: DateTime.now().toUtc().subtract(const Duration(hours: 2)),
      likeCount: 3,
      status: status,
      description: description,
      sellerNickname: sellerNickname,
    );

// ─── Fake auth notifier ─────────────────────────────────────────────────────

class _FakeAuthNotifier extends AuthNotifier {
  _FakeAuthNotifier({this.authenticated = true});
  final bool authenticated;

  @override
  Future<AuthState> build() async {
    if (!authenticated) return const Unauthenticated();
    return Authenticated(
      user: const UserModel(
        id: 'user-1',
        email: 'test@test.com',
        role: 'user',
        isActive: true,
        nickname: '테스터',
        neighborhoodId: 7,
      ),
    );
  }
}

// ─── Router + ProviderScope helper ──────────────────────────────────────────

Widget _buildApp(
  AsyncValue<ProductDetailModel> value, {
  bool authenticated = true,
}) {
  final router = GoRouter(
    initialLocation: '/product/prod-1',
    routes: [
      GoRoute(
        path: '/product/:productId',
        builder: (_, state) => ProductDetailScreen(
          productId: state.pathParameters['productId']!,
        ),
      ),
    ],
  );

  return ProviderScope(
    overrides: [
      productDetailProvider('prod-1').overrideWith((ref) async {
        if (value is AsyncLoading) await Completer<void>().future;
        if (value is AsyncError) throw (value as AsyncError).error;
        return (value as AsyncData<ProductDetailModel>).value;
      }),
      authNotifierProvider.overrideWith(
        () => _FakeAuthNotifier(authenticated: authenticated),
      ),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

// ─── Tests ──────────────────────────────────────────────────────────────────

void main() {
  group('ProductDetailScreen', () {
    testWidgets('로딩 상태 → CircularProgressIndicator', (tester) async {
      await tester.pumpWidget(
          _buildApp(const AsyncLoading<ProductDetailModel>()));
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('데이터 → 제목·가격·설명·판매자닉네임 렌더링', (tester) async {
      await tester.pumpWidget(_buildApp(AsyncData(_product())));
      await tester.pump();
      expect(find.text('테스트 상품'), findsOneWidget);
      expect(find.text('50,000원'), findsOneWidget);
      expect(find.text('좋은 상품입니다.'), findsOneWidget);
      expect(find.text('당근이'), findsOneWidget);
    });

    testWidgets('SOLD 상품 → 판매완료 배지 + 채팅하기 버튼 비활성화', (tester) async {
      await tester.pumpWidget(_buildApp(AsyncData(_product(status: 'SOLD'))));
      await tester.pump();
      // 배지: 판매완료 텍스트가 화면에 있음
      expect(find.text('판매완료'), findsWidgets);
      // ElevatedButton이 비활성화되어 있으면 onPressed == null
      final btn = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
      expect(btn.onPressed, isNull);
    });

    testWidgets('RESERVED 상품 → 예약중 배지 표시', (tester) async {
      await tester.pumpWidget(
          _buildApp(AsyncData(_product(status: 'RESERVED'))));
      await tester.pump();
      expect(find.text('예약중'), findsOneWidget);
    });

    testWidgets('에러 상태 → 에러 메시지 + 재시도 버튼', (tester) async {
      final err = const AppError(
          message: '상품을 찾을 수 없습니다.', code: AppErrorCode.unknown);
      await tester.pumpWidget(
          _buildApp(AsyncError(err, StackTrace.empty)));
      await tester.pump();
      expect(find.text('상품을 찾을 수 없습니다.'), findsOneWidget);
      expect(find.text('다시 시도'), findsOneWidget);
    });

    testWidgets('이미지 없음 → 플레이스홀더 표시', (tester) async {
      await tester.pumpWidget(
          _buildApp(AsyncData(_product(imageUrls: const []))));
      await tester.pump();
      expect(find.byIcon(Icons.image_outlined), findsOneWidget);
    });

    testWidgets('이미지 1장 → PageView 없이 Image.network, 점 인디케이터 없음', (tester) async {
      await tester.pumpWidget(
          _buildApp(AsyncData(_product(imageUrls: const ['https://example.com/a.jpg']))));
      await tester.pump();
      // 1장일 때는 PageView가 아닌 단순 Image.network 사용
      expect(find.byType(PageView), findsNothing);
      // Stack(Positioned)이 없으므로 점 인디케이터도 없음
      expect(find.byType(Positioned), findsNothing);
    });

    testWidgets('이미지 2장+ → PageView + 점 인디케이터 표시', (tester) async {
      await tester.pumpWidget(_buildApp(AsyncData(_product(
          imageUrls: const [
            'https://example.com/a.jpg',
            'https://example.com/b.jpg',
          ]))));
      await tester.pump();
      expect(find.byType(PageView), findsOneWidget);
      // 2개 점: 인디케이터 Row가 존재
      expect(find.byType(Row), findsWidgets);
    });

    testWidgets('description null → 설명 영역 미표시', (tester) async {
      await tester.pumpWidget(
          _buildApp(AsyncData(_product(description: null))));
      await tester.pump();
      expect(find.text('좋은 상품입니다.'), findsNothing);
    });

    testWidgets('sellerNickname null → 닉네임 영역 미표시', (tester) async {
      await tester.pumpWidget(
          _buildApp(AsyncData(_product(sellerNickname: null))));
      await tester.pump();
      expect(find.text('당근이'), findsNothing);
    });
  });
}
