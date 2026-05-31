# Story 2.3 — Flutter 상품 상세 화면

**Status:** review

## Summary

`/product/:productId` 플레이스홀더를 실제 상세 화면으로 교체.
이미지 PageView 슬라이드, 상품 정보 전체 표시, 판매완료 비활성화 버튼, 채팅하기 플레이스홀더(Epic 4).
`features/product/` 신규 feature 디렉토리 생성.

## Acceptance Criteria

**Given** 피드에서 상품 카드를 탭했을 때
**When** 상품 상세 화면이 로드되면
**Then** 이미지 슬라이드·제목·가격·설명·카테고리·등록 시간·관심수·판매 상태·판매자 닉네임이 표시된다

**Given** 상품 이미지가 2장 이상일 때
**When** 이미지 영역을 좌우로 스와이프하면
**Then** 다음/이전 이미지로 전환된다
**And** 현재 이미지 순서를 나타내는 인디케이터(점)가 표시된다

**Given** 판매 상태가 `SOLD`인 상품일 때
**When** 상세 화면이 로드되면
**Then** "채팅하기" 버튼이 비활성화된다
**And** "판매완료" 배지가 표시된다

**Given** 비인증 사용자가 상세 화면을 볼 때
**When** 화면이 로드되면
**Then** 로그인 없이 모든 상품 정보가 정상 표시된다

---

## 파일 구조

### NEW — 새로 생성 (`features/product/` 신규 feature)

```
mobile/lib/features/product/data/models/product_detail_model.dart
mobile/lib/features/product/data/product_detail_repository.dart
mobile/lib/features/product/domain/product_detail_provider.dart
mobile/lib/features/product/presentation/product_detail_screen.dart
mobile/test/features/product/product_detail_model_test.dart
mobile/test/features/product/product_detail_screen_test.dart
```

### UPDATE — 수정

```
mobile/lib/core/router/app_router.dart  ← /product/:productId 플레이스홀더를 실제 화면으로 교체
```

---

## API 계약 (Story 2.1에서 구현 완료)

### GET /api/v1/products/{id}

**공개 엔드포인트 — 인증 불필요 (FR-2)**

**Response 200**
```json
{
  "id": "uuid-string",
  "seller_id": "uuid-string",
  "title": "아이폰 15 Pro 팝니다",
  "price": 1200000,
  "description": "3개월 사용한 깨끗한 제품입니다.",
  "category": "전자기기",
  "image_urls": ["https://r2.../a.jpg", "https://r2.../b.jpg"],
  "created_at": "2026-05-30T09:00:00Z",
  "like_count": 7,
  "status": "SALE",
  "seller_nickname": "당근이"
}
```

**에러**
- `404 PRODUCT_NOT_FOUND` — 존재하지 않는 상품 ID
- 공개 엔드포인트 — auth 헤더 불필요

---

## 구현 상세

### 1. ProductDetailModel (`data/models/product_detail_model.dart`)

```dart
import 'package:mobile/features/feed/data/models/product_model.dart';

class ProductDetailModel {
  const ProductDetailModel({
    required this.id,
    required this.sellerId,
    required this.title,
    required this.price,
    required this.category,
    required this.imageUrls,
    required this.createdAt,
    required this.likeCount,
    required this.status,
    this.description,
    this.sellerNickname,
  });

  final String id;
  final String sellerId;
  final String title;
  final int price;
  final String category;
  final List<String> imageUrls;
  final DateTime createdAt;
  final int likeCount;
  final String status;
  final String? description;
  final String? sellerNickname;

  bool get isSold => status == 'SOLD';
  bool get isReserved => status == 'RESERVED';

  factory ProductDetailModel.fromJson(Map<String, dynamic> json) =>
      ProductDetailModel(
        id: json['id'] as String,
        sellerId: json['seller_id'] as String,
        title: json['title'] as String,
        price: json['price'] as int,
        category: json['category'] as String,
        imageUrls: (json['image_urls'] as List<dynamic>)
            .map((e) => e as String)
            .toList(),
        createdAt: DateTime.parse(json['created_at'] as String),
        likeCount: json['like_count'] as int,
        status: json['status'] as String,
        description: json['description'] as String?,
        sellerNickname: json['seller_nickname'] as String?,
      );
}
```

