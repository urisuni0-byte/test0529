import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants.dart';
import '../../../core/storage/secure_storage.dart';
import '../../auth/domain/auth_notifier.dart';
import '../data/chat_repository.dart';
import '../data/models/chat_models.dart';

class ChatRoomState {
  const ChatRoomState({
    this.messages = const [],
    this.isConnected = false,
    this.isLoadingHistory = true,
    this.historyError,
    this.reconnectFailed = false,
  });

  final List<ChatMessageModel> messages;
  final bool isConnected;
  final bool isLoadingHistory;
  final String? historyError;
  final bool reconnectFailed;

  ChatRoomState copyWith({
    List<ChatMessageModel>? messages,
    bool? isConnected,
    bool? isLoadingHistory,
    String? historyError,
    bool? reconnectFailed,
    bool clearHistoryError = false,
  }) =>
      ChatRoomState(
        messages: messages ?? this.messages,
        isConnected: isConnected ?? this.isConnected,
        isLoadingHistory: isLoadingHistory ?? this.isLoadingHistory,
        historyError:
            clearHistoryError ? null : (historyError ?? this.historyError),
        reconnectFailed: reconnectFailed ?? this.reconnectFailed,
      );
}

class ChatRoomNotifier extends StateNotifier<ChatRoomState> {
  ChatRoomNotifier(this.ref, this.roomId) : super(const ChatRoomState()) {
    _init();
  }

  final Ref ref;
  final String roomId;

  WebSocket? _ws;
  StreamSubscription<dynamic>? _wsSub;
  int _reconnectAttempts = 0;
  static const _maxReconnects = 3;
  bool _disposed = false;

  String get _myUserId =>
      ref.read(authNotifierProvider).valueOrNull?.user?.id ?? '';

  Future<void> _init() async {
    // 히스토리 로드와 WebSocket 연결을 병렬로 시작
    unawaited(_loadHistory());
    unawaited(_connectWithRetry());
  }

  Future<void> _loadHistory() async {
    try {
      final msgs = await ref
          .read(chatRepositoryProvider)
          .getMessages(roomId, myUserId: _myUserId);
      if (!_disposed) {
        // REST API는 최신순 DESC → 오래된 것이 앞으로 오도록 reversed
        state = state.copyWith(
          messages: msgs.reversed.toList(),
          isLoadingHistory: false,
          clearHistoryError: true,
        );
      }
    } catch (e) {
      if (!_disposed) {
        state = state.copyWith(
          isLoadingHistory: false,
          historyError: e.toString(),
        );
      }
    }
  }

  Future<void> _connectWithRetry() async {
    _reconnectAttempts = 0;
    while (!_disposed && _reconnectAttempts < _maxReconnects) {
      try {
        final token =
            await ref.read(secureStorageProvider).getAccessToken() ?? '';
        final uri =
            '${AppConstants.wsBase}/ws/chat/$roomId?token=$token';

        _ws = await WebSocket.connect(uri)
            .timeout(const Duration(seconds: 10));

        if (_disposed) {
          _ws?.close();
          return;
        }

        if (!_disposed) {
          state = state.copyWith(isConnected: true, reconnectFailed: false);
        }
        _reconnectAttempts = 0;

        final completer = Completer<void>();
        _wsSub = _ws!.listen(
          (raw) {
            if (raw is String) _handleMessage(raw);
          },
          onDone: completer.complete,
          onError: (Object e) {
            if (!completer.isCompleted) completer.completeError(e);
          },
          cancelOnError: true,
        );

        await completer.future; // 연결 종료까지 대기
        _wsSub = null;
      } catch (_) {
        // 연결 실패 — 아래 재시도 로직으로 이동
      }

      if (_disposed) return;

      if (!_disposed) state = state.copyWith(isConnected: false);

      _reconnectAttempts++;
      if (_reconnectAttempts >= _maxReconnects) {
        if (!_disposed) state = state.copyWith(reconnectFailed: true);
        return;
      }

      // Exponential backoff: 1초, 2초, 4초
      final delay = Duration(seconds: 1 << (_reconnectAttempts - 1));
      await Future.delayed(delay);
    }
  }

  void _handleMessage(String raw) {
    if (_disposed) return;
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      if (data['type'] == 'message') {
        final msg = ChatMessageModel.fromJson(data, myUserId: _myUserId);
        state = state.copyWith(messages: [...state.messages, msg]);
      }
      // 'connected' type → WebSocket 연결 확인 메시지 (isConnected는 이미 true)
    } catch (_) {
      // JSON 파싱 실패 무시
    }
  }

  void sendMessage(String content) {
    final trimmed = content.trim();
    if (trimmed.isEmpty || _ws == null) return;
    try {
      _ws!.add(jsonEncode({'type': 'message', 'content': trimmed}));
    } catch (_) {
      // WebSocket 전송 실패 무시 (재연결 중일 수 있음)
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _wsSub?.cancel();
    _ws?.close();
    super.dispose();
  }
}

final chatRoomNotifierProvider = StateNotifierProvider.autoDispose
    .family<ChatRoomNotifier, ChatRoomState, String>(
  (ref, roomId) => ChatRoomNotifier(ref, roomId),
);
