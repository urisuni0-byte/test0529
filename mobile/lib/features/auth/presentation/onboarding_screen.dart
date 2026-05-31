import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../domain/auth_notifier.dart';
import 'nickname_validator.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _controller = TextEditingController();
  String? _errorText;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    // addListener covers autofill and programmatic controller changes that
    // don't fire onChanged — prevents _controller.text from diverging from UI.
    _controller.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    // Rebuild immediately so _isValid (derived from _controller.text) is correct.
    // Error text is shown after the first character is entered.
    final value = _controller.text;
    setState(() {
      _errorText = value.isNotEmpty ? validateNickname(value) : null;
    });
  }

  String get _nickname => _controller.text;

  bool get _isValid =>
      _nickname.isNotEmpty && validateNickname(_nickname) == null;

  Future<void> _submit() async {
    if (!_isValid || _isSaving) return;
    setState(() => _isSaving = true);

    try {
      final dio = ref.read(dioProvider);
      await dio.patch('/users/me', data: {'nickname': _nickname});

      if (!mounted) return;

      // Optimistic update: update in-memory AuthState without a getMe() round-trip.
      // Avoids a stuck loading spinner if the network degrades after the PATCH.
      final currentUser = ref.read(authNotifierProvider).valueOrNull?.user;
      if (currentUser != null) {
        ref
            .read(authNotifierProvider.notifier)
            .updateUser(currentUser.copyWith(nickname: _nickname));
      }
      // go_router redirects to /feed automatically when needsOnboarding flips false.
    } on DioException catch (e) {
      if (!mounted) return;
      final data = e.response?.data;
      // Guard against non-Map response bodies (e.g. plain-text 500 from a gateway)
      final message =
          (data is Map) ? data['detail']?.toString() : null;
      _showError(message ?? '저장 중 오류가 발생했습니다. 다시 시도해 주세요.');
    } catch (_) {
      if (!mounted) return;
      _showError('저장 중 오류가 발생했습니다. 다시 시도해 주세요.');
    } finally {
      // Always reset _isSaving when mounted so the button is re-enabled
      // if navigation did not fire (e.g. state propagation was delayed).
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red.shade700,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('닉네임 설정'),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 32),
              const Text(
                '닉네임을 입력해 주세요',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF212121),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                '다른 사용자에게 표시되는 이름입니다.',
                style: TextStyle(fontSize: 14, color: Color(0xFF757575)),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 40),
              TextField(
                controller: _controller,
                maxLength: 15,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  hintText: '닉네임 (2~15자)',
                  errorText: _errorText,
                  border: const OutlineInputBorder(),
                  focusedBorder: const OutlineInputBorder(
                    borderSide: BorderSide(color: Color(0xFFFF7043), width: 2),
                  ),
                  // counterText driven by controller (single source of truth)
                  counterText: '${_controller.text.length}/15',
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _isValid && !_isSaving ? _submit : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF7043),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: _isSaving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Text(
                        '완료',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