`formatPrice` / `timeAgo` 함수는 `features/feed/data/models/product_model.dart`에서 import하여 재사용.

### 2. ProductDetailRepository (`data/product_detail_repository.dart`)

- `refreshDioProvider` 사용 (공개 엔드포인트, FR-2)
- `dioProvider` 사용 **금지**

```dart
class ProductDetailRepository {
  const ProductDetailRepository({required Dio publicDio})
      : _publicDio = publicDio; // ignore: prefer_initializing_formals

  final Dio _publicDio;

  Future<ProductDetailModel> getProduct(String productId) async {
    try {
      final resp = await _publicDio.get('/products/$productId');
      return ProductDetailModel.fromJson(
          resp.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }
}

final productDetailRepositoryProvider =
    Provider<ProductDetailRepository>((ref) {
  return ProductDetailRepository(publicDio: ref.watch(refreshDioProvider));
});
```

### 3. Provider (`domain/product_detail_provider.dart`)

단순 데이터 조회 + 변이 없음 → `FutureProvider.autoDispose.family` 사용 (AsyncNotifier family보다 간결).

```dart
final productDetailProvider =
    FutureProvider.autoDispose.family<ProductDetailModel, String>(
  (ref, productId) async {
    return ref
        .read(productDetailRepositoryProvider)
        .getProduct(productId);
  },
);
```

### 4. ProductDetailScreen (`presentation/product_detail_screen.dart`)

```dart
class ProductDetailScreen extends ConsumerWidget {
  const ProductDetailScreen({super.key, required this.productId});
  final String productId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailAsync = ref.watch(productDetailProvider(productId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('상품 상세'),
        backgroundColor: const Color(0xFFFF7043),
        foregroundColor: Colors.white,
      ),
      body: detailAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => _ErrorBody(
          message: err is AppError ? err.message : '오류가 발생했습니다.',
          onRetry: () => ref.invalidate(productDetailProvider(productId)),
        ),
        data: (product) => _DetailBody(product: product),
      ),
    );
  }
}
```

**_DetailBody 구성 (SingleChildScrollView + Column):**

```
1. _ImageSlider (PageView + 점 인디케이터) — 이미지 없으면 플레이스홀더
2. Padding 콘텐츠:
   - 판매 상태 배지 행 (RESERVED/SOLD)
   - 제목 (headline)
   - 가격 (formatPrice, bold)
   - Divider
   - 판매자 정보 행 (아이콘 + sellerNickname)
   - Divider
   - 카테고리
   - 등록 시간 (timeAgo)
   - 관심수
   - Divider
   - 상품 설명 (null이면 미표시)
3. 하단 고정 버튼 바 (채팅하기)
```

**_ImageSlider 구현:**

```dart
class _ImageSlider extends StatefulWidget {
  const _ImageSlider({required this.imageUrls});
  final List<String> imageUrls;

  @override
  State<_ImageSlider> createState() => _ImageSliderState();
}

class _ImageSliderState extends State<_ImageSlider> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    if (widget.imageUrls.isEmpty) {
      return Container(
        height: 300,
        color: Colors.grey.shade200,
        child: Icon(Icons.image_outlined, size: 80, color: Colors.grey.shade400),
      );
    }
    return SizedBox(
      height: 300,
      child: Stack(
        children: [
          PageView.builder(
            itemCount: widget.imageUrls.length,
            onPageChanged: (i) => setState(() => _currentIndex = i),
            itemBuilder: (_, i) => Image.network(
              widget.imageUrls[i],
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => Container(
                color: Colors.grey.shade200,
                child: Icon(Icons.image_outlined, color: Colors.grey.shade400),
              ),
            ),
          ),
          if (widget.imageUrls.length > 1)
            Positioned(
              bottom: 8,
              left: 0, right: 0,
              child: _DotIndicator(
                count: widget.imageUrls.length,
                current: _currentIndex,
              ),
            ),
        ],
      ),
    );
  }
}

class _DotIndicator extends StatelessWidget {
  const _DotIndicator({required this.count, required this.current});
  final int count;
  final int current;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(count, (i) => Container(
        width: 8, height: 8,
        margin: const EdgeInsets.symmetric(horizontal: 3),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: i == current ? Colors.white : Colors.white54,
        ),
      )),
    );
  }
}
```

