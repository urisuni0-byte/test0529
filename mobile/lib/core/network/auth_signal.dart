import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Incremented by AuthInterceptor when a refresh fails and the user must be
/// signed out. authNotifierProvider listens to this and calls forceSignOut().
/// Using a counter (not bool) lets multiple rapid failures each trigger a listen.
final authSignedOutSignalProvider = StateProvider<int>((ref) => 0);
