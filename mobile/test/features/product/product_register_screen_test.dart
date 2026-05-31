import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile/features/auth/data/models/user_model.dart';
import 'package:mobile/features/auth/domain/auth_notifier.dart';
import 'package:mobile/features/auth/domain/auth_state.dart';
import 'package:mobile/features/product/domain/product_register_notifier.dart';
import 'package:mobile/features/product/presentation/product_register_screen.dart';

// ─── Fake auth — 동네 설정된 사용자 ──────────────────────────────────────────

class _FakeAuth extends AuthNotifier {
  @override
  Future<AuthState> build() async => const Authenticated(
        user: UserModel(
          id: 'u1',
          email: 'a@a.com',
          role: 'user',
          isActive: true,
          nickname: '판매자',
          neighborhoodId: 7,
        ),
      );
}

// ─── Fake register notifier ───────────────────────────────────────────────────

class _FakeRegisterNotifier extends ProductRegisterNotifier {
  _FakeRegisterNotifier({required this.initialState});

  final ProductRegisterState initialState;

  @override
  ProductRegisterState build() => initialState;

  @override
  Future<void> register({
    required String title,
    required int price,
    required String category,
    String? description,
  }) async {
    // createdProductId를 null로 두어 피드로 이동하는 경로 검증
    state = state.copyWith(status: RegisterStatus.success);
  }
}

// ─── Helper ───────────────────────────────────────────────────────────────────

