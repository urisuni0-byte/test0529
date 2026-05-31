---
baseline_commit: NO_VCS
---

# Story 3.4 — Flutter 상품 관리 UI (관심·수정·삭제)

**Status:** review

## Story

As a user,
I want to like products I'm interested in and manage my own listings,
So that I can save items to review later and keep my listings up to date.

## Acceptance Criteria

**Given** 인증된 사용자가 상품 상세 화면에서 하트 버튼을 탭할 때
**When** 관심 등록 API 호출이 성공하면
**Then** 하트 아이콘이 채워지고 관심 수가 1 증가한다
**And** 이미 관심 등록된 상품에서 다시 탭하면 해제되고 수가 1 감소한다

**Given** 비인증 사용자가 하트 버튼을 탭할 때
**When** 탭 이벤트가 발생하면
**Then** 로그인 유도 스낵바가 표시된다

**Given** 판매자가 본인 상품 상세 화면에 진입할 때
**When** 화면이 로드되면
**Then** AppBar에 수정 버튼(연필 아이콘)과 삭제 버튼(쓰레기통 아이콘)이 표시된다
**And** 타인의 상품에서는 해당 버튼이 표시되지 않는다

**Given** 판매자가 수정 버튼을 탭할 때
**When** 수정 화면이 로드되면
**Then** 기존 제목·가격·설명·판매 상태가 입력 필드에 채워진다
**And** 저장 후 상세 화면이 수정된 내용으로 즉시 갱신된다

**Given** 판매자가 삭제 버튼을 탭할 때
**When** 확인 다이얼로그에서 삭제를 선택하면
**Then** 상품이 삭제되고 피드 화면으로 이동한다
**And** 피드에서 해당 상품 카드가 즉시 사라진다 (feedNotifierProvider invalidate)

## Tasks / Subtasks

- [x] Task 1: ProductManagementRepository 신규 생성 (AC: 1, 4, 5)
  - [x] `likeProduct(productId)` → POST /products/{id}/likes (201/409)
  - [x] `unlikeProduct(productId)` → DELETE /products/{id}/likes (204/404)
  - [x] `updateProduct(productId, data)` → PATCH /products/{id} → ProductDetailModel
  - [x] `deleteProduct(productId)` → DELETE /products/{id}
  - [x] `dioProvider` 사용 (4개 엔드포인트 모두 인증 필수)

- [x] Task 2: ProductDetailScreen → ConsumerStatefulWidget 변환 + 좋아요 UI (AC: 1, 2, 3)
  - [x] `ConsumerWidget` → `ConsumerStatefulWidget` (로컬 좋아요 상태: `_isLiked`, `_likeAdjustment`)
  - [x] BottomAppBar: 하트 버튼(왼쪽) + 채팅하기 버튼(오른쪽) 레이아웃으로 수정 (`_ActionBar`)
  - [x] 하트 토글 로직: API 호출 + 낙관적 로컬 상태 업데이트
  - [x] 비인증 → 로그인 스낵바
  - [x] AppBar: 판매자 본인인 경우 edit/delete 아이콘 버튼 표시

- [x] Task 3: ProductEditScreen 신규 생성 (AC: 4)
  - [x] `/product/:productId/edit` 라우트 추가
  - [x] 기존 값 pre-fill: 제목, 가격, 설명, 판매상태(드롭다운)
  - [x] PATCH API 호출 후 `ref.invalidate(productDetailProvider(productId))` + `context.pop()`
  - [x] 네트워크 오류 시 스낵바 표시 + 폼 보존

- [x] Task 4: 삭제 기능 (AC: 5)
  - [x] AppBar 삭제 버튼 → `showDialog` 확인
  - [x] DELETE API → `ref.invalidate(feedNotifierProvider)` → `context.go('/feed')`
  - [x] 오류 시 스낵바

- [x] Task 5: 라우터 업데이트 (AC: 4)
  - [x] `/product/:productId/edit` 라우트를 `/product/:productId` 앞에 추가

- [x] Task 6: 테스트 추가 (AC: 1~5)
  - [x] `product_detail_management_test.dart` 신규 생성 (13개 테스트)
  - [x] 기존 `product_detail_screen_test.dart` 회귀 확인 (9개 모두 통과)

