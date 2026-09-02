import 'package:dio/dio.dart';

class ApiException implements Exception {
  const ApiException({required this.message, this.code});

  final String message;
  final int? code;

  factory ApiException.fromDio(DioException error) {
    final data = error.response?.data;
    if (data is Map) {
      final msg = data['msg'] ?? data['message'];
      if (msg is String && msg.isNotEmpty) {
        return ApiException(
          message: msg,
          code: data['code'] is int ? data['code'] as int : error.response?.statusCode,
        );
      }
    }
    if (error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.receiveTimeout) {
      return const ApiException(message: '\u7f51\u7edc\u8d85\u65f6\uff0c\u8bf7\u7a0d\u540e\u91cd\u8bd5');
    }
    if (error.type == DioExceptionType.connectionError) {
      return const ApiException(message: '\u7f51\u7edc\u8fde\u63a5\u5931\u8d25');
    }
    return ApiException(
      message: error.message ?? '\u7f51\u7edc\u8bf7\u6c42\u5931\u8d25',
      code: error.response?.statusCode,
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
