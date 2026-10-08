import 'package:dio/dio.dart';

class ApiException implements Exception {
  const ApiException({required this.message, this.code});

  final String message;
  final int? code;

  factory ApiException.fromDio(DioException error) {
    final status = error.response?.statusCode;
    if (status == 502 || status == 503 || status == 504) {
      return ApiException(message: '系统维护中', code: status);
    }
    final data = error.response?.data;
    if (data is Map) {
      final msg = data['msg'] ?? data['message'];
      if (msg is String && msg.isNotEmpty) {
        return ApiException(
          message: msg,
          code: data['code'] is int ? data['code'] as int : status,
        );
      }
    }
    if (error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.receiveTimeout) {
      return const ApiException(message: '系统维护中');
    }
    if (error.type == DioExceptionType.connectionError) {
      return const ApiException(message: '系统维护中');
    }
    return ApiException(
      message: error.message ?? '网络请求失败',
      code: status,
    );
  }

  @override
  String toString() => message;
}

/// Unwrap FlyRoom envelope `{code,msg,data}`; throws [ApiException] when code != 200.
dynamic unwrapResponse(Response response) {
  final raw = response.data;
  if (raw is! Map) return raw;
  final code = raw['code'];
  final codeInt = code is int ? code : int.tryParse('$code');
  if (codeInt != null && codeInt != 200) {
    throw ApiException(
      message: (raw['msg'] ?? raw['message'] ?? '\u8bf7\u6c42\u5931\u8d25').toString(),
      code: codeInt,
    );
  }
  return raw.containsKey('data') ? raw['data'] : raw;
}
