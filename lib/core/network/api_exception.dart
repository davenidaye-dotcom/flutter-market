import 'package:dio/dio.dart';

import '../security/vpn_guard.dart';

class ApiException implements Exception {
  const ApiException({
    required this.message,
    this.code,
    this.bizCode,
    this.isNetwork = false,
  });

  final String message;
  final int? code;

  /// 业务错误码，如 BET_BUSY / SEALED / BET_REQ_NOT_FOUND。
  final String? bizCode;

  /// 超时 / 断网 / 网关错误：请求可能已到达服务端，不能当成业务失败。
  final bool isNetwork;

  factory ApiException.fromDio(DioException error) {
    if (error.error is VpnBlockedException) {
      return const ApiException(
        message: VpnBlockedException.message,
        bizCode: 'VPN_BLOCKED',
        isNetwork: true,
      );
    }
    final status = error.response?.statusCode;
    if (status == 502 || status == 503 || status == 504) {
      return ApiException(message: '系统维护中', code: status, isNetwork: true);
    }
    final data = error.response?.data;
    if (data is Map) {
      final msg = data['msg'] ?? data['message'];
      if (msg is String && msg.isNotEmpty) {
        return ApiException(
          message: msg,
          code: data['code'] is int ? data['code'] as int : status,
          bizCode: bizCodeOf(data),
        );
      }
    }
    if (error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.sendTimeout ||
        error.type == DioExceptionType.receiveTimeout ||
        error.type == DioExceptionType.connectionError) {
      return const ApiException(message: '系统维护中', isNetwork: true);
    }
    return ApiException(
      message: error.message ?? '网络请求失败',
      code: status,
      isNetwork: error.response == null,
    );
  }

  @override
  String toString() => message;
}

/// 信封里的业务码：errorCode / errCode / bizCode，或非数字的 code。
String? bizCodeOf(Map data) {
  for (final k in const ['errorCode', 'errCode', 'bizCode', 'error']) {
    final v = data[k];
    if (v is String && v.isNotEmpty) return v;
  }
  final code = data['code'];
  if (code is String && int.tryParse(code) == null && code.isNotEmpty) return code;
  return null;
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
      bizCode: bizCodeOf(raw),
    );
  }
  return raw.containsKey('data') ? raw['data'] : raw;
}