**채팅하기 버튼 (하단 고정):**

```dart
BottomAppBar(
  child: Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    child: ElevatedButton(
      onPressed: product.isSold ? null : () => _onChatTap(context, ref),
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFFFF7043),
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(48),
      ),
      child: Text(product.isSold ? '판매완료' : '채팅하기'),
    ),
  ),
)

void _onChatTap(BuildContext context, WidgetRef ref) {
  final isAuth = ref.read(authNotifierProvider).valueOrNull?.isAuthenticated ?? false;
  if (!isAuth) {
    // FR-2: 비인증 → 로그인 유도
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('로그인이 필요합니다.')),
    );
    return;
  }
  // Story 4.x에서 구현
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('채팅하기 (Story 4.x에서 구현)')),
  );
}
```

**상태 배지 (RESERVED/SOLD):**

```dart
if (product.isReserved || product.isSold) ...[
  Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: product.isSold ? Colors.black54 : Colors.grey.shade600,
      borderRadius: BorderRadius.circular(4),
    ),
    child: Text(
      product.isSold ? '판매완료' : '예약중',
      style: const TextStyle(color: Colors.white, fontSize: 12),
    ),
  ),
  const SizedBox(height: 6),
],
```

### 5. app_router.dart 수정

`/product/:productId` 플레이스홀더를 실제 화면으로 교체:

```dart
import '../../features/product/presentation/product_detail_screen.dart';

GoRoute(
  path: '/product/:productId',
  builder: (context, state) {
    final id = state.pathParameters['productId']!;
    return ProductDetailScreen(productId: id);
  },
),
```

---

## 테스트 요구사항

### `test/features/product/product_detail_model_test.dart`

```dart
// 필수 테스트:
// - fromJson: 모든 필드 정상 파싱
// - fromJson: description/sellerNickname null 허용
// - fromJson: imageUrls 빈 리스트 허용
// - isSold: status=='SOLD' → true, 그 외 → false
// - isReserved: status=='RESERVED' → true, 그 외 → false
```

### `test/features/product/product_detail_screen_test.dart`

```dart
// 필수 테스트:
// - 로딩 상태 → CircularProgressIndicator 표시
// - 데이터 상태 → 제목·가격·설명·판매자닉네임 렌더링
// - SOLD 상품 → '판매완료' 배지 + 채팅하기 버튼 비활성화
// - RESERVED 상품 → '예약중' 배지 표시
// - 에러 상태 → 에러 메시지 + 재시도 버튼
// - 이미지 없음 → 플레이스홀더 표시
// - 이미지 1장 → 점 인디케이터 없음
// - 이미지 2장+ → 점 인디케이터 표시

// 테스트 패턴:
// FutureProvider.family 오버라이드:
// productDetailProvider('product-id').overrideWith((ref) async => testProduct)
```

---

## 개발자 가드레일

### MUST 따라야 할 패턴

