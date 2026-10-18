import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../config/env/env_config.dart';
import 'client_cert_refresh.dart';
import 'client_cert_store.dart';
import 'mtls_bind_stub.dart' if (dart.library.io) 'mtls_bind_io.dart';
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
  final List<dynamic> _pendingRaw = [];
  bool _pumping = false;
  int _pumpGen = 0;
  _WsDecodeWorker? _worker;

  /// 超过它的文本帧才送 isolate；小帧内联解码比跨 isolate 拷贝更快。
  static const _inlineDecodeLimit = 64 * 1024;
  bool _closing = false;
  bool _disconnectNotified = false;

  /// 建连时的 token。旧连接上的 SESSION_KICKED 不能踢掉后来登录的会话。
  String? sessionToken;

  Stream<Map<String, dynamic>> get events => _controller.stream;
  bool get isConnected => _channel != null;

  Uri get _uri {
    final token = SessionStore.instance.accessToken ?? '';
    final path = role == FlyroomWsRole.owner ? 'owner' : 'member';
    return Uri.parse('${EnvConfig.wsBaseUrl}/$path?token=$token');
  }

  Future<void> connect() async {
    await disconnect();
    if (!EnvConfig.requestsAllowed) {
      debugPrint('[ws] skip connect: pro oss unavailable');
      return;
    }
    _disconnectNotified = false;
    sessionToken = SessionStore.instance.accessToken;
    final ch = await _open();
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

  /// 握手被拒且手上没有可用的证：总后台可能刚打开双向证书，换一次证再连。
  Future<WebSocketChannel> _open() async {
    final store = ClientCertStore.instance;
    if (store.shouldRenew) {
      await ClientCertRefresh.refresh();
    }
    try {
      return await connectFlyroomSocket(_uri);
    } catch (_) {
      if (store.hasCert && !store.shouldRenew) rethrow;
      final result = await ClientCertRefresh.refresh();
      if (result != CertRefreshResult.installed) rethrow;
      return connectFlyroomSocket(_uri);
    }
  }

  void _notifyDisconnected() {
    if (_closing || _disconnectNotified) return;
    _disconnectNotified = true;
    _channel = null;
    onDisconnected?.call();
  }

  /// 单消费者队列：小帧同步消化，大帧交给 isolate。
  /// 积压时按车道把时钟和状态排到气泡前面，仪式帧保持原顺序。
  Future<void> _pump() async {
    _pumping = true;
    final gen = _pumpGen;
    try {
      while (_pendingRaw.isNotEmpty) {
        if (_pendingRaw.length > 1) {
          _hoistPriorityFrames();
        }
        final raw = _pendingRaw.removeAt(0);
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

  /// 积压时按车道重排，车道内部保持到达顺序。
  /// 时钟可以排到封盘和开奖前面；仪式帧本身不互相插队；气泡留在最后。
  void _hoistPriorityFrames() {
    var urgent = false;
    for (final raw in _pendingRaw) {
      if (raw is String && _sendLane(raw) < 4) {
        urgent = true;
        break;
      }
    }
    if (!urgent) return;
    final lanes = List.generate(5, (_) => <dynamic>[]);
    for (final raw in _pendingRaw) {
      final lane = raw is String ? _sendLane(raw) : 4;
      lanes[lane].add(raw);
    }
    _pendingRaw
      ..clear()
      ..addAll(lanes[0])
      ..addAll(lanes[1])
      ..addAll(lanes[2])
      ..addAll(lanes[3])
      ..addAll(lanes[4]);
  }

  /// 与服务端 {@code WsSendLane} 一致：0 连接，1 时钟，2 仪式，3 状态，4 气泡。
  static const Map<String, int> _laneByEvent = {
    'SESSION_KICKED': 0,
    'SYSTEM_MAINTAIN': 0,
    'CONNECTED': 0,
    'SUBSCRIBED': 0,
    'UNSUBSCRIBED': 0,
    'SUBSCRIBE_DENIED': 0,
    'PONG': 0,
    'BET_ACK': 0,
    'PERIOD_TICK': 1,
    'PERIOD_SNAPSHOT': 1,
    'SEAL_WARN': 2,
    'SEALED': 2,
    'DRAW_RESULT': 2,
    'BET_RANK': 2,
    'WIN_LIST': 2,
    'CHECK_SELF': 2,
    'WALLET_DELTA': 3,
    'CREDIT_DELTA': 3,
    'ROOM_WALLET_SUMMARY': 3,
    'UNREAD_CS': 3,
    'ROOM_FLAGS': 3,
    'ROOM_NAME': 3,
    'ROOM_GAMES_CHANGED': 3,
    'OWNER_DASH_DIRTY': 3,
    'CS_MESSAGE': 3,
    'APPLY_NOTICE': 3,
    'REDPACK_NOTICE': 3,
    'SITE_NOTICE': 3,
    'SETTLE_RESULT': 3,
    'LONG_DRAGON': 3,
  };

  int _sendLane(String raw) => _laneByEvent[_envelopeEvent(raw)] ?? 4;

  /// 只认信封上的第一个 event。气泡正文里如果出现同样的字样，不能因此插队。
  String _envelopeEvent(String raw) {
    const marker = '"event":"';
    final at = raw.indexOf(marker);
    if (at < 0) return '';
    final start = at + marker.length;
    final end = raw.indexOf('"', start);
    if (end < 0) return '';
    return raw.substring(start, end);
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