---

## Dev Notes

### 핵심 사항 요약

1. **Flutter 전용 스토리** — 백엔드 변경 없음 (Story 3.3에서 모든 API 구현 완료)
2. **ConsumerStatefulWidget 변환** — 좋아요 로컬 상태(isLiked, likeCount)를 StatefulWidget State에서 관리
3. **is_liked 서버 미지원** — MVP 한계: 최초 진입 시 좋아요 초기 상태를 서버에서 받지 않음. `_isLiked = false`로 시작, 사용자 탭으로만 토글됨.
4. **낙관적 업데이트** — API 호출 전 UI 즉시 업데이트 → 실패 시 원래 상태로 복원
5. **`dioProvider`** — 관심·수정·삭제 4개 엔드포인트 모두 인증 필수. `refreshDioProvider` 사용 금지.
6. **`productDetailProvider` invalidate** — 수정 성공 후 `ref.invalidate(productDetailProvider(productId))`로 상세 화면 즉시 갱신

### 파일 구조

**NEW — 새로 생성:**
```
mobile/lib/features/product/data/product_management_repository.dart
mobile/lib/features/product/presentation/product_edit_screen.dart
mobile/test/features/product/product_detail_management_test.dart
```

**UPDATE — 수정:**
```
mobile/lib/features/product/presentation/product_detail_screen.dart  ← 대규모 수정
mobile/lib/core/router/app_router.dart                              ← edit 라우트 추가
```

### 기존 코드 컨텍스트 (반드시 보존)

**`product_detail_screen.dart` 현재 상태:**
- `ConsumerWidget` → `ConsumerStatefulWidget`으로 변환 필요
- `productDetailProvider('id')` — `FutureProvider.autoDispose.family<ProductDetailModel, String>` (변경 불필요)
- `_ChatBar` — 하단 채팅 버튼만 있음 → 하트 버튼 추가
- `_onChatTap` — 비인증 체크 로직 이미 있음 → 하트에도 동일 패턴 적용

**`product_detail_screen_test.dart` 기존 테스트:**
- `ConsumerWidget` 기반으로 작성됨
- `ConsumerStatefulWidget` 변환 후에도 동일하게 동작해야 함 (회귀 없음)
- `_FakeAuthNotifier` 재사용 가능

**`product_detail_repository.dart` 현재:**
- `refreshDioProvider` 사용 (공개 엔드포인트) — 그대로 유지
- 좋아요/수정/삭제는 별도 `ProductManagementRepository` 사용 (dioProvider)

**`feed_notifier.dart`:**
- `feedNotifierProvider` is `AutoDisposeAsyncNotifierProvider` 
- `ref.invalidate(feedNotifierProvider)` — 삭제 성공 후 호출하면 피드 자동 갱신

**라우터 현재 상태:**
- `/product/register` → ProductRegisterScreen (이미 `/product/:productId` 앞에 있음)
- `/product/:productId` → ProductDetailScreen
- `/product/:productId/edit`는 `/product/:productId`와 세그먼트 수가 달라서 순서 무관하지만 앞에 선언

---

## API 계약

### POST /api/v1/products/{id}/likes (관심 등록)
- **201** — 등록 성공
- **409 LIKE_ALREADY_EXISTS** — 이미 등록됨 (→ isLiked=true로 처리)
- **401** — 미인증

### DELETE /api/v1/products/{id}/likes (관심 해제)
- **204** — 해제 성공
- **404 LIKE_NOT_FOUND** — 등록 안 됨 (→ isLiked=false로 처리)
- **401** — 미인증

### PATCH /api/v1/products/{id} (수정)
```dart
// body: title?, price?, description?, status?
final resp = await _dio.patch('/products/$productId', data: data);
return ProductDetailModel.fromJson(resp.data as Map<String, dynamic>);
```
- **200** — 수정된 ProductDetail 반환
- **403 FORBIDDEN** — 타인 상품
- **404 PRODUCT_NOT_FOUND** — 상품 없음

### DELETE /api/v1/products/{id} (삭제)
- **204** — 삭제 성공 (빈 바디)
- **403 FORBIDDEN** — 타인 상품
- **404 PRODUCT_NOT_FOUND** — 상품 없음

