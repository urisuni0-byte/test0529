import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/app_error.dart';
import '../../auth/domain/auth_notifier.dart';
import '../data/models/product_model.dart';
import '../data/product_repository.dart';

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
  }) =>
      FeedState(
        products: products ?? this.products,
        total: total ?? this.total,
        currentPage: currentPage ?? this.currentPage,
        isLoadingMore: isLoadingMore ?? this.isLoadingMore,
        loadMoreError:
            clearLoadMoreError ? null : (loadMoreError ?? this.loadMoreError),
      );
}

class FeedNotifier extends AutoDisposeAsyncNotifier<FeedState> {
  @override
  Future<FeedState> build() async {
    // watch — auth 상태 변경(동네 변경 포함) 시 자동 재빌드
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

    state = AsyncData(
        current.copyWith(isLoadingMore: true, clearLoadMoreError: true));
    try {
      final resp = await ref
          .read(productRepositoryProvider)
          .getProducts(neighborhoodId: neighborhoodId, page: current.currentPage + 1);
      // await 이후 fresh state 재독: 동시 refresh()가 state를 교체했을 수 있음
      final fresh = state.valueOrNull;
      if (fresh == null) return; // 리프레시로 인해 notifier가 재빌드 중 → 결과 폐기
      state = AsyncData(fresh.copyWith(
        products: [...fresh.products, ...resp.items],
        total: resp.total,
        currentPage: fresh.currentPage + 1,
        isLoadingMore: false,
      ));
    } on AppError catch (e) {
      final fresh = state.valueOrNull;
      if (fresh != null) {
        state = AsyncData(fresh.copyWith(isLoadingMore: false, loadMoreError: e));
      }
    } catch (e) {
      final fresh = state.valueOrNull;
      if (fresh != null) {
        state = AsyncData(fresh.copyWith(
          isLoadingMore: false,
          loadMoreError: AppError(message: e.toString(), code: AppErrorCode.unknown),
        ));
      }
    }
  }

  Future<void> refresh() async {
    ref.invalidateSelf();
    try {
      await future;
    } catch (_) {
      // build() 오류는 이미 AsyncError 상태로 반영됨.
      // 여기서 삼키지 않으면 RefreshIndicator에서 uncaught Future rejection 발생.
    }
  }
}

final feedNotifierProvider =
    AutoDisposeAsyncNotifierProvider<FeedNotifier, FeedState>(FeedNotifier.new);
