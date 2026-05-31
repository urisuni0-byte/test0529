# Story 2.2 — Flutter 메인 피드 화면

**Status:** review

## Summary

피드 화면 전면 구현: 동네별 상품 목록 무한 스크롤, Pull-to-Refresh, 카드 탭 → 상세 이동, 오프라인 토스트.
Story 2.1에서 완성된 `GET /api/v1/products` API를 소비한다.

## Acceptance Criteria

**Given** 앱 진입 시 동네가 설정된 상태일 때
**When** 피드 화면이 로드되면
**Then** 해당 동네의 상품 카드가 최신순으로 표시된다
**And** 각 카드에 썸네일·제목·가격·경과 시간·관심수가 표시된다
**And** `예약중` 상품 카드에는 "예약중" 배지가 표시된다

**Given** 피드를 스크롤하여 하단에 도달할 때
**When** 추가 상품이 있으면
**Then** 다음 20개가 자동으로 로드되어 목록에 추가된다
**And** 로드 중 하단에 로딩 인디케이터가 표시된다

**Given** 더 이상 로드할 상품이 없을 때
**When** 스크롤이 하단에 도달하면
**Then** 추가 로드 없이 목록 끝 안내가 표시된다

**Given** 피드를 아래로 당길 때 (Pull-to-refresh)
**When** 새로고침이 완료되면
**Then** 가장 최신 상품이 최상단에 노출된다

**Given** 상품 카드를 탭할 때
**When** 탭 이벤트가 발생하면
**Then** 해당 상품의 상세 화면(`/product/:id`)으로 이동한다

**Given** 네트워크가 없을 때
**When** 피드 화면에 진입하거나 새로고침하면
**Then** 오프라인 안내 Snackbar가 표시된다

---

## 파일 구조

### NEW — 새로 생성

```
mobile/lib/features/feed/data/models/product_model.dart
mobile/lib/features/feed/data/product_repository.dart
mobile/lib/features/feed/domain/feed_notifier.dart
mobile/lib/features/feed/presentation/product_card.dart
mobile/test/features/feed/product_model_test.dart
mobile/test/features/feed/product_card_test.dart
mobile/test/features/feed/feed_screen_test.dart
```

### UPDATE — 수정

```
mobile/lib/features/feed/presentation/feed_screen.dart  ← placeholder 전면 교체
mobile/lib/core/router/app_router.dart                  ← /product/:productId route 추가
```

---

## API 계약 (Story 2.1에서 구현 완료)

### GET /api/v1/products

**쿼리 파라미터**
```
neighborhood_id: int  (required)
page: int = 1         (ge=1)
limit: int = 20       (ge=1, le=100)
```

**Response 200**
```json
{
  "items": [
    {
      "id": "uuid-string",
      "seller_id": "uuid-string",
      "title": "아이폰 15 Pro 팝니다",
      "price": 1200000,
      "created_at": "2026-05-30T09:00:00Z",
      "like_count": 3,
      "status": "SALE",          // "SALE" | "RESERVED" | "SOLD"
      "thumbnail_url": "https://example.com/img.jpg"  // nullable
    }
  ],
  "total": 47,
  "page": 1,
  "limit": 20
}
```

**에러**
- `404 NEIGHBORHOOD_NOT_FOUND` — 존재하지 않는 neighborhood_id
- 공개 엔드포인트 — 인증 불필요

---

## 구현 상세

### 1. ProductModel (`data/models/product_model.dart`)

```dart
class ProductModel {
  const ProductModel({
    required this.id,
    required this.sellerId,
    required this.title,
    required this.price,
    required this.createdAt,
    required this.likeCount,
    required this.status,
    this.thumbnailUrl,
  });

  final String id;
  final String sellerId;
  final String title;
  final int price;
  final DateTime createdAt;
  final int likeCount;
  final String status;
  final String? thumbnailUrl;

  bool get isReserved => status == 'RESERVED';

  factory ProductModel.fromJson(Map<String, dynamic> json) => ProductModel(
        id: json['id'] as String,
        sellerId: json['seller_id'] as String,
        title: json['title'] as String,
        price: json['price'] as int,
        createdAt: DateTime.parse(json['created_at'] as String),
        likeCount: json['like_count'] as int,
        status: json['status'] as String,
        thumbnailUrl: json['thumbnail_url'] as String?,
      );
}
```

