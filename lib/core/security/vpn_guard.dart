import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 检测到 VPN，本次请求没有发出去。
class VpnBlockedException implements Exception {
  const VpnBlockedException();

  static const message = '检测到 VPN 或代理，请关闭后重试';

  @override
  String toString() => message;
}

/// 出网前先看本机有没有 VPN。抓包软件的 VPN 模式会把整机流量引到虚拟网卡，
/// 只要 App 发起连接，它就能看到 CONNECT。这里直接不发。
///
/// 「没有 VPN」的结果不能缓存。房间里每秒有一次查询，WebSocket 被掐断还会马上补拉。
/// 中途打开抓包的那一秒如果还拿着旧结果，这两下就会连出去，抓包列表里出现 CONNECT。
///
/// 开发调试要抓包时：`--dart-define=ALLOW_VPN=true`。
class VpnGuard {
  VpnGuard._();

  static const _channel = MethodChannel('flyroom/security');
  static const _events = EventChannel('flyroom/security/vpn');
  static const _allowVpn = bool.fromEnvironment('ALLOW_VPN');

  /// 原生回调已经确认有 VPN。之后的请求同步拦住，不再等 MethodChannel。
  static bool blocked = false;

  static bool _watching = false;
  static Future<bool>? _inflight;
  static final List<void Function(bool blocked)> _listeners = [];

  static void addListener(void Function(bool blocked) listener) {
    _listeners.add(listener);
  }

  /// 订阅 VPN 网卡出现/消失。启动时调一次即可。
  static void watch() {
    if (_watching || _allowVpn || kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return;
    }
    _watching = true;
    _events.receiveBroadcastStream().listen(
      (event) => _setBlocked(event == true),
      onError: (_) {},
    );
  }

  static void _setBlocked(bool value) {
    if (blocked == value) return;
    blocked = value;
    for (final listener in List<void Function(bool)>.of(_listeners)) {
      try {
        listener(value);
      } catch (_) {}
    }
  }

  /// 每次出网都问一次原生。问的过程中如果回调先到，以回调为准。
  static Future<bool> active() {
    if (_allowVpn || kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return Future.value(false);
    }
    if (blocked) return Future.value(true);
    return _inflight ??= _query().whenComplete(() => _inflight = null);
  }

  static Future<bool> _query() async {
    if (blocked) return true;
    var now = false;
    try {
      now = await _channel.invokeMethod<bool>('isVpnActive') ?? false;
    } on MissingPluginException {
      now = false;
    } catch (_) {
      now = false;
    }
    if (blocked || now) {
      _setBlocked(true);
      return true;
    }
    return false;
  }

  static Future<void> assertClear() async {
    if (await active()) throw const VpnBlockedException();
  }
}
