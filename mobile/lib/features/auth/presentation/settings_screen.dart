import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../domain/auth_notifier.dart';
import 'nickname_validator.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _controller = TextEditingController();
  bool _isEditing = false;
  String? _errorText;
  bool _isSaving = false;

  /// Nickname value stored at the start of an edit session.
  /// Used to (a) guard against unnecessary PATCH and (b) detect concurrent
  /// server-side changes while the user is editing.
  String _initialNickname = '';

  /// Last confirmed non-null nickname — prevents '닉네임 없음' flash during
  /// auth loading/error transitions.
  String? _cachedNickname;

  @override
  void initState() {
    super.initState();
    // addListener fires on autofill and programmatic writes (mirrors OnboardingScreen).
    _controller.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    final value = _controller.text;
    setState(() {
      _errorText = value.isNotEmpty ? validateNickname(value) : null;
    });
  }

  void _startEditing(String currentNickname) {
    _initialNickname = currentNickname;
    _controller.text = currentNickname;
    // Validate the pre-loaded value so legacy invalid nicknames surface an error.
    _errorText = currentNickname.isNotEmpty ? validateNickname(currentNickname) : null;
    setState(() => _isEditing = true);
  }

  void _cancelEditing() {
    _controller.clear();
    setState(() {
      _isEditing = false;
      _errorText = null;
    });
  }

  String get _nickname => _controller.text.trim();

  bool get _isValid => _nickname.isNotEmpty && validateNickname(_nickname) == null;

  Future<void> _save() async {
    if (!_isValid || _isSaving) return;

    // Skip PATCH if nickname is unchanged — avoids spurious 409 errors.
    if (_nickname == _initialNickname.trim()) {
      setState(() => _isEditing = false);
      return;
    }

    setState(() => _isSaving = true);
    try {
      final dio = ref.read(dioProvider);
      await dio.patch('/users/me', data: {'nickname': _nickname});

      if (!mounted) return;

      final currentUser = ref.read(authNotifierProvider).valueOrNull?.user;
      if (currentUser != null) {
        ref
            .read(authNotifierProvider.notifier)
            .updateUser(currentUser.copyWith(nickname: _nickname));
      }

      setState(() {
        _isEditing = false;
        _isSaving = false;
        _initialNickname = _nickname;
      });
    } on DioException catch (e) {
      if (!mounted) return;
      final data = e.response?.data;
      final message = (data is Map) ? data['detail']?.toString() : null;
      _showError(message ?? '저장 중 오류가 발생했습니다. 다시 시도해 주세요.');
      setState(() => _isSaving = false);
    } catch (_) {
      if (!mounted) return;
      _showError('저장 중 오류가 발생했습니다. 다시 시도해 주세요.');
      setState(() => _isSaving = false);
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

  Future<void> _confirmLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('로그아웃'),
        content: const Text('로그아웃 하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('로그아웃', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      try {
        await ref.read(authNotifierProvider.notifier).signOut();
        // go_router redirects to /login automatically.
      } catch (_) {
        if (!mounted) return;
        _showError('로그아웃 중 오류가 발생했습니다. 다시 시도해 주세요.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authAsync = ref.watch(authNotifierProvider);
    final user = authAsync.valueOrNull?.user;

    // Cache last non-null nickname to avoid '닉네임 없음' flash during
    // brief loading/error transitions (e.g. token refresh).
    if (user?.nickname != null) _cachedNickname = user!.nickname;
    final currentNickname = _cachedNickname ?? '';

    return Scaffold(
      appBar: AppBar(title: const Text('설정')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                '프로필',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF757575),
                ),
              ),
              const SizedBox(height: 8),
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: Colors.grey.shade200),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: _isEditing
                      ? _buildEditRow()
                      : _buildDisplayRow(currentNickname),
                ),
              ),
              const SizedBox(height: 32),
              const Text(
                '계정',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF757575),
                ),
              ),
              const SizedBox(height: 8),
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: Colors.grey.shade200),
                ),
                child: ListTile(
                  title: const Text('로그아웃',
                      style: TextStyle(color: Colors.red)),
                  trailing: const Icon(Icons.logout, color: Colors.red),
                  // Wrap async callback so Future is awaited and exceptions are caught.
                  onTap: () => _confirmLogout(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDisplayRow(String nickname) {
    return Row(
      children: [
        const Icon(Icons.person_outline, color: Color(0xFF757575)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('닉네임',
                  style: TextStyle(fontSize: 12, color: Color(0xFF9E9E9E))),
              const SizedBox(height: 2),
              Text(
                nickname.trim().isNotEmpty ? nickname : '닉네임 없음',
                key: const Key('nickname_display'),
                style: const TextStyle(fontSize: 16),
              ),
            ],
          ),
        ),
        TextButton(
          onPressed: () => _startEditing(nickname),
          child: const Text('편집', style: TextStyle(color: Color(0xFFFF7043))),
        ),
      ],
    );
  }

  Widget _buildEditRow() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _controller,
          maxLength: 15,
          autofocus: true,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _save(),
          decoration: InputDecoration(
            labelText: '닉네임',
            errorText: _errorText,
            border: const OutlineInputBorder(),
            focusedBorder: const OutlineInputBorder(
              borderSide: BorderSide(color: Color(0xFFFF7043), width: 2),
            ),
            counterText: '${_controller.text.length}/15',
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: _cancelEditing,
              child: const Text('취소'),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: _isValid && !_isSaving ? _save : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF7043),
                foregroundColor: Colors.white,
              ),
              child: _isSaving
                  ? const SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Text('저장'),
            ),
          ],
        ),
      ],
    );
  }
}
