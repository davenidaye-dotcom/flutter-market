
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../config/env/env_config.dart';

enum ShieldStatus { pending, ready, failed }

class ShieldGate {
  ShieldGate._();

  static const _channel = MethodChannel('flyroom/shield');
  static const _budget = Duration(seconds: 15);

  /// 只放进 HTTP Host，不拿去解析，也不传给四层要端口。
  static const ruleHost = 'www.demo.com';

  static void attachRuleHost(Map<String, dynamic> headers) {
    if (EnvConfig.environment != AppEnvironment.pro) return;
    headers['host'] = ruleHost;
  }

  static ShieldStatus status = ShieldStatus.pending;
  static Future<void>? _start;
  static Future<void>? _stopping;
  static Timer? _retryTimer;
  static var _retryStep = 0;
  static DateTime? _notBefore;
  static var _open = false;
  static var _inited = false;
  static var _needReinit = false;
  static ({String ip, int port})? _last;
  static final List<void Function()> _portListeners = [];

  static void addPortListener(void Function() listener) {
    _portListeners.add(listener);
  }

  static void removePortListener(void Function() listener) {
    _portListeners.remove(listener);
  }

  static bool get blocksBusiness =>
      EnvConfig.environment == AppEnvironment.pro && status == ShieldStatus.failed;

  static Future<void> start() {
    _open = true;
    if (_inited) return Future<void>.value();
    return _start ??= _run();
  }

  /// 关掉本地监听。init 成功过就不再初始化第二次，下次只重新要端口。
  static void release() {
    _open = false;
    _cancelPortRetry();
    if (EnvConfig.environment == AppEnvironment.pro && _inited) {
      _needReinit = true;
      _stopping = _stopNative();
    }
    if (!_inited && status == ShieldStatus.failed) {
      status = ShieldStatus.pending;
      _start = null;
    }
  }

  static Future<void> _stopNative() async {
    try {
      await _channel.invokeMethod<bool>('stop').timeout(_budget);
    } catch (_) {}
  }

  static Future<void> _run() async {
    if (EnvConfig.environment != AppEnvironment.pro) {
      status = ShieldStatus.ready;
      return;
    }
    try {
      final ok = await _channel.invokeMethod<bool>('init').timeout(_budget);
      if (ok != true) {
        status = ShieldStatus.failed;
        debugPrint('[shield] init failed');
        return;
      }
      _inited = true;
      final endpoint = await _readOrReinit();
      if (endpoint == null) {
        status = ShieldStatus.failed;
        debugPrint('[shield] local port missing');
        return;
      }
      _last = endpoint;
      status = ShieldStatus.ready;
      debugPrint('[shield] ready');
    } catch (_) {
      status = ShieldStatus.failed;
      debugPrint('[shield] init failed');
    }
  }

  static Future<({String ip, int port})?> localEndpoint() async {
    if (!_open) return null;
    await start();
    if (!_inited && status != ShieldStatus.ready) return null;
    if (_waitingForRetry) return null;
    try {
      var endpoint = await _readOrReinit();
      if (endpoint == null && _open && _inited) {
        endpoint = await _readOrReinit();
      }
      if (endpoint == null) {
        status = ShieldStatus.failed;
        _armPortRetry();
        return null;
      }
      _acceptPort(endpoint, notify: false);
      return endpoint;
    } catch (_) {
      status = ShieldStatus.failed;
      _armPortRetry();
      return null;
    }
  }

  /// 已经 init 成功但上次没要到端口。间隔没到就不再打原生接口。
  static Future<void> retryPortIfInited() async {
    if (EnvConfig.environment != AppEnvironment.pro) return;
    if (!_open || !_inited || status != ShieldStatus.failed) return;
    if (_waitingForRetry) return;
    try {
      final endpoint = await _readOrReinit();
      if (endpoint == null) {
        status = ShieldStatus.failed;
        _armPortRetry();
        return;
      }
      _acceptPort(endpoint, notify: true);
    } catch (_) {
      status = ShieldStatus.failed;
      _armPortRetry();
    }
  }

  static bool get _waitingForRetry =>
      _retryTimer != null ||
      (_notBefore != null && DateTime.now().isBefore(_notBefore!));

  static void _armPortRetry() {
    if (!_open || !_inited || _retryTimer != null) return;
    const steps = [2, 4, 8, 16, 30];
    final seconds = steps[_retryStep];
    if (_retryStep < steps.length - 1) _retryStep++;
    final delay = Duration(seconds: seconds);
    _notBefore = DateTime.now().add(delay);
    _retryTimer = Timer(delay, () {
      unawaited(_retryFromTimer());
    });
  }

  static Future<void> _retryFromTimer() async {
    _retryTimer = null;
    _notBefore = null;
    if (!_open || !_inited || status != ShieldStatus.failed) return;
    try {
      final endpoint = await _readOrReinit();
      if (!_open || !_inited) return;
      if (endpoint == null) {
        status = ShieldStatus.failed;
        _armPortRetry();
        return;
      }
      _acceptPort(endpoint, notify: true);
    } catch (_) {
      if (!_open || !_inited) return;
      status = ShieldStatus.failed;
      _armPortRetry();
    }
  }

  static void _acceptPort(({String ip, int port}) endpoint, {required bool notify}) {
    _last = endpoint;
    status = ShieldStatus.ready;
    _retryStep = 0;
    _notBefore = null;
    _retryTimer?.cancel();
    _retryTimer = null;
    if (notify) _notifyPort();
  }

  static void _cancelPortRetry() {
    _retryTimer?.cancel();
    _retryTimer = null;
    _notBefore = null;
    _retryStep = 0;
  }

  static void _notifyPort() {
    for (final listener in List<void Function()>.of(_portListeners)) {
      listener();
    }
  }

  /// 回到前台时重新要端口。变了才通知长连接重连。
  static Future<bool> refreshAfterResume() async {
    if (!_open || !_inited) return false;
    _retryTimer?.cancel();
    _retryTimer = null;
    _notBefore = null;
    final wasFailed = status == ShieldStatus.failed;
    final previous = _last;
    try {
      final endpoint = await _readOrReinit();
      if (!_open || !_inited) return false;
      if (endpoint == null) {
        status = ShieldStatus.failed;
        _armPortRetry();
        return false;
      }
      final changed = wasFailed ||
          previous == null ||
          previous.ip != endpoint.ip ||
          previous.port != endpoint.port;
      _acceptPort(endpoint, notify: changed);
      return changed;
    } catch (_) {
      if (!_open || !_inited) return false;
      status = ShieldStatus.failed;
      _armPortRetry();
      return false;
    }
  }

  static Future<({String ip, int port})?> _readOrReinit() async {
    final stopping = _stopping;
    if (stopping != null) await stopping;
    var endpoint = await _readEndpoint();
    if (endpoint != null) {
      _needReinit = false;
      return endpoint;
    }
    if (!_needReinit || defaultTargetPlatform != TargetPlatform.iOS) return null;
    _needReinit = false;
    try {
      final ok = await _channel.invokeMethod<bool>('reinit').timeout(_budget);
      if (ok != true) return null;
      return _readEndpoint();
    } catch (_) {
      return null;
    }
  }

  static Future<({String ip, int port})?> _readEndpoint() async {
    final raw = await _channel
        .invokeMapMethod<String, dynamic>('localPort', '')
        .timeout(_budget);
    final ip = raw?['ip']?.toString() ?? '';
    final portValue = raw?['port'];
    final port = portValue is int ? portValue : int.tryParse('$portValue') ?? -1;
    if (ip.isEmpty || port <= 0) return null;
    return (ip: ip, port: port);
  }
}
