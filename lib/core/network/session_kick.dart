import 'package:dio/dio.dart';

import 'session_store.dart';

/// 服务端注销登录后，清本地 token 并回到登录页。
///
/// 只踢发这次请求时用的那张 token。登录页打开就会跑设备快登，
/// 它的 401 若晚于密码登录返回，不能把刚写入的会话清掉。
class SessionKick {
  SessionKick._();

  static const tokenExtra = 'frSessionToken';
  static const skipExtra = 'frSkipKick';

  static void Function()? handler;
  static bool _busy = false;

  /// 把当前 token 记在请求上，响应回来时按这张 token 判断要不要踢。
  static void attach(RequestOptions options) {
    final token = SessionStore.instance.accessToken;
    if (token == null || token.isEmpty) return;
    options.headers['Authorization'] = 'Bearer $token';
    options.extra[tokenExtra] = token;
  }

  /// 登录、注册、设备快登的 401 是账号校验失败，不是当前会话失效。
  static void consider(RequestOptions options, dynamic data, int? status) {
    if (options.extra[skipExtra] == true) return;
    if (!_unauthorized(data, status)) return;
    if (_isCredentialExchange(options.uri.path)) return;
    final sent = options.extra[tokenExtra];
    if (sent is! String || sent.isEmpty) return;
    signal(sent);
  }

  static void signal(String token) {
    if (_busy || token.isEmpty) return;
    final now = SessionStore.instance.accessToken;
    if (now == null || now.isEmpty || now != token) return;
    _busy = true;
    try {
      handler?.call();
    } finally {
      _busy = false;
    }
  }

  /// `device-login` 不以 `/login` 结尾，必须单独排除。
  static bool _isCredentialExchange(String path) {
    return path.endsWith('/login') ||
        path.endsWith('/device-login') ||
        path.endsWith('/register');
  }

  static bool _unauthorized(dynamic data, int? status) {
    if (status == 401) return true;
    if (data is Map) {
      final code = data['code'];
      final n = code is int ? code : int.tryParse('$code');
      if (n == 401) return true;
    }
    return false;
  }
}
