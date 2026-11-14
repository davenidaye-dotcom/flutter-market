
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../config/env/env_config.dart';

enum ShieldStatus { pending, ready, failed }

class ShieldGate {
  ShieldGate._();

  static const _channel = MethodChannel('flyroom/shield');
  static const _budget = Duration(seconds: 15);

  static ShieldStatus status = ShieldStatus.pending;
  static Future<void>? _start;

  static bool get blocksBusiness =>
      EnvConfig.environment == AppEnvironment.pro && status == ShieldStatus.failed;

  static Future<void> start() {
    return _start ??= _run();
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
      final endpoint = await _readEndpoint();
      if (endpoint == null) {
        status = ShieldStatus.failed;
        debugPrint('[shield] local port missing');
        return;
      }
      status = ShieldStatus.ready;
      debugPrint('[shield] ready');
    } catch (_) {
      status = ShieldStatus.failed;
      debugPrint('[shield] init failed');
    }
  }

  static Future<({String ip, int port})?> localEndpoint() async {
    await start();
    if (status != ShieldStatus.ready) return null;
    try {
      return await _readEndpoint();
    } catch (_) {
      return null;
    }
  }

  static Future<({String ip, int port})?> _readEndpoint() async {
    final raw = await _channel.invokeMapMethod<String, dynamic>('localPort').timeout(_budget);
    final ip = raw?['ip']?.toString() ?? '';
    final portValue = raw?['port'];
    final port = portValue is int ? portValue : int.tryParse('$portValue') ?? -1;
    if (ip.isEmpty || port <= 0) return null;
    return (ip: ip, port: port);
  }
}
