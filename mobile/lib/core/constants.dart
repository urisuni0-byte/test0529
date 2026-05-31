class AppConstants {
  AppConstants._();

  /// Backend API base URL.
  /// Override at build time: --dart-define=API_BASE_URL=https://your-server.com
  /// Android emulator default: 10.0.2.2 (maps to host machine localhost)
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8000',
  );

  static const String apiV1 = '$baseUrl/api/v1';

  /// WebSocket base URL: http→ws, https→wss (자동 변환).
  static String get wsBase => baseUrl.replaceFirst('http', 'ws');

  /// Google OAuth2 web client ID (server-side verification).
  /// Must match GOOGLE_CLIENT_ID in the backend .env.
  static const String googleClientId = String.fromEnvironment(
    'GOOGLE_CLIENT_ID',
    defaultValue: '',
  );
}