### 2. ProductListResponse (data/product_repository.dart 내부 클래스)

```dart
class ProductListResponse {
  const ProductListResponse({
    required this.items,
    required this.total,
    required this.page,
    required this.limit,
  });
  final List<ProductModel> items;
  final int total;
  final int page;
  final int limit;
}
```

### 3. ProductRepository (`data/product_repository.dart`)

- 공개 엔드포인트이므로 `refreshDioProvider`(인증 없는 Dio) 사용
- `dioProvider`(인증 Dio) 사용 **금지** — 비인증 사용자도 피드 열람 가능해야 함 (FR-2)

```dart
class ProductRepository {
  const ProductRepository({required Dio publicDio}) : _publicDio = publicDio;
  final Dio _publicDio;

  Future<ProductListResponse> getProducts({
    required int neighborhoodId,
    int page = 1,
    int limit = 20,
  }) async {
    try {
      final resp = await _publicDio.get('/products', queryParameters: {
        'neighborhood_id': neighborhoodId,
        'page': page,
        'limit': limit,
      });
      final data = resp.data as Map<String, dynamic>;
      final items = (data['items'] as List<dynamic>)
          .map((e) => ProductModel.fromJson(e as Map<String, dynamic>))
          .toList();
      return ProductListResponse(
        items: items,
        total: data['total'] as int,
        page: data['page'] as int,
        limit: data['limit'] as int,
      );
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }
}

final productRepositoryProvider = Provider<ProductRepository>((ref) {
  return ProductRepository(publicDio: ref.watch(refreshDioProvider));
});
```

### 4. FeedState & FeedNotifier (`domain/feed_notifier.dart`)

```dart
class FeedState {
  const FeedState({
    required this.products,
    required this.total,
    required this.currentPage,
    this.isLoadingMore = false,
    this.loadMoreError,
  });

  final List<ProductModel> products;
  final int total;
  final int currentPage;
  final bool isLoadingMore;
  final AppError? loadMoreError;

  bool get hasMore => products.length < total;

  FeedState copyWith({
    List<ProductModel>? products,
    int? total,
    int? currentPage,
    bool? isLoadingMore,
    AppError? loadMoreError,
    bool clearLoadMoreError = false,
  }) => FeedState(
        products: products ?? this.products,
        total: total ?? this.total,
        currentPage: currentPage ?? this.currentPage,
        isLoadingMore: isLoadingMore ?? this.isLoadingMore,
        loadMoreError: clearLoadMoreError ? null : (loadMoreError ?? this.loadMoreError),
      );
}

class FeedNotifier extends AutoDisposeAsyncNotifier<FeedState> {
  @override
  Future<FeedState> build() async {
    // watch — notifier re-builds when auth state changes (e.g., neighborhood update)
    final authAsync = ref.watch(authNotifierProvider);
    final neighborhoodId = authAsync.valueOrNull?.user?.neighborhoodId;
    if (neighborhoodId == null) {
      throw const AppError(
        message: '동네를 먼저 설정해 주세요.',
        code: AppErrorCode.unknown,
      );
    }
    final resp = await ref
        .read(productRepositoryProvider)
        .getProducts(neighborhoodId: neighborhoodId, page: 1);
    return FeedState(
      products: resp.items,
      total: resp.total,
      currentPage: 1,
    );
  }

  Future<void> loadMore() async {
    final current = state.valueOrNull;
    if (current == null || current.isLoadingMore || !current.hasMore) return;

    final neighborhoodId =
        ref.read(authNotifierProvider).valueOrNull?.user?.neighborhoodId;
    if (neighborhoodId == null) return;

    state = AsyncData(current.copyWith(isLoadingMore: true, clearLoadMoreError: true));
    try {
      final resp = await ref
          .read(productRepositoryProvider)
          .getProducts(neighborhoodId: neighborhoodId, page: current.currentPage + 1);
      state = AsyncData(current.copyWith(
        products: [...current.products, ...resp.items],
        total: resp.total,
        currentPage: current.currentPage + 1,
        isLoadingMore: false,
      ));
    } on AppError catch (e) {
      state = AsyncData(current.copyWith(isLoadingMore: false, loadMoreError: e));
    } catch (e) {
      state = AsyncData(current.copyWith(
        isLoadingMore: false,
        loadMoreError: AppError(message: e.toString(), code: AppErrorCode.unknown),
      ));
    }
  }

  Future<void> refresh() async {
    ref.invalidateSelf();
    await future;
  }
}

final feedNotifierProvider =
    AutoDisposeAsyncNotifierProvider<FeedNotifier, FeedState>(FeedNotifier.new);
```

