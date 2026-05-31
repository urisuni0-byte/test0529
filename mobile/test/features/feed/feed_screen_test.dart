import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile/features/auth/domain/auth_notifier.dart';
import 'package:mobile/features/auth/domain/auth_state.dart';
import 'package:mobile/features/auth/data/models/user_model.dart';
import 'package:mobile/features/feed/data/models/product_model.dart';
import 'package:mobile/features/feed/domain/feed_notifier.dart';
import 'package:mobile/features/feed/presentation/feed_screen.dart';
import 'package:mobile/core/error/app_error.dart';

// ─── Fixtures ───────────────────────────────────────────────────────────────

ProductModel _product(String id, {String status = 'SALE'}) => ProductModel(
      id: id,
      sellerId: 'seller',
      title: '상품 $id',
      price: 10000,
      createdAt: DateTime.now().toUtc(),
      likeCount: 0,
      status: status,
    );

FeedState _stateWith(List<ProductModel> products, {int total = 0}) => FeedState(
      products: products,
      total: total == 0 ? products.length : total,
      currentPage: 1,
    );

// ─── Fake notifiers ─────────────────────────────────────────────────────────

class _FakeFeedNotifier extends FeedNotifier {
  _FakeFeedNotifier(this._result);
  final AsyncValue<FeedState> _result;

  @override
  Future<FeedState> build() async {
    state = _result;
    if (_result is AsyncLoading) {
      // Never completes — keeps the notifier in loading state for the test.
      await Completer<void>().future;
    }
    if (_result is AsyncError) throw (_result as AsyncError).error;
    return (_result as AsyncData<FeedState>).value;
  }

  @override
  Future<void> loadMore() async {}

  @override
  Future<void> refresh() async {}
}

class _FakeAuthNotifier extends AuthNotifier {
  _FakeAuthNotifier({int? neighborhoodId})
      : _neighborhoodId = neighborhoodId; // ignore: prefer_initializing_formals

  final int? _neighborhoodId;

  @override
  Future<AuthState> build() async {
    if (_neighborhoodId == null) return const Unauthenticated();
    return Authenticated(
      user: UserModel(
        id: 'user-1',
        email: 'test@test.com',
        role: 'user',
        isActive: true,
        nickname: '테스터',
        neighborhoodId: _neighborhoodId,
      ),
    );
  }
}

// ─── Router helper ──────────────────────────────────────────────────────────

final _navigatedRoutes = <String>[];

GoRouter _makeRouter() => GoRouter(
      initialLocation: '/feed',
      routes: [
        GoRoute(
          path: '/feed',
          builder: (_, _) => const FeedScreen(),
        ),
        GoRoute(
          path: '/product/:id',
          builder: (_, state) {
            _navigatedRoutes.add('/product/${state.pathParameters['id']}');
            return const Scaffold(body: Text('상세'));
          },
        ),
        GoRoute(
          path: '/neighborhood',
          builder: (_, _) => const Scaffold(body: Text('동네설정')),
        ),
      ],
    );

Widget _buildApp(
  AsyncValue<FeedState> feedState, {
  int? neighborhoodId = 7,
}) {
  return ProviderScope(
    overrides: [
      feedNotifierProvider
          .overrideWith(() => _FakeFeedNotifier(feedState)),
      authNotifierProvider
          .overrideWith(() => _FakeAuthNotifier(neighborhoodId: neighborhoodId)),
    ],
    child: MaterialApp.router(routerConfig: _makeRouter()),
  );
}

// ─── Tests ──────────────────────────────────────────────────────────────────

void main() {
  setUp(() => _navigatedRoutes.clear());

  group('FeedScreen', () {
    testWidgets('로딩 상태 → CircularProgressIndicator 표시', (tester) async {
      await tester.pumpWidget(
          _buildApp(const AsyncLoading<FeedState>()));
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('데이터 상태 → 상품 카드 목록 표시', (tester) async {
      final products = [_product('p1'), _product('p2')];
      await tester.pumpWidget(_buildApp(AsyncData(_stateWith(products))));
      await tester.pump();
      expect(find.text('상품 p1'), findsOneWidget);
      expect(find.text('상품 p2'), findsOneWidget);
    });

    testWidgets('빈 목록 → 안내 텍스트 표시', (tester) async {
      await tester.pumpWidget(_buildApp(AsyncData(_stateWith([]))));
      await tester.pump();
      expect(find.text('판매중인 상품이 없습니다.'), findsOneWidget);
    });

    testWidgets('에러 상태 → 에러 메시지와 재시도 버튼 표시', (tester) async {
      final err = const AppError(
          message: '서버 오류', code: AppErrorCode.serverError);
      await tester.pumpWidget(_buildApp(
          AsyncError(err, StackTrace.empty)));
      await tester.pump();
      expect(find.text('서버 오류'), findsOneWidget);
      expect(find.text('다시 시도'), findsOneWidget);
    });

    testWidgets('네트워크 에러 → SnackBar 표시', (tester) async {
      final err = const AppError(
          message: '네트워크 연결을 확인해 주세요.',
          code: AppErrorCode.networkError);
      await tester.pumpWidget(_buildApp(
          AsyncError(err, StackTrace.empty)));
      await tester.pump(); // 첫 번째 프레임
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.text('네트워크 연결을 확인해 주세요.'), findsWidgets);
    });

    testWidgets('카드 탭 → /product/:id 로 이동', (tester) async {
      final products = [_product('abc-123')];
      await tester.pumpWidget(_buildApp(AsyncData(_stateWith(products))));
      await tester.pump();
      await tester.tap(find.text('상품 abc-123'));
      await tester.pumpAndSettle();
      expect(_navigatedRoutes, contains('/product/abc-123'));
    });

    testWidgets('예약중 상품에 배지 표시', (tester) async {
      final products = [_product('r1', status: 'RESERVED')];
      await tester.pumpWidget(_buildApp(AsyncData(_stateWith(products))));
      await tester.pump();
      expect(find.text('예약중'), findsOneWidget);
    });

    testWidgets('동네 미설정 에러 → 동네 설정하기 버튼 표시', (tester) async {
      final err = const AppError(
          message: '동네를 먼저 설정해 주세요.',
          code: AppErrorCode.unknown);
      await tester.pumpWidget(_buildApp(
          AsyncError(err, StackTrace.empty),
          neighborhoodId: null));
      await tester.pump();
      expect(find.text('동네를 먼저 설정해 주세요.'), findsWidgets);
      expect(find.text('동네 설정하기'), findsOneWidget);
    });

    testWidgets('loadMoreError → 푸터에 에러 메시지와 재시도 버튼 표시', (tester) async {
      final loadMoreErr = const AppError(
          message: '추가 로드 실패', code: AppErrorCode.networkError);
      final stateWithError = FeedState(
        products: [_product('p1'), _product('p2')],
        total: 40,
        currentPage: 1,
        loadMoreError: loadMoreErr,
      );
      await tester.pumpWidget(_buildApp(AsyncData(stateWithError)));
      await tester.pump();
      expect(find.text('추가 로드 실패'), findsOneWidget);
      expect(find.text('다시 시도'), findsOneWidget);
    });

    testWidgets('빈 목록 → SingleChildScrollView로 감싸여 있음 (pull-to-refresh 가능)', (tester) async {
      await tester.pumpWidget(_buildApp(AsyncData(_stateWith([]))));
      await tester.pump();
      expect(find.byType(SingleChildScrollView), findsOneWidget);
    });
  });
}
