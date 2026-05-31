import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/error/app_error.dart';
import '../../../core/widgets/app_error_view.dart';
import '../domain/feed_notifier.dart';
import 'neighborhood_guard.dart';
import 'product_card.dart';

class FeedScreen extends ConsumerWidget {
  const FeedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feedAsync = ref.watch(feedNotifierProvider);

    // 초기 로드 네트워크 에러(AsyncError) 및 페이지네이션 네트워크 에러(AsyncData.loadMoreError) → Snackbar
    ref.listen(feedNotifierProvider, (prev, next) {
      if (next case AsyncError(:final error)) {
        if (error is AppError && error.code == AppErrorCode.networkError) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(error.message)),
          );
        }
      }
      // loadMoreError는 AsyncData 내부에 있어 AsyncError와 별도로 감지
      final loadMoreErr = next.valueOrNull?.loadMoreError;
      final prevLoadMoreErr = prev?.valueOrNull?.loadMoreError;
      if (loadMoreErr != null && loadMoreErr != prevLoadMoreErr &&
          loadMoreErr.code == AppErrorCode.networkError) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(loadMoreErr.message)),
        );
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('피드'),
        backgroundColor: const Color(0xFFFF7043),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.chat_bubble_outline),
            tooltip: '채팅',
            onPressed: () => context.push('/chat-list'),
          ),
        ],
      ),
      body: feedAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => AppErrorView(
          message: err is AppError ? err.message : '오류가 발생했습니다.',
          onRetry: () => ref.invalidate(feedNotifierProvider),
          showNeighborhoodButton: err is AppError &&
              err.message.contains('동네'),
        ),
        data: (feedState) => RefreshIndicator(
          onRefresh: () => ref.read(feedNotifierProvider.notifier).refresh(),
          child: feedState.products.isEmpty
              ? const _EmptyView()
              : _FeedListView(state: feedState),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => requireNeighborhood(
          context,
          ref,
          onHasNeighborhood: () => context.push('/product/register'),
        ),
        backgroundColor: const Color(0xFFFF7043),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.edit),
        label: const Text('글쓰기'),
      ),
    );
  }
}

// ─── 피드 목록 ─────────────────────────────────────────────────────────────

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
    final feedState =
        ref.watch(feedNotifierProvider).valueOrNull ?? widget.state;
    final itemCount = feedState.products.length + 1; // +1 for footer

    return ListView.separated(
      controller: _ctrl,
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: itemCount,
      separatorBuilder: (_, _) => const Divider(height: 1, indent: 16),
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
        if (feedState.loadMoreError != null) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  feedState.loadMoreError!.message,
                  style: const TextStyle(color: Colors.grey, fontSize: 13),
                ),
                TextButton(
                  onPressed: () =>
                      ref.read(feedNotifierProvider.notifier).loadMore(),
                  child: const Text('다시 시도'),
                ),
              ],
            ),
          );
        }
        if (!feedState.hasMore) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: Text(
                '마지막 상품입니다.',
                style: TextStyle(color: Colors.grey, fontSize: 13),
              ),
            ),
          );
        }
        return const SizedBox.shrink();
      },
    );
  }
}

/// 빈 피드 뷰 — SingleChildScrollView로 감싸 RefreshIndicator의 pull-to-refresh가 동작하도록 함.
class _EmptyView extends StatelessWidget {
  const _EmptyView();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: SizedBox(
          height: constraints.maxHeight,
          child: const Center(
            child: Text(
              '판매중인 상품이 없습니다.',
              style: TextStyle(fontSize: 15, color: Colors.grey),
            ),
          ),
        ),
      ),
    );
  }
}
