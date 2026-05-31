import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/error/app_error.dart';
import '../../../core/utils/formatting.dart';
import '../../../core/widgets/app_error_view.dart';
import '../../auth/domain/auth_notifier.dart';
import '../../chat/data/chat_repository.dart';
import '../../feed/domain/feed_notifier.dart';
import '../data/models/product_detail_model.dart';
import '../data/product_management_repository.dart';
import '../domain/product_detail_provider.dart';

class ProductDetailScreen extends ConsumerStatefulWidget {
  const ProductDetailScreen({super.key, required this.productId});

  final String productId;

  @override
  ConsumerState<ProductDetailScreen> createState() =>
      _ProductDetailScreenState();
}

class _ProductDetailScreenState extends ConsumerState<ProductDetailScreen> {
  // MVP: 서버가 is_liked 반환 안 함 → false로 시작, 사용자 탭으로만 토글됨
  bool _isLiked = false;
  int _likeAdjustment = 0;
  bool _likeBusy = false;
  bool _chatLoading = false;

  Future<void> _toggleLike() async {
    if (_likeBusy) return;
    final isAuth =
        ref.read(authNotifierProvider).valueOrNull?.isAuthenticated ?? false;
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
      // 409(중복 like) / 404(없는 unlike) → 이미 올바른 상태 유지
      // 그 외 네트워크 오류 → 원래 상태 복원 + 스낵바
      final isExpectedError = e.statusCode == 409 || e.statusCode == 404;
      if (!isExpectedError) {
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

  Future<void> _onChatTap() async {
    if (!mounted) return;
    final isAuth =
        ref.read(authNotifierProvider).valueOrNull?.isAuthenticated ?? false;
    if (!isAuth) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('로그인이 필요합니다.')),
      );
      return;
    }
    setState(() => _chatLoading = true);
    try {
      final result = await ref
          .read(chatRepositoryProvider)
          .createOrGetChatRoom(widget.productId);
      if (!mounted) return;
      context.push('/chat/${result.roomId}', extra: widget.productId);
    } on AppError catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } finally {
      if (mounted) setState(() => _chatLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final detailAsync = ref.watch(productDetailProvider(widget.productId));
    final currentUserId =
        ref.watch(authNotifierProvider).valueOrNull?.user?.id;

    final product = detailAsync.valueOrNull;
    final isSeller = product != null && currentUserId == product.sellerId;

    return Scaffold(
      appBar: AppBar(
        title: const Text('상품 상세'),
        backgroundColor: const Color(0xFFFF7043),
        foregroundColor: Colors.white,
        actions: isSeller
            ? [
                IconButton(
                  icon: const Icon(Icons.edit_outlined),
                  tooltip: '수정',
                  onPressed: () => context.push(
                    '/product/${widget.productId}/edit',
                    extra: product,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outlined),
                  tooltip: '삭제',
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
          onRetry: () =>
              ref.invalidate(productDetailProvider(widget.productId)),
        ),
        data: (p) => _DetailBody(
          product: p.copyWithLikeCount(p.likeCount + _likeAdjustment),
        ),
      ),
      bottomNavigationBar: product != null
          ? _ActionBar(
              product: product,
              isLiked: _isLiked,
              likeBusy: _likeBusy,
              isChatLoading: _chatLoading,
              onLike: _toggleLike,
              onChat: _onChatTap,
            )
          : null,
    );
  }
}

// ─── 본문 ─────────────────────────────────────────────────────────────────

class _DetailBody extends StatelessWidget {
  const _DetailBody({required this.product});

  final ProductDetailModel product;

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).viewPadding.bottom + 72;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ImageSlider(imageUrls: product.imageUrls),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (product.isReserved || product.isSold) ...[
                  _StatusBadge(product: product),
                  const SizedBox(height: 8),
                ],
                Text(
                  product.title,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                Text(
                  formatPrice(product.price),
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  timeAgo(product.createdAt),
                  style:
                      TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
                const Divider(height: 24),
                if (product.sellerNickname != null) ...[
                  Row(
                    children: [
                      const Icon(Icons.person_outline,
                          size: 18, color: Colors.grey),
                      const SizedBox(width: 6),
                      Text(
                        product.sellerNickname!,
                        style: const TextStyle(fontSize: 14),
                      ),
                    ],
                  ),
                  const Divider(height: 24),
                ],
                Row(
                  children: [
                    Text('카테고리  ',
                        style: TextStyle(
                            fontSize: 13, color: Colors.grey.shade600)),
                    Text(product.category,
                        style: const TextStyle(fontSize: 13)),
                  ],
                ),
                const SizedBox(height: 8),
                // like_count는 _ActionBar에서도 표시하므로 여기선 유지
                Row(
                  children: [
                    Icon(Icons.favorite_border,
                        size: 14, color: Colors.grey.shade500),
                    const SizedBox(width: 4),
                    Text('관심 ${product.likeCount}',
                        style: TextStyle(
                            fontSize: 13, color: Colors.grey.shade600)),
                  ],
                ),
                if (product.description != null) ...[
                  const Divider(height: 24),
                  Text(
                    product.description!,
                    style: const TextStyle(fontSize: 14, height: 1.5),
                  ),
                ],
                SizedBox(height: bottomPad),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── 상태 배지 ─────────────────────────────────────────────────────────────

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.product});

  final ProductDetailModel product;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: product.isSold ? Colors.black54 : Colors.grey.shade600,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        product.isSold ? '판매완료' : '예약중',
        style: const TextStyle(color: Colors.white, fontSize: 12),
      ),
    );
  }
}