---

## 구현 상세

### 1. `product_management_repository.dart` (NEW)

```dart
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/error/app_error.dart';
import '../../../core/network/api_client.dart';
import 'models/product_detail_model.dart';

class ProductManagementRepository {
  const ProductManagementRepository({required Dio authDio}) : _dio = authDio;
  final Dio _dio;

  Future<void> likeProduct(String productId) async {
    try {
      await _dio.post('/products/$productId/likes');
    } on DioException catch (e) {
      // 409(중복) → 이미 liked 상태, 호출자가 처리
      throw AppError.fromDioException(e);
    }
  }

  Future<void> unlikeProduct(String productId) async {
    try {
      await _dio.delete('/products/$productId/likes');
    } on DioException catch (e) {
      // 404(없음) → 이미 unliked, 호출자가 처리
      throw AppError.fromDioException(e);
    }
  }

  Future<ProductDetailModel> updateProduct(
    String productId,
    Map<String, dynamic> data,
  ) async {
    try {
      final resp = await _dio.patch('/products/$productId', data: data);
      return ProductDetailModel.fromJson(resp.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }

  Future<void> deleteProduct(String productId) async {
    try {
      await _dio.delete('/products/$productId');
    } on DioException catch (e) {
      throw AppError.fromDioException(e);
    }
  }
}

final productManagementRepositoryProvider =
    Provider<ProductManagementRepository>((ref) {
  return ProductManagementRepository(authDio: ref.watch(dioProvider));
});
```

### 2. `product_detail_screen.dart` 변환

**ConsumerWidget → ConsumerStatefulWidget:**

```dart
class ProductDetailScreen extends ConsumerStatefulWidget {
  const ProductDetailScreen({super.key, required this.productId});
  final String productId;

  @override
  ConsumerState<ProductDetailScreen> createState() =>
      _ProductDetailScreenState();
}

class _ProductDetailScreenState extends ConsumerState<ProductDetailScreen> {
  bool _isLiked = false;  // MVP: 서버에서 초기 liked 상태 미제공 → false로 시작
  int _likeAdjustment = 0;  // 로컬 조정값: +1 or -1
  bool _likeBusy = false;

  Future<void> _toggleLike(ProductDetailModel product) async {
    if (_likeBusy) return;
    final isAuth = ref.read(authNotifierProvider).valueOrNull?.isAuthenticated ?? false;
    if (!isAuth) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('로그인이 필요합니다.')),
      );
      return;
    }

    final wasLiked = _isLiked;
    // 낙관적 업데이트
    setState(() {
      _isLiked = !wasLiked;
      _likeAdjustment += wasLiked ? -1 : 1;
      _likeBusy = true;
    });

    final repo = ref.read(productManagementRepositoryProvider);
    try {
      if (wasLiked) {
        await repo.unlikeProduct(widget.productId);
      } else {
        await repo.likeProduct(widget.productId);
      }
    } on AppError catch (e) {
      if (!mounted) return;
      // 409/404 → 이미 올바른 상태, 로컬 상태 그대로 유지
      // 그 외 → 원래 상태로 복원 + 스낵바
      final serverCode = e.code;
      if (serverCode != AppErrorCode.unknown) {
        setState(() {
          _isLiked = wasLiked;
          _likeAdjustment += wasLiked ? 1 : -1;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
      }
    } finally {
      if (mounted) setState(() => _likeBusy = false);
    }
  }

  Future<void> _deleteProduct() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('상품 삭제'),
        content: const Text('정말 삭제하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('삭제', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await ref
          .read(productManagementRepositoryProvider)
          .deleteProduct(widget.productId);
      ref.invalidate(feedNotifierProvider);
      if (!mounted) return;
      context.go('/feed');
    } on AppError catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final detailAsync = ref.watch(productDetailProvider(widget.productId));
    final currentUserId =
        ref.watch(authNotifierProvider).valueOrNull?.user?.id;

    return Scaffold(
      appBar: AppBar(
        title: const Text('상품 상세'),
        backgroundColor: const Color(0xFFFF7043),
        foregroundColor: Colors.white,
        actions: detailAsync.valueOrNull != null &&
                currentUserId == detailAsync.requireValue.sellerId
            ? [
                IconButton(
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () => context.push(
                    '/product/${widget.productId}/edit',
                    extra: detailAsync.requireValue,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outlined),
                  onPressed: _deleteProduct,
                ),
              ]
            : null,
      ),
      body: detailAsync.when(
        skipLoadingOnRefresh: true,
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => AppErrorView(
          message: err is AppError ? err.message : '오류가 발생했습니다.',
          onRetry: () => ref.invalidate(productDetailProvider(widget.productId)),
        ),
        data: (product) => _DetailBody(product: product.copyWithLikeCount(
          product.likeCount + _likeAdjustment,
        )),
      ),
      bottomNavigationBar: detailAsync.valueOrNull != null
          ? _ActionBar(
              product: detailAsync.requireValue,
              isLiked: _isLiked,
              likeBusy: _likeBusy,
              onLike: () => _toggleLike(detailAsync.requireValue),
              onChat: () => _onChatTap(context),
            )
          : null,
    );
  }

  void _onChatTap(BuildContext context) {
    if (!context.mounted) return;
    final isAuth =
        ref.read(authNotifierProvider).valueOrNull?.isAuthenticated ?? false;
    if (!isAuth) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('로그인이 필요합니다.')),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('채팅하기 (Story 4.x에서 구현)')),
    );
  }
}
```

