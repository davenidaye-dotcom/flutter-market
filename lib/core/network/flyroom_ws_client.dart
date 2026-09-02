import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../config/env/env_config.dart';
import 'session_store.dart';
import 'ws_message_codec.dart';

enum FlyroomWsRole { member, owner }

/// FlyRoom WS：解码与 UI 解耦，突发多帧合并到单次 microtask，大帧走 isolate。
class FlyroomWsClient {
  FlyroomWsClient({this.role = FlyroomWsRole.member, this.onDisconnected});

  final FlyroomWsRole role;
  final VoidCallback? onDisconnected;
  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  final _controller = StreamController<Map<String, dynamic>>.broadcast();
  final List<dynamic> _pendingRaw = [];
  bool _flushScheduled = false;
  bool _closing = false;
  bool _disconnectNotified = false;

  Stream<Map<String, dynamic>> get events => _controller.stream;
  bool get isConnected => _channel != null;

  Uri get _uri {
    final token = SessionStore.instance.accessToken ?? '';
    final path = role == FlyroomWsRole.owner ? 'owner' : 'member';
    return Uri.parse('${EnvConfig.wsBaseUrl}/$path?token=$token');
  }

  Future<void> connect() async {
    await disconnect();
    _disconnectNotified = false;
    final ch = WebSocketChannel.connect(_uri);
    _channel = ch;
    _sub = ch.stream.listen(
      (raw) {
        _pendingRaw.add(raw);
        _scheduleDecodeFlush();
      },
      onError: (_) => _notifyDisconnected(),
      onDone: _notifyDisconnected,
    );
  }

  void _notifyDisconnected() {
    if (_closing || _disconnectNotified) return;
    _disconnectNotified = true;
    _channel = null;
    onDisconnected?.call();
  }

  void _scheduleDecodeFlush() {
    if (_flushScheduled) return;
    _flushScheduled = true;
    scheduleMicrotask(() {
      _flushScheduled = false;
      if (_pendingRaw.isEmpty) return;
      final batch = List<dynamic>.from(_pendingRaw);
      _pendingRaw.clear();
      for (final raw in batch) {
        unawaited(_emitDecoded(raw));
      }
    });
  }

  Future<void> _emitDecoded(dynamic raw) async {
    if (_controller.isClosed) return;
    if (raw is Map) {
      _controller.add(Map<String, dynamic>.from(raw));
      return;
    }
    if (raw is! String) return;

    Map<String, dynamic>? decoded;
    if (raw.length > 1024) {
      decoded = await compute(decodeWsJsonFrame, raw);
    } else {
      decoded = decodeWsJsonFrame(raw);
    }
    if (decoded != null && !_controller.isClosed) {
      _controller.add(decoded);
    }
  }

  void subscribe(String topic) {
    send({'action': 'SUBSCRIBE', 'topic': topic});
  }

  void unsubscribe(String topic) {
    send({'action': 'UNSUBSCRIBE', 'topic': topic});
  }

  void ping() => send({'action': 'PING'});

  void send(Map<String, dynamic> payload) {
    final ch = _channel;
    if (ch == null) return;
    ch.sink.add(jsonEncode(payload));
  }

  Future<void> disconnect() async {
    _closing = true;
    _disconnectNotified = true;
    _pendingRaw.clear();
    _flushScheduled = false;
    await _sub?.cancel();
    _sub = null;
    try {
      await _channel?.sink.close();
    } catch (_) {}
    _channel = null;
    _closing = false;
  }

  Future<void> dispose() async {
    await disconnect();
    await _controller.close();
  }
}
