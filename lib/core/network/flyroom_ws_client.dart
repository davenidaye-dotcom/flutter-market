import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../config/env/env_config.dart';
import 'session_store.dart';
import 'ws_message_codec.dart';

enum FlyroomWsRole { member, owner }

/// FlyRoom WS：解码与 UI 解耦。帧严格按到达顺序投递：小帧主线程内联解码，
/// 大帧交给一个常驻 isolate，后面的帧排在它后面，不会反超。
class FlyroomWsClient {
  FlyroomWsClient({this.role = FlyroomWsRole.member, this.onDisconnected});

  final FlyroomWsRole role;
  final VoidCallback? onDisconnected;
  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  final _controller = StreamController<Map<String, dynamic>>.broadcast();
  final Queue<dynamic> _pendingRaw = Queue();
  bool _pumping = false;
  int _pumpGen = 0;
  _WsDecodeWorker? _worker;

  /// 超过它的文本帧才送 isolate；小帧内联解码比跨 isolate 拷贝更快。
  static const _inlineDecodeLimit = 64 * 1024;
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
        if (!_pumping) unawaited(_pump());
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

  /// 单消费者队列：同步消化小帧，遇到大帧 await isolate，保证投递顺序 = 到达顺序。
  Future<void> _pump() async {
    _pumping = true;
    final gen = _pumpGen;
    try {
      while (_pendingRaw.isNotEmpty) {
        final raw = _pendingRaw.removeFirst();
        Map<String, dynamic>? decoded;
        if (raw is Map) {
          decoded = Map<String, dynamic>.from(raw);
        } else if (raw is String) {
          if (raw.length > _inlineDecodeLimit) {
            decoded = await (_worker ??= _WsDecodeWorker()).decode(raw);
            if (gen != _pumpGen) return;
          } else {
            decoded = decodeWsJsonFrame(raw);
          }
        }
        if (decoded != null && !_controller.isClosed) {
          _controller.add(decoded);
        }
      }
    } finally {
      if (gen == _pumpGen) _pumping = false;
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
    _pumpGen++;
    _pumping = false;
    _worker?.dispose();
    _worker = null;
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

/// 常驻解码 isolate：请求/响应按 id 配对，调用方 await 完成即得到有序结果。
class _WsDecodeWorker {
  _WsDecodeWorker();

  final _replies = ReceivePort();
  final Map<int, Completer<Map<String, dynamic>?>> _waiting = {};
  Isolate? _isolate;
  SendPort? _send;
  Future<void>? _starting;
  int _nextId = 0;
  bool _disposed = false;

  Future<void> _start() async {
    final ready = Completer<SendPort>();
    _replies.listen((msg) {
      if (msg is SendPort) {
        if (!ready.isCompleted) ready.complete(msg);
        return;
      }
      if (msg is List && msg.length == 2) {
        final c = _waiting.remove(msg[0] as int);
        if (c != null && !c.isCompleted) {
          final m = msg[1];
          c.complete(m is Map ? Map<String, dynamic>.from(m) : null);
        }
      }
    });
    _isolate = await Isolate.spawn(_decodeLoop, _replies.sendPort);
    _send = await ready.future;
  }

  Future<Map<String, dynamic>?> decode(String raw) async {
    if (_disposed) return null;
    try {
      await (_starting ??= _start());
    } catch (_) {
      // isolate 起不来就退回主线程解码，仍保持顺序
      return decodeWsJsonFrame(raw);
    }
    final send = _send;
    if (_disposed || send == null) return null;
    final id = _nextId++;
    final c = Completer<Map<String, dynamic>?>();
    _waiting[id] = c;
    send.send([id, raw]);
    return c.future;
  }

  void dispose() {
    _disposed = true;
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _replies.close();
    for (final c in _waiting.values) {
      if (!c.isCompleted) c.complete(null);
    }
    _waiting.clear();
  }
}

void _decodeLoop(SendPort replyTo) {
  final inbox = ReceivePort();
  replyTo.send(inbox.sendPort);
  inbox.listen((msg) {
    if (msg is List && msg.length == 2) {
      replyTo.send([msg[0], decodeWsJsonFrame(msg[1] as String)]);
    }
  });
}