// ─── 이미지 슬라이더 ────────────────────────────────────────────────────────

Widget _buildNetworkImage(String url, {double height = 300}) {
  return Image.network(
    url,
    fit: BoxFit.cover,
    width: double.infinity,
    height: height,
    errorBuilder: (_, _, _) => Container(
      height: height,
      color: Colors.grey.shade200,
      child:
          Icon(Icons.image_outlined, size: 80, color: Colors.grey.shade400),
    ),
  );
}

class _ImageSlider extends StatefulWidget {
  const _ImageSlider({required this.imageUrls});

  final List<String> imageUrls;

  @override
  State<_ImageSlider> createState() => _ImageSliderState();
}

class _ImageSliderState extends State<_ImageSlider> {
  late final PageController _pageController;
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.imageUrls.isEmpty) {
      return Container(
        height: 300,
        color: Colors.grey.shade200,
        child: Icon(
          Icons.image_outlined,
          size: 80,
          color: Colors.grey.shade400,
        ),
      );
    }

    if (widget.imageUrls.length == 1) {
      return SizedBox(
        height: 300,
        child: _buildNetworkImage(widget.imageUrls.first),
      );
    }

    return SizedBox(
      height: 300,
      child: Stack(
        children: [
          PageView.builder(
            controller: _pageController,
            itemCount: widget.imageUrls.length,
            physics:
                const PageScrollPhysics(parent: ClampingScrollPhysics()),
            onPageChanged: (i) => setState(() => _currentIndex = i),
            itemBuilder: (_, i) => _buildNetworkImage(widget.imageUrls[i]),
          ),
          Positioned(
            bottom: 8,
            left: 0,
            right: 0,
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
      children: List.generate(
        count,
        (i) => Container(
          width: 8,
          height: 8,
          margin: const EdgeInsets.symmetric(horizontal: 3),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: i == current ? Colors.white : Colors.white54,
          ),
        ),
      ),
    );
  }
}

// ─── 하단 액션 바 (하트 + 채팅하기) ──────────────────────────────────────────

class _ActionBar extends StatelessWidget {
  const _ActionBar({
    required this.product,
    required this.isLiked,
    required this.likeBusy,
    required this.isChatLoading,
    required this.onLike,
    required this.onChat,
  });

  final ProductDetailModel product;
  final bool isLiked;
  final bool likeBusy;
  final bool isChatLoading;
  final VoidCallback onLike;
  final VoidCallback onChat;

  @override
  Widget build(BuildContext context) {
    return BottomAppBar(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
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
            Expanded(
              child: ElevatedButton(
                onPressed: product.isSold || isChatLoading ? null : onChat,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF7043),
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.grey.shade400,
                  minimumSize: const Size.fromHeight(48),
                ),
                child: isChatLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : Text(product.isSold ? '판매완료' : '채팅하기'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
