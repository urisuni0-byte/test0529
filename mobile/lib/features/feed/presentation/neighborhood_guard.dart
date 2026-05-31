import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../auth/domain/auth_notifier.dart';

/// Checks if the current user has a neighborhood set.
/// If not, shows a snackbar and navigates to /neighborhood.
/// Otherwise calls [onHasNeighborhood].
void requireNeighborhood(
  BuildContext context,
  WidgetRef ref, {
  required VoidCallback onHasNeighborhood,
}) {
  final user = ref.read(authNotifierProvider).valueOrNull?.user;
  if (user == null || !user.hasNeighborhood) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('먼저 동네를 설정해 주세요.')),
    );
    context.push('/neighborhood');
    return;
  }
  onHasNeighborhood();
}
