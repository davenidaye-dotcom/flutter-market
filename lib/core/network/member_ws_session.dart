import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'flyroom_ws_client.dart';

/// 登录后的会员 WS。首页和房间共用一条，离开房间只退订游戏，不断开 user 频道。
/// 还有持有者时断线会重连。退出登录调用 [suspend]，避免旧连接被当成新登录的连接。
class MemberWsSession {
  MemberWsSession._();

  static final MemberWsSession instance = MemberWsSession._();

  final _events = StreamController<Map<String, dynamic>>.broadcast();
  final List<VoidCallback> _disconnects = [];
  FlyroomWsClient? _client;
  StreamSubscription? _pipe;
  Future<void> _tail = Future<void>.value();
  Timer? _reconnectTimer;
  int _holders = 0;
  int _reconnectAttempt = 0;
  bool _suspended = false;
  Set<String> features = const {};

  Stream<Map<String, dynamic>> get events => _events.stream;

  FlyroomWsClient? get client =>
      _client != null && _client!.isConnected ? _client : null;

  Future<void> acquire() async {
    _suspended = false;
    _holders++;
    try {
      await ensureConnected();
      _reconnectAttempt = 0;
    } catch (_) {
      _scheduleReconnect();
    }
  }

  void release() {
    if (_holders > 0) _holders--;
    if (_holders == 0) {
      _reconnectTimer?.cancel();
      _reconnectTimer = null;
      unawaited(_shutdown());
    }
  }

  /// 退出、被踢或换账号。拆掉当前连接，直到下一次 [acquire] 才允许重连。
  void suspend() {
    _suspended = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    unawaited(_shutdown());
  }

  void addDisconnectListener(VoidCallback listener) {
    _disconnects.add(listener);
  }

  void removeDisconnectListener(VoidCallback listener) {
    _disconnects.remove(listener);
  }

  Future<FlyroomWsClient> ensureConnected() {
    return _exclusive(() async {
      if (_suspended) {
        throw StateError('member ws suspended');
      }
      final current = client;
      if (current != null) return current;
      return _open();
    });
  }

  Future<T> _exclusive<T>(Future<T> Function() body) {
    final result = _tail.then((_) => body());
    _tail = result.then((_) {}, onError: (_) {});
    return result;
  }

  Future<FlyroomWsClient> _open() async {
    late final FlyroomWsClient client;
    client = FlyroomWsClient(
      role: FlyroomWsRole.member,
      onDisconnected: () {
        if (!identical(_client, client)) return;
        _client = null;
        features = const {};
        unawaited(_pipe?.cancel());
        _pipe = null;
        for (final listener in List<VoidCallback>.of(_disconnects)) {
          listener();
        }
        _scheduleReconnect();
      },
    );
    await client.connect();
    if (_suspended || _holders == 0 || !client.isConnected) {
      await client.dispose();
      throw StateError('member ws not connected');
    }
    _client = client;
    _pipe = client.events.listen((event) {
      if (identical(_client, client) && !_events.isClosed) {
        final type = '${event['event'] ?? ''}'.toUpperCase();
        if (type == 'CONNECTED') {
          final data = event['data'];
          final raw = data is Map ? data['features'] : event['features'];
          features = {
            if (raw is List) for (final e in raw) '$e'.toUpperCase(),
          };
        }
        _events.add(event);
      }
    });
    _reconnectAttempt = 0;
    return client;
  }

  void _scheduleReconnect() {
    if (_suspended || _holders == 0 || client != null || _reconnectTimer != null) {
      return;
    }
    final attempt = _reconnectAttempt;
    _reconnectAttempt = math.min(5, _reconnectAttempt + 1);
    // 第一次马上重连，避免停在首页时把刚通过的房间推送错过。失败后再退避。
    final delay = attempt == 0
        ? Duration.zero
        : Duration(seconds: math.min(30, 1 << math.min(5, attempt - 1)));
    _reconnectTimer = Timer(delay, () {
      _reconnectTimer = null;
      if (_suspended || _holders == 0 || client != null) return;
      unawaited(() async {
        try {
          await ensureConnected();
          _reconnectAttempt = 0;
        } catch (_) {
          _scheduleReconnect();
        }
      }());
    });
  }

  /// 连接还没好就返回 null，调用方走 HTTP。发出去之后等回执，不再并行打 HTTP。
  Future<MemberEnterFrame?> tryEnter({
    required String roomCode,
    String? enterPassword,
  }) async {
    final socket = client;
    if (socket == null) return null;
    final code = roomCode.trim();
    final done = Completer<MemberEnterFrame>();
    late final StreamSubscription<Map<String, dynamic>> sub;
    sub = events.listen((event) {
      final type = '${event['event'] ?? ''}'.toUpperCase();
      if (type != 'ENTER_ROOM_OK' && type != 'ENTER_ROOM_FAIL') return;
      final data = event['data'];
      final map = data is Map
          ? Map<String, dynamic>.from(data)
          : Map<String, dynamic>.from(event);
      final got = '${map['roomCode'] ?? ''}'.trim();
      if (got.isNotEmpty && got != code) return;
      if (!done.isCompleted) {
        done.complete(MemberEnterFrame(
          ok: type == 'ENTER_ROOM_OK',
          data: map,
          code: '${map['code'] ?? ''}',
          message: '${map['message'] ?? ''}',
        ));
      }
    });
    socket.send({
      'action': 'ENTER_ROOM',
      'data': {
        'roomCode': code,
        if (enterPassword != null && enterPassword.isNotEmpty)
          'enterPassword': enterPassword,
      },
    });
    try {
      return await done.future.timeout(const Duration(seconds: 8));
    } on TimeoutException {
      return MemberEnterFrame(
        ok: false,
        data: const {'roomCode': ''},
        code: 'ENTER_TIMEOUT',
        message: '进房超时，请重试',
      );
    } finally {
      await sub.cancel();
    }
  }

  Future<void> _shutdown() {
    return _exclusive(() async {
      _reconnectTimer?.cancel();
      _reconnectTimer = null;
      final client = _client;
      _client = null;
      features = const {};
      final pipe = _pipe;
      _pipe = null;
      await pipe?.cancel();
      if (client != null) {
        await client.dispose();
      }
    });
  }
}

class MemberEnterFrame {
  const MemberEnterFrame({
    required this.ok,
    required this.data,
    required this.code,
    required this.message,
  });

  final bool ok;
  final Map<String, dynamic> data;
  final String code;
  final String message;
}
