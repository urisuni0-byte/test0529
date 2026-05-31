import '../data/models/user_model.dart';

sealed class AuthState {
  const AuthState();

  bool get isAuthenticated => this is Authenticated;
  bool get needsOnboarding =>
      isAuthenticated && (this as Authenticated).user.hasNickname == false;

  UserModel? get user => null;
}

final class Authenticated extends AuthState {
  const Authenticated({required this.user});

  @override
  final UserModel user;
}

final class Unauthenticated extends AuthState {
  const Unauthenticated();
}
