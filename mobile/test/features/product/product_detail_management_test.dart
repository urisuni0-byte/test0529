import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile/features/auth/data/models/user_model.dart';
import 'package:mobile/features/auth/domain/auth_notifier.dart';
import 'package:mobile/features/auth/domain/auth_state.dart';
import 'package:mobile/features/product/data/models/product_detail_model.dart';
import 'package:mobile/features/product/domain/product_detail_provider.dart';
import 'package:mobile/features/product/presentation/product_detail_screen.dart';
import 'package:mobile/features/product/presentation/product_edit_screen.dart';

// ─── Fixtures ────────────────────────────────────────────────────────────────

const _kSellerId = 'seller-1';
const _kOtherId = 'other-1';

ProductDetailModel _product({
  String sellerId = _kSellerId,
  String status = 'SALE',
  int likeCount = 3,
}) =>
    ProductDetailModel(
      id: 'prod-1',
      sellerId: sellerId,
      title: '테스트 상품',
      price: 50000,
      category: '전자기기',
      imageUrls: const ['https://example.com/img.jpg'],
      createdAt: DateTime.now().toUtc().subtract(const Duration(hours: 2)),
      likeCount: likeCount,
      status: status,
      sellerNickname: '판매자닉',
    );

// ─── Fake auth ────────────────────────────────────────────────────────────────

class _FakeAuth extends AuthNotifier {
  _FakeAuth({required this.userId});

  // ignore: prefer_initializing_formals
  final String userId;

  @override
  Future<AuthState> build() async => Authenticated(
        user: UserModel(
          id: userId,
          email: '$userId@test.com',
          role: 'user',
          isActive: true,
          nickname: '테스터',
          neighborhoodId: 7,
        ),
      );
}

class _UnauthFakeAuth extends AuthNotifier {
  @override
  Future<AuthState> build() async => const Unauthenticated();
}

// ─── App builder ──────────────────────────────────────────────────────────────