**주의:** `AutoDisposeAsyncNotifier` 사용 — 피드를 벗어나면 상태 자동 해제.
`build()`에서 `ref.watch(authNotifierProvider)` — 동네 변경 시 피드 자동 재로드.

### 5. ProductCard (`presentation/product_card.dart`)

```dart
class ProductCard extends StatelessWidget {
  const ProductCard({super.key, required this.product, required this.onTap});
  final ProductModel product;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Thumbnail
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: product.thumbnailUrl != null
                  ? Image.network(
                      product.thumbnailUrl!,
                      width: 80, height: 80, fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _placeholder(),
                    )
                  : _placeholder(),
            ),
            const SizedBox(width: 12),
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    if (product.isReserved)
                      Container(
                        margin: const EdgeInsets.only(right: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade600,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text('예약중',
                            style: TextStyle(color: Colors.white, fontSize: 11)),
                      ),
                    Expanded(
                      child: Text(product.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 15)),
                    ),
                  ]),
                  const SizedBox(height: 4),
                  Text(_timeAgo(product.createdAt),
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                  const SizedBox(height: 4),
                  Text(_formatPrice(product.price),
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  const SizedBox(height: 4),
                  Row(children: [
                    Icon(Icons.favorite_border, size: 14, color: Colors.grey.shade500),
                    const SizedBox(width: 3),
                    Text('${product.likeCount}',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                  ]),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _placeholder() => Container(
        width: 80, height: 80,
        color: Colors.grey.shade200,
        child: Icon(Icons.image_outlined, color: Colors.grey.shade400),
      );
}

/// 경과 시간 포맷 (intl 패키지 없이 구현)
String _timeAgo(DateTime dt) {
  final diff = DateTime.now().toUtc().difference(dt.toUtc());
  if (diff.inMinutes < 1) return '방금 전';
  if (diff.inMinutes < 60) return '${diff.inMinutes}분 전';
  if (diff.inHours < 24) return '${diff.inHours}시간 전';
  if (diff.inDays < 30) return '${diff.inDays}일 전';
  return '${diff.inDays ~/ 30}달 전';
}

/// 가격 포맷 — intl 없이 직접 구현
String _formatPrice(int price) {
  final s = price.toString();
  final buf = StringBuffer();
  for (int i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
    buf.write(s[i]);
  }
  return '${buf}원';
}
```

### 6. FeedScreen (`presentation/feed_screen.dart`) — 전면 교체

```dart
class FeedScreen extends ConsumerWidget {
  const FeedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feedAsync = ref.watch(feedNotifierProvider);

    // 네트워크 에러 → Snackbar 토스트
    ref.listen(feedNotifierProvider, (_, next) {
      if (next case AsyncError(:final error)) {
        if (error is AppError && error.code == AppErrorCode.networkError) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(error.message)),
          );
        }
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('피드'),
        backgroundColor: const Color(0xFFFF7043),
        foregroundColor: Colors.white,
      ),
      body: feedAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => _ErrorView(
          message: err is AppError ? err.message : '오류가 발생했습니다.',
          onRetry: () => ref.invalidate(feedNotifierProvider),
        ),
        data: (feedState) => RefreshIndicator(
          onRefresh: () => ref.read(feedNotifierProvider.notifier).refresh(),
          child: feedState.products.isEmpty
              ? const _EmptyView()
              : _FeedListView(state: feedState),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => requireNeighborhood(context, ref,
            onHasNeighborhood: () {
          // Story 3.2에서 구현
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('글쓰기 (Story 3.2에서 구현)')),
          );
        }),
        backgroundColor: const Color(0xFFFF7043),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.edit),
        label: const Text('글쓰기'),
      ),
    );
  }
}
```

