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
      return ApiException(
        message: '系统维护中',
        code: status,
        bizCode: 'INTERNAL',
        isNetwork: true,
      );
    }
    final data = error.response?.data;
    if (data is Map) {
      final msg = data['msg'] ?? data['message'];
      if (msg is String && msg.isNotEmpty) {
        final code = data['code'] is int ? data['code'] as int : status;
        return ApiException(
          message: msg,
          code: code,
          bizCode: bizCodeOf(data) ?? loginFailureKind(msg, code),
        );
      }
    }
    if (error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.sendTimeout ||
        error.type == DioExceptionType.receiveTimeout ||
        error.type == DioExceptionType.connectionError) {
      return const ApiException(
        message: '系统维护中',
        bizCode: 'TIMEOUT',
        isNetwork: true,
      );
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

/// 登录失败分类。其它页面仍用 [ApiException.message]，避免下注、聊天文案被改掉。
/// 返回 `TOKEN` / `TIMEOUT` / `INTERNAL`，业务拒绝返回 null。
String? loginFailureKind(String message, int? code) {
  if (message == '系统维护中' || message.contains('维护')) return null;
  if (message.contains('其他地方')) return null;
  if (message.contains('登录已失效') ||
      message.contains('认证失败，无法访问系统资源') ||
      message == '登录失败：无 Token' ||
      code == 401) {
    return 'TOKEN';
  }
  if (message.contains('发生系统异常') || message.contains('发生未知异常')) {
    return 'INTERNAL';
  }
  return null;
}

/// 登录页和被踢回登录页的提示。密码错误等业务文案原样保留。
String loginFailureText(Object error) {
  if (error is! ApiException) {
    final text = error.toString().trim();
    return text.isEmpty ? '系统异常' : text;
  }
  final kind = error.bizCode == 'TOKEN' ||
          error.bizCode == 'TIMEOUT' ||
          error.bizCode == 'INTERNAL'
      ? error.bizCode
      : loginFailureKind(error.message, error.code);
  return switch (kind) {
    'TOKEN' => '请重新登录',
    'TIMEOUT' => '请求超时 检查网络重新登录',
    'INTERNAL' => '系统异常',
    _ when error.message == '系统维护中' || error.bizCode == 'MAINT_MODE' =>
      '系统维护中',
    _ => error.message.trim().isEmpty ? '系统异常' : error.message,
  };
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