Widget _buildDetailApp(
  AsyncValue<ProductDetailModel> value, {
  String currentUserId = _kOtherId,
  List<Override> extra = const [],
}) {
  final router = GoRouter(
    initialLocation: '/product/prod-1',
    routes: [
      GoRoute(
        path: '/product/:productId',
        builder: (context, state) =>
            ProductDetailScreen(productId: state.pathParameters['productId']!),
      ),
      GoRoute(
        path: '/product/:productId/edit',
        builder: (context, state) =>
            ProductEditScreen(product: state.extra as ProductDetailModel),
      ),
      GoRoute(
        path: '/feed',
        builder: (context, state) =>
            const Scaffold(body: Center(child: Text('피드'))),
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
        () => _FakeAuth(userId: currentUserId),
      ),
      ...extra,
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

// ─── Tests ────────────────────────────────────────────────────────────────────

void main() {
  group('ProductDetailScreen — 좋아요 버튼', () {
    testWidgets('초기 상태 — ActionBar 빈 하트 아이콘 표시', (tester) async {
      await tester.pumpWidget(
          _buildDetailApp(AsyncData(_product()), currentUserId: _kOtherId));
      await tester.pump();

      // ActionBar의 하트 버튼(IconButton)이 빈 하트인지 확인
      expect(
        find.widgetWithIcon(IconButton, Icons.favorite_border),
        findsOneWidget,
      );
      expect(
        find.widgetWithIcon(IconButton, Icons.favorite),
        findsNothing,
      );
    });

    testWidgets('비인증 사용자 — ActionBar 하트 탭 시 로그인 스낵바', (tester) async {
      final router = GoRouter(
        initialLocation: '/product/prod-1',
        routes: [
          GoRoute(
            path: '/product/:productId',
            builder: (context, state) =>
                ProductDetailScreen(productId: state.pathParameters['productId']!),
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            productDetailProvider('prod-1').overrideWith(
              (ref) async => _product(),
            ),
            authNotifierProvider.overrideWith(() => _UnauthFakeAuth()),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pump();

      // ActionBar의 IconButton(하트)을 탭
      await tester.tap(find.widgetWithIcon(IconButton, Icons.favorite_border));
      await tester.pump();

      expect(find.text('로그인이 필요합니다.'), findsOneWidget);
    });

    testWidgets('하트 버튼 — 관심수 텍스트 표시', (tester) async {
      await tester.pumpWidget(
          _buildDetailApp(AsyncData(_product(likeCount: 7)),
              currentUserId: _kOtherId));
      await tester.pump();

      // ActionBar에 likeCount 표시 (product.likeCount + _likeAdjustment)
      expect(find.text('7'), findsOneWidget);
    });
  });

  group('ProductDetailScreen — 판매자 버튼', () {
    testWidgets('본인 상품 — AppBar에 수정/삭제 아이콘 표시', (tester) async {
      await tester.pumpWidget(_buildDetailApp(
        AsyncData(_product(sellerId: _kSellerId)),
        currentUserId: _kSellerId,
      ));
      await tester.pump();

      expect(find.byIcon(Icons.edit_outlined), findsOneWidget);
      expect(find.byIcon(Icons.delete_outlined), findsOneWidget);
    });

    testWidgets('타인 상품 — AppBar에 수정/삭제 아이콘 없음', (tester) async {
      await tester.pumpWidget(_buildDetailApp(
        AsyncData(_product(sellerId: _kSellerId)),
        currentUserId: _kOtherId,
      ));
      await tester.pump();

      expect(find.byIcon(Icons.edit_outlined), findsNothing);
      expect(find.byIcon(Icons.delete_outlined), findsNothing);
    });

    testWidgets('삭제 버튼 탭 → 확인 다이얼로그 표시', (tester) async {
      await tester.pumpWidget(_buildDetailApp(
        AsyncData(_product(sellerId: _kSellerId)),
        currentUserId: _kSellerId,
      ));
      await tester.pump();

      await tester.tap(find.byIcon(Icons.delete_outlined));
      await tester.pumpAndSettle();

      expect(find.text('상품 삭제'), findsOneWidget);
      expect(find.text('정말 삭제하시겠습니까?'), findsOneWidget);
    });

    testWidgets('삭제 다이얼로그 취소 → 화면 유지', (tester) async {
      await tester.pumpWidget(_buildDetailApp(
        AsyncData(_product(sellerId: _kSellerId)),
        currentUserId: _kSellerId,
      ));
      await tester.pump();

      await tester.tap(find.byIcon(Icons.delete_outlined));
      await tester.pumpAndSettle();
      await tester.tap(find.text('취소'));
      await tester.pumpAndSettle();

      expect(find.byType(ProductDetailScreen), findsOneWidget);
    });
  });

  group('ProductDetailScreen — BottomAppBar', () {
    testWidgets('SALE 상품 — 채팅하기 버튼 활성화', (tester) async {
      await tester.pumpWidget(
          _buildDetailApp(AsyncData(_product(status: 'SALE'))));
      await tester.pump();

      final btn = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
      expect(btn.onPressed, isNotNull);
    });

    testWidgets('SOLD 상품 — 채팅하기 버튼 비활성화 + 판매완료 텍스트', (tester) async {
      await tester.pumpWidget(
          _buildDetailApp(AsyncData(_product(status: 'SOLD'))));
      await tester.pump();

      final btn = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
      expect(btn.onPressed, isNull);
      expect(find.text('판매완료'), findsWidgets);
    });
  });

  group('ProductEditScreen', () {
    Widget buildEditApp(ProductDetailModel product) {
      final router = GoRouter(
        initialLocation: '/product/prod-1/edit',
        routes: [
          GoRoute(
            path: '/product/:productId/edit',
            builder: (context, state) =>
                ProductEditScreen(product: product),
          ),
          GoRoute(
            path: '/product/:productId',
            builder: (context, state) =>
                ProductDetailScreen(productId: state.pathParameters['productId']!),
          ),
        ],
      );

      return ProviderScope(
        overrides: [
          authNotifierProvider.overrideWith(
            () => _FakeAuth(userId: _kSellerId),
          ),
          productDetailProvider('prod-1').overrideWith(
            (ref) async => product,
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      );
    }

    testWidgets('기존 제목·가격·설명·상태가 초기값으로 채워짐', (tester) async {
      final product = ProductDetailModel(
        id: 'prod-1',
        sellerId: _kSellerId,
        title: '기존 제목',
        price: 99000,
        category: '전자기기',
        imageUrls: const [],
        createdAt: DateTime.now().toUtc(),
        likeCount: 0,
        status: 'RESERVED',
        description: '기존 설명',
        sellerNickname: '판매자',
      );

      await tester.pumpWidget(buildEditApp(product));
      await tester.pump();

      expect(find.text('기존 제목'), findsOneWidget);
      expect(find.text('99000'), findsOneWidget);
      expect(find.text('기존 설명'), findsOneWidget);
    });

    testWidgets('상품 수정 AppBar 타이틀 표시', (tester) async {
      await tester.pumpWidget(buildEditApp(_product()));
      await tester.pump();

      expect(find.text('상품 수정'), findsOneWidget);
    });

    testWidgets('저장하기 버튼 표시', (tester) async {
      await tester.pumpWidget(buildEditApp(_product()));
      await tester.pump();

      expect(find.text('저장하기'), findsOneWidget);
    });
  });

  group('ProductDetailModel.copyWithLikeCount', () {
    test('likeCount만 변경되고 나머지 필드 보존', () {
      final original = _product(likeCount: 5);
      final updated = original.copyWithLikeCount(10);

      expect(updated.likeCount, 10);
      expect(updated.id, original.id);
      expect(updated.title, original.title);
      expect(updated.price, original.price);
      expect(updated.sellerId, original.sellerId);
    });
  });
}
