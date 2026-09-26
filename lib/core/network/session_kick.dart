import 'session_store.dart';

/// 服务端注销登录后，清本地 token 并回到登录页。
class SessionKick {
  SessionKick._();

  static void Function()? handler;
  static bool _busy = false;

  static void signal() {
    if (_busy || !SessionStore.instance.hasToken) return;
    _busy = true;
    try {
      handler?.call();
    } finally {
      _busy = false;
    }
  }
}