**BottomAppBar를 `_ActionBar`로 교체:**

```dart
class _ActionBar extends StatelessWidget {
  const _ActionBar({
    required this.product,
    required this.isLiked,
    required this.likeBusy,
    required this.onLike,
    required this.onChat,
  });

  final ProductDetailModel product;
  final bool isLiked;
  final bool likeBusy;
  final VoidCallback onLike;
  final VoidCallback onChat;

  @override
  Widget build(BuildContext context) {
    return BottomAppBar(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            // 하트 버튼 + 관심수
            IconButton(
              icon: Icon(
                isLiked ? Icons.favorite : Icons.favorite_border,
                color: isLiked ? Colors.red : Colors.grey,
              ),
              onPressed: likeBusy ? null : onLike,
            ),
            Text(
              '${product.likeCount}',
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(width: 12),
            // 채팅하기 버튼
            Expanded(
              child: ElevatedButton(
                onPressed: product.isSold ? null : onChat,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF7043),
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.grey.shade400,
                  minimumSize: const Size.fromHeight(48),
                ),
                child: Text(product.isSold ? '판매완료' : '채팅하기'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

**`ProductDetailModel`에 `copyWithLikeCount` 추가:**

```dart
// product_detail_model.dart 에 추가
ProductDetailModel copyWithLikeCount(int newLikeCount) => ProductDetailModel(
  id: id, sellerId: sellerId, title: title, price: price,
  category: category, imageUrls: imageUrls, createdAt: createdAt,
  likeCount: newLikeCount, status: status,
  description: description, sellerNickname: sellerNickname,
);
```

### 3. `product_edit_screen.dart` (NEW)

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../data/models/product_detail_model.dart';
import '../data/product_management_repository.dart';
import '../domain/product_detail_provider.dart';
import '../../feed/domain/feed_notifier.dart';
import '../../../core/error/app_error.dart';

const _kStatusItems = <DropdownMenuItem<String>>[
  DropdownMenuItem(value: 'SALE', child: Text('판매중')),
  DropdownMenuItem(value: 'RESERVED', child: Text('예약중')),
  DropdownMenuItem(value: 'SOLD', child: Text('판매완료')),
];

class ProductEditScreen extends ConsumerStatefulWidget {
  const ProductEditScreen({super.key, required this.product});
  final ProductDetailModel product;

  @override
  ConsumerState<ProductEditScreen> createState() => _ProductEditScreenState();
}

class _ProductEditScreenState extends ConsumerState<ProductEditScreen> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _priceCtrl;
  late final TextEditingController _descCtrl;
  late String _selectedStatus;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(text: widget.product.title);
    _priceCtrl = TextEditingController(text: widget.product.price.toString());
    _descCtrl = TextEditingController(text: widget.product.description ?? '');
    _selectedStatus = widget.product.status;
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _priceCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_isSaving) return;
    final price = int.tryParse(_priceCtrl.text.replaceAll(',', ''));
    if (price == null || price < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('올바른 가격을 입력해 주세요.')),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      final desc = _descCtrl.text.trim();
      await ref.read(productManagementRepositoryProvider).updateProduct(
        widget.product.id,
        {
          'title': _titleCtrl.text.trim(),
          'price': price,
          'description': desc.isEmpty ? null : desc,
          'status': _selectedStatus,
        },
      );
      ref.invalidate(productDetailProvider(widget.product.id));
      ref.invalidate(feedNotifierProvider);
      if (!mounted) return;
      context.pop();
    } on AppError catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('상품 수정'),
        backgroundColor: const Color(0xFFFF7043),
        foregroundColor: Colors.white,
      ),
      body: _isSaving
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFFF7043)))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  TextField(
                    controller: _titleCtrl,
                    maxLength: 40,
                    decoration: const InputDecoration(
                      labelText: '제목 *',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // ignore: deprecated_member_use
                  DropdownButtonFormField<String>(
                    value: _selectedStatus,
                    decoration: const InputDecoration(
                      labelText: '판매 상태',
                      border: OutlineInputBorder(),
                    ),
                    items: _kStatusItems,
                    onChanged: (v) => setState(() => _selectedStatus = v!),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _priceCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: '가격 (원) *',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _descCtrl,
                    maxLines: 4,
                    maxLength: 2000,
                    decoration: const InputDecoration(
                      labelText: '설명 (선택)',
                      border: OutlineInputBorder(),
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 80),
                ],
              ),
            ),
      bottomNavigationBar: _isSaving
          ? null
          : BottomAppBar(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: ElevatedButton(
                  onPressed: _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF7043),
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(48),
                  ),
                  child: const Text('저장하기'),
                ),
              ),
            ),
    );
  }
}
```

