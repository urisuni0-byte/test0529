// Story 4.5 — FCM 토큰 등록 및 알림 핸들러.
import 'dart:async';

import 'package:dio/dio.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../network/api_client.dart';

/// 알림 탭으로 딥링크 대기 중인 roomId.
/// App 위젯에서 watch → navigate + null reset.
final pendingChatRoomProvider = StateProvider<String?>((ref) => null);

class FcmService {
  FcmService({required Dio authDio}) : _dio = authDio;

  final Dio _dio;

  // 구독을 저장해 중복 리스너 누적 및 토큰 갱신 누수 방지
  StreamSubscription<RemoteMessage>? _openedAppSub;
  StreamSubscription<String>? _tokenRefreshSub;

  /// 앱 시작 시 FCM 초기화: 권한 요청 + 토큰 등록 + 갱신 구독.
  /// 재호출 시 이전 구독을 취소하고 새로 등록한다.
  Future<void> initialize() async {
    try {
      final settings = await FirebaseMessaging.instance.requestPermission();
      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        return; // 권한 거부 → FCM 비활성화 (앱 정상 동작 유지)
      }

      // 현재 토큰 등록
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) await _registerToken(token);

      // 토큰 갱신 감지 — 이전 구독 취소 후 재등록
      await _tokenRefreshSub?.cancel();
      _tokenRefreshSub =
          FirebaseMessaging.instance.onTokenRefresh.listen(_registerToken);
    } catch (_) {
      // Firebase 미설정 또는 에뮬레이터 — 조용히 무시
    }
  }

  /// 알림 탭 핸들러 설정.
  /// 이전 구독을 취소하고 새로 등록해 중복 리스너를 방지한다.
  void setupNotificationHandlers(WidgetRef ref) {
    _openedAppSub?.cancel();
    _openedAppSub = FirebaseMessaging.onMessageOpenedApp.listen((message) {
      final roomId = message.data['room_id']?.toString();
      if (roomId != null && roomId.isNotEmpty) {
        ref.read(pendingChatRoomProvider.notifier).state = roomId;
      }
    });
  }

  /// 앱 종료 상태에서 알림 탭으로 시작된 경우 확인.
  Future<void> checkInitialMessage(WidgetRef ref) async {
    try {
      final initial = await FirebaseMessaging.instance.getInitialMessage();
      final roomId = initial?.data['room_id']?.toString();
      if (roomId != null && roomId.isNotEmpty) {
        // await 이후 ref가 유효한지 확인
        ref.read(pendingChatRoomProvider.notifier).state = roomId;
      }
    } catch (_) {
      // WidgetRef 해제 후 접근 시 StateError 포함 — 조용히 무시
    }
  }

  Future<void> _registerToken(String token) async {
    try {
      await _dio.patch('/users/me', data: {'fcm_token': token});
    } catch (_) {
      // 토큰 등록 실패 무시 (다음 앱 실행 시 재시도)
    }
  }

  /// 리소스 정리 (로그아웃 시 호출 권장).
  Future<void> dispose() async {
    await _openedAppSub?.cancel();
    await _tokenRefreshSub?.cancel();
    _openedAppSub = null;
    _tokenRefreshSub = null;
  }
}

final fcmServiceProvider = Provider<FcmService>((ref) {
  return FcmService(authDio: ref.watch(dioProvider));
});
