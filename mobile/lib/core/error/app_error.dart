import 'package:dio/dio.dart';

enum AppErrorCode {
  unauthorized,
  accountDeactivated,
  forbidden,
  networkError,
  serverError,
  unknown,
}

class AppError implements Exception {
  const AppError({
    required this.message,
    required this.code,
    this.statusCode,
  });

  final String message;
  final AppErrorCode code;
  final int? statusCode;

  factory AppError.fromDioException(DioException e) {
    final response = e.response;
    if (response == null) {
      return AppError(
        message: '네트워크 연결을 확인해 주세요.',
        code: AppErrorCode.networkError,
      );
    }

    final data = response.data;
    final serverCode = (data is Map) ? data['code'] as String? : null;
    final detail = (data is Map) ? data['detail'] as String? : null;

    return switch (serverCode) {
      'UNAUTHORIZED' => AppError(
          message: detail ?? '인증이 필요합니다.',
          code: AppErrorCode.unauthorized,
          statusCode: response.statusCode,
        ),
      'ACCOUNT_DEACTIVATED' => AppError(
          message: detail ?? '계정이 정지되었습니다.',
          code: AppErrorCode.accountDeactivated,
          statusCode: response.statusCode,
        ),
      'FORBIDDEN' => AppError(
          message: detail ?? '권한이 없습니다.',
          code: AppErrorCode.forbidden,
          statusCode: response.statusCode,
        ),
      _ => AppError(
          message: detail ?? '서버 오류가 발생했습니다.',
          code: response.statusCode != null && response.statusCode! >= 500
              ? AppErrorCode.serverError
              : AppErrorCode.unknown,
          statusCode: response.statusCode,
        ),
    };
  }

  @override
  String toString() => message;
}