`_FeedListView`는 `ConsumerStatefulWidget`으로 구현하여 `ScrollController`로 스크롤 끝 감지 후 `loadMore()` 호출:

```dart
class _FeedListView extends ConsumerStatefulWidget {
  const _FeedListView({required this.state});
  final FeedState state;

  @override
  ConsumerState<_FeedListView> createState() => _FeedListViewState();
}

class _FeedListViewState extends ConsumerState<_FeedListView> {
  final _ctrl = ScrollController();

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(_onScroll);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_ctrl.position.pixels >= _ctrl.position.maxScrollExtent - 200) {
      ref.read(feedNotifierProvider.notifier).loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    // AsyncValue watch 대신 state를 직접 watch하여 isLoadingMore 반응
    final feedState = ref.watch(feedNotifierProvider).valueOrNull ?? widget.state;
    final itemCount = feedState.products.length + 1; // +1 for footer

    return ListView.separated(
      controller: _ctrl,
      physics: const AlwaysScrollableScrollPhysics(),  // pull-to-refresh 활성화
      itemCount: itemCount,
      separatorBuilder: (_, __) => const Divider(height: 1, indent: 16),
      itemBuilder: (context, index) {
        if (index < feedState.products.length) {
          final product = feedState.products[index];
          return ProductCard(
            product: product,
            onTap: () => context.push('/product/${product.id}'),
          );
        }
        // Footer
        if (feedState.isLoadingMore) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (!feedState.hasMore && feedState.products.isNotEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: Text('마지막 상품입니다.',
                  style: TextStyle(color: Colors.grey, fontSize: 13)),
            ),
          );
        }
        return const SizedBox.shrink();
      },
    );
  }
}
```

`_ErrorView`, `_EmptyView`는 간단한 StatelessWidget으로 구현.

### 7. app_router.dart 수정

`/product/:productId` route 추가 (Story 2.3에서 실제 구현):

```dart
GoRoute(
  path: '/product/:productId',
  builder: (context, state) {
    final id = state.pathParameters['productId']!;
    return Scaffold(
      appBar: AppBar(title: const Text('상품 상세')),
      body: Center(child: Text('상품 상세 화면 (Story 2.3에서 구현)\nID: $id')),
    );
  },
),
```

---

## 테스트 요구사항

### `test/features/feed/product_model_test.dart`

```dart
// 필수 테스트:
// - fromJson: 모든 필드 정상 파싱
// - fromJson: thumbnail_url null 허용
// - isReserved: status=='RESERVED' → true, 그 외 → false
// - _timeAgo 헬퍼: 1분 미만 → '방금 전', 분/시간/일 단위 계산
// - _formatPrice 헬퍼: 1200000 → '1,200,000원', 10000 → '10,000원'
```

### `test/features/feed/product_card_test.dart`

```dart
// 필수 테스트:
// - 제목·가격·관심수 렌더링
// - thumbnailUrl == null 시 플레이스홀더 표시
// - isReserved == true 시 '예약중' 배지 표시
// - onTap 콜백 호출
```

### `test/features/feed/feed_screen_test.dart`

```dart
// 필수 테스트:
// - 로딩 상태 → CircularProgressIndicator 표시
// - 데이터 상태 → 상품 카드 목록 표시
// - 빈 목록 → 안내 텍스트 표시
// - 에러 상태 → 에러 메시지 + 재시도 버튼 표시
// - 네트워크 에러 → SnackBar 표시
// - 카드 탭 → GoRouter context.push('/product/{id}') 호출 검증
```

