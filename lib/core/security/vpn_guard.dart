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
/// 开发调试要抓包时：`--dart-define=ALLOW_VPN=true`。
class VpnGuard {
  VpnGuard._();

  static const _channel = MethodChannel('flyroom/security');
  static const _allowVpn = bool.fromEnvironment('ALLOW_VPN');

  static bool _last = false;
  static DateTime _checkedAt = DateTime.fromMillisecondsSinceEpoch(0);
  static Future<bool>? _inflight;

  /// 同一秒内的请求共用一次原生检查，避免每个请求都过一遍 MethodChannel。
  static Future<bool> active() {
    if (_allowVpn || kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return Future.value(false);
    }
    if (DateTime.now().difference(_checkedAt) < const Duration(seconds: 1)) {
      return Future.value(_last);
    }
    return _inflight ??= _query().whenComplete(() => _inflight = null);
  }

  static Future<bool> _query() async {
    try {
      _last = await _channel.invokeMethod<bool>('isVpnActive') ?? false;
    } on MissingPluginException {
      _last = false;
    } catch (_) {
      _last = false;
    }
    _checkedAt = DateTime.now();
    return _last;
  }

  static Future<void> assertClear() async {
    if (await active()) throw const VpnBlockedException();
  }
}
