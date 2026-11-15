
import 'dart:async';

import 'package:flutter/services.dart';

enum ShieldStatus { pending, ready, failed }

class ShieldGate {
  ShieldGate._();

  static const _channel = MethodChannel('flyroom/shield');
  static const _budget = Duration(seconds: 15);

  static ShieldStatus status = ShieldStatus.pending;
  static Future<void>? _start;

  /// 备用包不走游戏盾。初始化失败不能把业务请求挡成线路未就绪。
  static bool get blocksBusiness => false;

  static Future<void> start() {
    return _start ??= _run();
  }

  static Future<void> _run() async {
    status = ShieldStatus.ready;
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