**테스트 패턴** (기존 `neighborhood_picker_screen_test.dart`와 동일):

```dart
class _FakeFeedNotifier extends FeedNotifier {
  _FakeFeedNotifier(this._result);
  final AsyncValue<FeedState> _result;

  @override
  Future<FeedState> build() async {
    state = _result;
    return _result.requireValue;
  }

  @override
  Future<void> loadMore() async {}

  @override
  Future<void> refresh() async {}
}

Widget _buildApp(AsyncValue<FeedState> feedState) {
  return ProviderScope(
    overrides: [
      feedNotifierProvider.overrideWith(() => _FakeFeedNotifier(feedState)),
      authNotifierProvider.overrideWith(() => _fakeAuthNotifier),
    ],
    child: MaterialApp.router(routerConfig: _testRouter),
  );
}
```

GoRouter 테스트에는 `MaterialApp.router`와 테스트용 `GoRouter` 인스턴스를 사용한다.

---

## 개발자 가드레일

### MUST 따라야 할 기존 패턴

1. **공개 엔드포인트 → `refreshDioProvider`**: 피드는 `GET /products` (공개), `dioProvider` 사용 금지
2. **Riverpod `AsyncNotifier` 패턴**: `NeighborhoodNotifier`와 동일 구조 준수
3. **`AppError.fromDioException`**: 모든 `DioException` 변환에 이 팩토리 사용
4. **파일명 snake_case, 클래스명 PascalCase**: `product_card.dart` / `ProductCard`
5. **feature-first 구조**: `features/feed/data/`, `features/feed/domain/`, `features/feed/presentation/`
6. **`authNotifierProvider.watch`** — `build()`에서 watch, 이후에는 `read` 사용
7. **`context.push()`** — go_router 네비게이션 (import `'package:go_router/go_router.dart'`)

### MUST NOT

- `intl` 패키지 사용 금지 (pubspec.yaml에 없음) — 가격/시간 포맷은 직접 구현
- `riverpod_generator`/`@riverpod` 어노테이션 사용 금지 (다른 Notifier들과 일관성 유지)
- `dioProvider`(인증 Dio)를 공개 엔드포인트에 사용 금지
- `FeedNotifier`에서 `AsyncNotifier` 대신 `AutoDisposeAsyncNotifier` 사용 (피드 벗어날 때 자동 해제)

### 동네 없는 사용자 처리

- `neighborhoodId == null`이면 `build()`에서 `AppError` throw → 피드 에러 상태
- 에러 뷰에 "동네를 설정해 주세요" 메시지 + `/neighborhood` 이동 버튼 표시
- 비인증 사용자(FR-2): `authAsync.valueOrNull?.user`가 null → neighborhoodId null → 동일 처리

### Story 2.3 의존성

- `/product/:productId` route는 이 스토리에서 **플레이스홀더**로 추가
- `ProductDetailScreen`은 2.3에서 구현 — 지금은 Scaffold + 텍스트로 대체

---

## 이전 스토리 학습사항 (Story 2.1 코드리뷰 결과)

1. **Query 파라미터 검증**: FastAPI에서 `Query(ge=1, le=100)` 필요했음 → Flutter 측에서도 `limit`을 1~100 범위로 고정 (20 사용)
2. **에러 형식**: 서버 에러는 `{"detail": "...", "code": "..."}` flat 형식, `AppError.fromDioException`이 이미 처리함
3. **`refreshDioProvider`**: 공개 엔드포인트는 반드시 이 provider 사용 (neighborhood_repository.dart 참조)
4. **`authNotifierProvider.watch` in `build()`**: 동네 변경 시 자동 재로드를 위해 필수
5. **Cascade 전략**: 기존 products 테이블은 `neighborhood_id NOT NULL` — null인 경우 서버에서 404 반환함

---

## 스프린트 상태 업데이트

`2-2-flutter-feed-screen: ready-for-dev`
