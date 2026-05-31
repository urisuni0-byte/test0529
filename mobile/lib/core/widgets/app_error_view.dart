import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// 공통 에러 뷰 — 피드, 상품 상세 등에서 공유.
class AppErrorView extends StatelessWidget {
  const AppErrorView({
    super.key,
    required this.message,
    required this.onRetry,
    this.showNeighborhoodButton = false,
  });

  final String message;
  final VoidCallback onRetry;
  final bool showNeighborhoodButton;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.grey),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 15),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: onRetry,
              child: const Text('다시 시도'),
            ),
            if (showNeighborhoodButton) ...[
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () => context.push('/neighborhood'),
                child: const Text('동네 설정하기'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
