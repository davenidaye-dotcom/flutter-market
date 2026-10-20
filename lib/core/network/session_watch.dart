import 'dart:async';

import 'flyroom_ws_client.dart';
import 'session_kick.dart';
import 'session_store.dart';

/// 登录后一直挂着的会话连接。
///
/// 旧包只在直播页有这条连接。代理停在自己的页面时收不到踢线。
/// 新包用和直播相同的 SESSION_KICKED，空闲页也会回登录页。
class SessionWatch {
  FlyroomWsClient? _client;
  StreamSubscription<Map<String, dynamic>>? _sub;
  Timer? _retry;
  int _gen = 0;
  bool _host = false;
  bool _active = false;

  void sync({required bool loggedIn, required bool host}) {
    final token = SessionStore.instance.accessToken;
    if (!loggedIn || token == null || token.isEmpty) {
      stop();
      return;
    }
    if (_active && _client != null && _host == host) return;
    _host = host;
    _active = true;
    unawaited(_open());
  }

  Future<void> _open() async {
    final gen = ++_gen;
    _retry?.cancel();
    await _dropClient();
    if (!_active || gen != _gen) return;
    final client = FlyroomWsClient(
      role: _host ? FlyroomWsRole.owner : FlyroomWsRole.member,
      onDisconnected: () => _onLost(gen),
    );
    try {
      await client.connect();
    } catch (_) {
      await client.dispose();
      _schedule(gen);
      return;
    }
    if (!_active || gen != _gen) {
      await client.dispose();
      return;
    }
    _client = client;
    _sub = client.events.listen(_onEvent);
  }

  void _onEvent(Map<String, dynamic> event) {
    final merged = Map<String, dynamic>.from(event);
    final data = event['data'];
    if (data is Map) {
      merged.addAll(Map<String, dynamic>.from(data));
    }
    final type = (merged['event'] ?? merged['type'] ?? '').toString().toUpperCase();
    if (type != 'SESSION_KICKED') return;
    final token = _client?.sessionToken;
    final message = merged['message']?.toString() ?? '';
    _active = false;
    _gen++;
    _retry?.cancel();
    _retry = null;
    if (token != null && token.isNotEmpty) {
      SessionKick.signal(token, message: message);
    }
  }

  void _onLost(int gen) {
    if (!_active || gen != _gen) return;
    _schedule(gen);
  }

  void _schedule(int gen) {
    if (!_active || gen != _gen) return;
    _retry?.cancel();
    _retry = Timer(const Duration(seconds: 2), () {
      if (_active && gen == _gen) unawaited(_open());
    });
  }

  void stop() {
    _active = false;
    _gen++;
    _retry?.cancel();
    _retry = null;
    unawaited(_dropClient());
  }

  Future<void> _dropClient() async {
    await _sub?.cancel();
    _sub = null;
    final client = _client;
    _client = null;
    if (client != null) await client.dispose();
  }
}
