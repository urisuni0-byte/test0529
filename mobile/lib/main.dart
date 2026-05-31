import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/notifications/fcm_service.dart';
import 'core/router/app_router.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Firebase 초기화 (google-services.json / GoogleService-Info.plist 필요)
  // 미설정 시 앱은 정상 동작 — FCM만 비활성화됨
  try {
    await Firebase.initializeApp();
  } catch (_) {}

  runApp(const ProviderScope(child: App()));
}

class App extends ConsumerStatefulWidget {
  const App({super.key});

  @override
  ConsumerState<App> createState() => _AppState();
}

class _AppState extends ConsumerState<App> {
  @override
  void initState() {
    super.initState();
    _initFcm();
  }

  Future<void> _initFcm() async {
    final fcmService = ref.read(fcmServiceProvider);
    await fcmService.initialize();
    if (!mounted) return;
    fcmService.setupNotificationHandlers(ref);
    if (!mounted) return;
    await fcmService.checkInitialMessage(ref);
    // checkInitialMessage 이후 ref가 유효하지 않을 수 있으므로
    // 내부 StateError는 catch(_){} 에서 처리됨
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);

    // 알림 탭 딥링크: pendingChatRoomProvider → 채팅방으로 이동
    ref.listen<String?>(pendingChatRoomProvider, (prev, roomId) {
      if (roomId != null) {
        router.push('/chat/$roomId');
        ref.read(pendingChatRoomProvider.notifier).state = null;
      }
    });

    return MaterialApp.router(
      title: '중고거래 MVP',
      debugShowCheckedModeBanner: false,
      routerConfig: router,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFFF7043),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFFF7043),
          foregroundColor: Colors.white,
          elevation: 0,
        ),
      ),
    );
  }
}