### 4. `app_router.dart` — 수정 라우트 추가

`/product/register` 바로 뒤에 추가:

```dart
import '../../features/product/presentation/product_edit_screen.dart';

GoRoute(
  path: '/product/:productId/edit',
  builder: (context, state) {
    final product = state.extra as ProductDetailModel;
    return ProductEditScreen(product: product);
  },
),
```

---

## 테스트 요구사항

`product_detail_management_test.dart` 신규 작성:

```dart
// 기존 product_detail_screen_test.dart에서 _product(), _FakeAuthNotifier, _buildApp 재사용
// 새 파일에서도 동일 헬퍼 정의 또는 공통 파일에서 import

class TestLikeButton:
  - '비인증 → 로그인 스낵바'
  - '관심 버튼 초기 상태 — 빈 하트 아이콘'

class TestSellerControls:
  - '본인 상품 → AppBar에 수정/삭제 아이콘 표시'
  - '타인 상품 → AppBar 아이콘 없음'
```

기존 `product_detail_screen_test.dart` — ConsumerStatefulWidget 변환 후에도 기존 9개 테스트 모두 통과해야 함. 회귀 확인 필수.

**테스트 helper `_product` 업데이트 필요:**
- `likeCount` 포함 확인 (이미 있음)
- `sellerId` 파라미터 추가로 판매자/구매자 구분 테스트 가능

---

## 개발자 가드레일

### MUST 따라야 할 패턴

1. **`dioProvider` 사용**: 관심/수정/삭제 4개 API 모두 인증 필수. `refreshDioProvider` 금지.

2. **낙관적 업데이트 패턴**: API 호출 전 `setState(() => _isLiked = !_isLiked)` → 실패 시 `setState(() => _isLiked = wasLiked)` 복원. 기존 `AuthNotifier.updateUser()` 패턴과 동일 철학.

3. **mounted 체크**: 모든 `async` 갭 이후 `if (!mounted) return;` 필수. `_toggleLike`, `_deleteProduct`, `_save` 전부 해당.

4. **`productDetailProvider` invalidate**: 수정 성공 후 상세 화면 갱신. `FutureProvider.autoDispose.family` 특성상 `ref.invalidate(productDetailProvider(productId))` 사용.

5. **`feedNotifierProvider` invalidate**: 삭제 성공 후, 수정 성공 후 모두 invalidate. 피드는 autoDispose이므로 화면 전환 후 자동 재빌드.