1. **공개 엔드포인트 → `refreshDioProvider`**: detail API는 인증 불필요. `dioProvider` 사용 금지.
2. **`FutureProvider.autoDispose.family`**: 단순 조회 + parameter 있음 → 이 패턴 사용 (AsyncNotifier family보다 간결).
3. **`formatPrice` / `timeAgo` 재사용**: `features/feed/data/models/product_model.dart`에서 import. 중복 구현 금지.
4. **feature-first 구조**: `features/product/data/`, `features/product/domain/`, `features/product/presentation/` 신규 생성.
5. **StatefulWidget for PageView**: 이미지 슬라이더는 `_currentIndex` 상태가 필요하므로 `StatefulWidget` 사용.
6. **파일명 snake_case, 클래스명 PascalCase**.
7. **BottomAppBar**: 채팅하기 버튼은 Scaffold.bottomNavigationBar가 아닌 `bottomNavigationBar: BottomAppBar(...)`.

### MUST NOT

- `intl` 패키지 사용 금지 (pubspec.yaml에 없음)
- 외부 carousel/slider 패키지 사용 금지 — 빌트인 `PageView` 사용
- `dioProvider`(인증 Dio)를 product detail에 사용 금지
- `@riverpod` 어노테이션 사용 금지 (다른 provider들과 일관성)
- `StatelessWidget`에서 PageView currentIndex 관리 시도 금지 (State 필요)

### 비인증 사용자 처리

- 상세 화면 자체는 비인증 접근 가능 (FR-2)
- **중요**: 라우터 redirect는 `isAuthenticated` 체크를 함 → 비인증 사용자는 `/login`으로 리다이렉트됨
- 그러나 2.3에서는 비인증 사용자도 상세를 볼 수 있어야 하므로(FR-2) 라우터 가드에서 `/product/:productId`를 제외해야 할 수도 있음
- **현재 라우터 상태 확인 필수**: `redirect` 함수에서 `isAuthenticated == false`이면 `/login`으로 보냄 → 비인증 사용자가 `/product/:id`에 접근 불가
- **해결책**: redirect에서 `/product/` 경로를 인증 예외로 처리

```dart
// app_router.dart redirect 수정
if (!isAuthenticated) {
  // /product/:id는 공개 접근 허용 (FR-2)
  if (loc.startsWith('/product/')) return null;
  return loc == '/login' ? null : '/login';
}
```

### 이미지 슬라이더 엣지케이스

- `imageUrls.isEmpty` → 플레이스홀더 Container (아이콘만)
- `imageUrls.length == 1` → PageView 불필요, 단순 Image.network. 점 인디케이터 숨김.
- `imageUrls.length >= 2` → PageView + 점 인디케이터

### SOLD/RESERVED/SALE 버튼 상태

| status | 채팅하기 버튼 | 배지 |
|---|---|---|
| SALE | 활성화 | 없음 |
| RESERVED | 활성화 | "예약중" (회색) |
| SOLD | **비활성화** | "판매완료" (어두운 회색) |

---

## 이전 스토리 학습사항 (Story 2.2 + 코드리뷰)

1. **`refreshDioProvider` 필수**: 공개 엔드포인트에 `dioProvider` 사용 시 비인증 사용자 접근 불가.
2. **`FutureProvider.family` 오버라이드 패턴**:
   ```dart
   productDetailProvider('id').overrideWith((ref) async => testProduct)
   ```
3. **`loadMoreError` 교훈**: 에러를 UI에서 반드시 표시할 것 — 이번 스토리는 `AsyncError`만 있어 자동 처리됨.
4. **StatefulWidget for local UI state**: PageView의 currentIndex처럼 로컬 UI 상태는 StatefulWidget, 서버 데이터는 Provider.
5. **라우터 redirect 비인증 예외**: `/product/:id`는 공개 경로이므로 redirect에서 예외 처리 필요.
6. **`errorBuilder: (_, _, _)`**: Image.network errorBuilder의 3개 매개변수 모두 와일드카드 `_` 사용(lint 규칙).
7. **`ref.invalidate(provider(arg))`**: family provider 재시도 시 `ref.invalidate(productDetailProvider(productId))` 형태.

---

## 스프린트 상태 업데이트

`2-3-flutter-product-detail: ready-for-dev`