Widget _buildApp({ProductRegisterState? registerState}) {
  final router = GoRouter(
    initialLocation: '/product/register',
    routes: [
      GoRoute(
        path: '/product/register',
        builder: (context, state) => const ProductRegisterScreen(),
      ),
      GoRoute(
        path: '/feed',
        builder: (context, state) =>
            const Scaffold(body: Center(child: Text('피드'))),
      ),
      GoRoute(
        path: '/product/:productId',
        builder: (context, state) => Scaffold(
          body: Center(
              child: Text('상품상세:${state.pathParameters['productId']}')),
        ),
      ),
    ],
  );

  return ProviderScope(
    overrides: [
      authNotifierProvider.overrideWith(() => _FakeAuth()),
      productRegisterProvider.overrideWith(
        () => _FakeRegisterNotifier(
          initialState: registerState ?? const ProductRegisterState(),
        ),
      ),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

// ─── Tests ────────────────────────────────────────────────────────────────────

void main() {
  group('ProductRegisterScreen', () {
    testWidgets('초기 상태 — 등록 버튼 비활성화', (tester) async {
      await tester.pumpWidget(_buildApp());
      await tester.pump();

      final btn = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
      expect(btn.onPressed, isNull,
          reason: '필수 필드가 비어 있으면 버튼이 비활성화되어야 한다');
    });

    testWidgets('제목만 입력 — 버튼 여전히 비활성화', (tester) async {
      await tester.pumpWidget(_buildApp());
      await tester.pump();

      await tester.enterText(find.byType(TextField).at(0), '맥북 팝니다');
      await tester.pump();

      expect(
        tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
        isNull,
        reason: '카테고리·가격 미입력 시 여전히 비활성화',
      );
    });

    testWidgets('제목·카테고리·가격 모두 입력 후 버튼 활성화', (tester) async {
      await tester.pumpWidget(_buildApp());
      await tester.pump();

      await tester.enterText(find.byType(TextField).at(0), '맥북 팝니다');
      await tester.pump();

      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('전자기기').last);
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).at(1), '1200000');
      await tester.pump();

      expect(
        tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
        isNotNull,
        reason: '세 필드 모두 채워지면 버튼이 활성화되어야 한다',
      );
    });

    testWidgets('등록 성공(productId null) → 피드 화면으로 이동', (tester) async {
      await tester.pumpWidget(_buildApp());
      await tester.pump();

      await tester.enterText(find.byType(TextField).at(0), '자전거');
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('스포츠').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).at(1), '50000');
      await tester.pump();

      await tester.tap(find.byType(ElevatedButton));
      await tester.pumpAndSettle();

      expect(find.text('피드'), findsOneWidget,
          reason: 'createdProductId가 없으면 피드로 이동한다');
    });

    testWidgets('등록 성공(productId 있음) → 상품 상세 화면으로 이동', (tester) async {
      // productId를 가진 성공 상태를 직접 주입
      final fakeNotifier = _SuccessWithIdNotifier();
      final router = GoRouter(
        initialLocation: '/product/register',
        routes: [
          GoRoute(
            path: '/product/register',
            builder: (context, state) => const ProductRegisterScreen(),
          ),
          GoRoute(
            path: '/product/:productId',
            builder: (context, state) => Scaffold(
              body: Center(
                  child: Text('상품상세:${state.pathParameters['productId']}')),
            ),
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authNotifierProvider.overrideWith(() => _FakeAuth()),
            productRegisterProvider.overrideWith(() => fakeNotifier),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pump();

      await tester.enterText(find.byType(TextField).at(0), '상품');
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('기타').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).at(1), '1000');
      await tester.pump();

      await tester.tap(find.byType(ElevatedButton));
      await tester.pumpAndSettle();

      expect(find.textContaining('상품상세:product-123'), findsOneWidget,
          reason: 'createdProductId가 있으면 상품 상세로 이동한다');
    });

    testWidgets('업로드 중 — CircularProgressIndicator 표시, BottomAppBar 숨김',
        (tester) async {
      await tester.pumpWidget(_buildApp(
        registerState: const ProductRegisterState(
          status: RegisterStatus.uploadingImages,
          selectedImages: [],
          compressedCount: 0,
        ),
      ));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byType(BottomAppBar), findsNothing,
          reason: '진행 중에는 등록 버튼이 숨겨져야 한다');
    });

    testWidgets('압축 진행 중 — 이미지 압축 중 텍스트 표시', (tester) async {
      // selectedImages 3개, compressedCount 1 → 압축 단계
      await tester.pumpWidget(_buildApp(
        registerState: ProductRegisterState(
          status: RegisterStatus.uploadingImages,
          selectedImages: [XFile('a.jpg'), XFile('b.jpg'), XFile('c.jpg')],
          compressedCount: 1,
        ),
      ));
      await tester.pump();

      expect(find.textContaining('이미지 압축 중'), findsOneWidget);
      expect(find.textContaining('(1/3)'), findsOneWidget);
    });

    testWidgets('업로드 단계 — 이미지 업로드 중... 표시', (tester) async {
      // compressedCount == selectedImages.length → 업로드 단계
      await tester.pumpWidget(_buildApp(
        registerState: const ProductRegisterState(
          status: RegisterStatus.uploadingImages,
          selectedImages: [],
          compressedCount: 0,
        ),
      ));
      await tester.pump();

      expect(find.textContaining('이미지 업로드 중'), findsOneWidget);
    });

    testWidgets('submitting 상태 — 상품 등록 중... 텍스트', (tester) async {
      await tester.pumpWidget(_buildApp(
        registerState: const ProductRegisterState(
          status: RegisterStatus.submitting,
          selectedImages: [],
          compressedCount: 0,
        ),
      ));
      await tester.pump();

      expect(find.text('상품 등록 중...'), findsOneWidget);
    });

    testWidgets('이미지 추가 버튼 — 초기에 0/10 표시', (tester) async {
      await tester.pumpWidget(_buildApp());
      await tester.pump();

      expect(find.text('0/10'), findsOneWidget,
          reason: '초기 이미지 개수 표시가 올바르게 나와야 한다');
    });

    testWidgets('화면에 상품 등록 appbar 타이틀 표시', (tester) async {
      await tester.pumpWidget(_buildApp());
      await tester.pump();

      expect(find.text('상품 등록'), findsOneWidget);
    });
  });

  group('ProductRegisterState', () {
    test('isBusy — idle 상태는 false', () {
      const state = ProductRegisterState();
      expect(state.isBusy, isFalse);
    });

    test('isBusy — uploadingImages는 true', () {
      const state =
          ProductRegisterState(status: RegisterStatus.uploadingImages);
      expect(state.isBusy, isTrue);
    });

    test('isBusy — submitting은 true', () {
      const state = ProductRegisterState(status: RegisterStatus.submitting);
      expect(state.isBusy, isTrue);
    });

    test('isBusy — success는 false', () {
      const state = ProductRegisterState(status: RegisterStatus.success);
      expect(state.isBusy, isFalse);
    });

    test('copyWith — clearError가 true이면 errorMessage null', () {
      const state = ProductRegisterState(errorMessage: '에러 발생');
      final next = state.copyWith(clearError: true);
      expect(next.errorMessage, isNull);
    });

    test('copyWith — clearError가 false이면 errorMessage 유지', () {
      const state = ProductRegisterState(errorMessage: '에러 발생');
      final next = state.copyWith(compressedCount: 1);
      expect(next.errorMessage, '에러 발생');
    });

    test('createdProductId — copyWith로 설정 및 보존', () {
      const state = ProductRegisterState();
      final next = state.copyWith(createdProductId: 'product-123');
      expect(next.createdProductId, 'product-123');
    });
  });

  group('ProductRegisterNotifier', () {
    test('addImages — 10장 이하는 false 반환', () {
      final container = ProviderContainer(
        overrides: [
          productRegisterProvider.overrideWith(ProductRegisterNotifier.new),
          authNotifierProvider.overrideWith(() => _FakeAuth()),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(productRegisterProvider.notifier);

      final exceeded = notifier.addImages(
        List.generate(5, (i) => XFile('img_$i.jpg')),
      );
      expect(exceeded, isFalse);
      expect(container.read(productRegisterProvider).selectedImages.length, 5);
    });

    test('addImages — 10장 초과 시 true 반환하고 10장으로 잘림', () {
      final container = ProviderContainer(
        overrides: [
          productRegisterProvider.overrideWith(ProductRegisterNotifier.new),
          authNotifierProvider.overrideWith(() => _FakeAuth()),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(productRegisterProvider.notifier);

      final exceeded = notifier.addImages(
        List.generate(11, (i) => XFile('img_$i.jpg')),
      );
      expect(exceeded, isTrue);
      expect(
          container.read(productRegisterProvider).selectedImages.length, 10);
    });

    test('removeImage — 인덱스 항목 제거', () {
      final container = ProviderContainer(
        overrides: [
          productRegisterProvider.overrideWith(ProductRegisterNotifier.new),
          authNotifierProvider.overrideWith(() => _FakeAuth()),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(productRegisterProvider.notifier);
      notifier.addImages(List.generate(3, (i) => XFile('img_$i.jpg')));
      expect(
          container.read(productRegisterProvider).selectedImages.length, 3);

      notifier.removeImage(1);
      expect(
          container.read(productRegisterProvider).selectedImages.length, 2);
    });
  });
}

// ─── productId 있는 성공 Notifier ─────────────────────────────────────────────

class _SuccessWithIdNotifier extends ProductRegisterNotifier {
  @override
  ProductRegisterState build() => const ProductRegisterState();

  @override
  Future<void> register({
    required String title,
    required int price,
    required String category,
    String? description,
  }) async {
    state = state.copyWith(
      status: RegisterStatus.success,
      createdProductId: 'product-123',
    );
  }
}