6. **`context.push('/product/$id/edit', extra: product)`**: GoRouter `extra`로 ProductDetailModel 전달. 라우트에서 `state.extra as ProductDetailModel`로 캐스팅.

7. **`copyWithLikeCount` 추가**: `ProductDetailModel`에 편의 메서드 추가. `_likeAdjustment` 반영 시 사용.

8. **AppBar actions**: 판매자 본인 여부 = `currentUserId == product.sellerId`. `detailAsync.valueOrNull != null` 체크 후 접근.

### MUST NOT

- `@riverpod` 어노테이션 사용 금지 (프로젝트 전체 수동 Provider 패턴)
- `productDetailProvider` 자체 수정 금지 (`FutureProvider.family` 패턴 유지)
- 수정/삭제 버튼을 `BottomAppBar`에 넣지 말 것 — AppBar trailing에 아이콘 버튼으로

---

## 이전 스토리 학습사항 (Story 3.2 + 3.3)

1. **`dioProvider` vs `refreshDioProvider`**: 관심 API는 인증 필수 → `dioProvider`. 상세 조회는 기존 `refreshDioProvider` 유지.

2. **`context.mounted` 가드 위치**: `await` 갭 이후 모든 `ScaffoldMessenger`·`context.go`·`context.pop` 호출 전.

3. **낙관적 업데이트 + 에러 복원 패턴**: `wasLiked` 값 저장 → 실패 시 복원. Story 3.3의 테스트에서 409/404가 정상 응답 코드임을 학습.

4. **`ref.listen` vs 로컬 상태**: 단순 토글은 로컬 `State`가 더 단순. 복잡한 비동기 흐름에는 `ref.listen` + Notifier.

5. **`ProductDetailModel.fromJson` 변경 없음**: Story 3.1/3.3에서 이미 `like_count`, `seller_id` 모두 포함. `copyWithLikeCount` 메서드만 추가.

6. **기존 테스트 회귀**: `ConsumerWidget → ConsumerStatefulWidget` 변환 후에도 동일한 동작. 기존 9개 테스트가 여전히 통과해야 함.

---

## Dev Agent Record

### Agent Model Used

claude-sonnet-4-6

### Debug Log References

- `Icons.favorite_border` 이 `_DetailBody`(관심수 행)와 `_ActionBar`(IconButton) 두 곳에 있어 `findsOneWidget` 실패 → `find.widgetWithIcon(IconButton, Icons.favorite_border)` 로 수정
- `_FakeAuth._userId` → `prefer_initializing_formals` lint → `userId` public 필드 + ignore 주석
- `_buildEditApp` 로컬 함수 → `no_leading_underscores_for_local_identifiers` → `buildEditApp`으로 rename

### Completion Notes List

- `ProductManagementRepository` — dioProvider 기반, likeProduct/unlikeProduct/updateProduct/deleteProduct
- `ProductDetailModel.copyWithLikeCount` — 낙관적 업데이트를 위한 편의 메서드
- `ProductDetailScreen` → ConsumerStatefulWidget: `_isLiked`/`_likeAdjustment`/`_likeBusy` 로컬 상태, 낙관적 업데이트
- `_ActionBar` — 하트버튼 + 관심수 + 채팅하기 버튼 통합 BottomAppBar
- AppBar: 판매자 본인(`currentUserId == product.sellerId`)이면 수정/삭제 아이콘 표시
- `ProductEditScreen` — pre-fill, PATCH API, productDetailProvider + feedNotifierProvider invalidate
- `/product/:productId/edit` 라우트 추가 (GoRouter extra로 ProductDetailModel 전달)
- 전체 테스트 120/120 통과, flutter analyze: No issues found

### File List
- mobile/lib/features/product/data/models/product_detail_model.dart (UPDATE — copyWithLikeCount 추가)
- mobile/lib/features/product/data/product_management_repository.dart (NEW)
- mobile/lib/features/product/presentation/product_detail_screen.dart (UPDATE — 대규모 변환)
- mobile/lib/features/product/presentation/product_edit_screen.dart (NEW)
- mobile/lib/core/router/app_router.dart (UPDATE — edit 라우트)
- mobile/test/features/product/product_detail_management_test.dart (NEW)
