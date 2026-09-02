/// Mimic every ws-test.html button on 207.148.105.182
import 'dart:convert';
import 'dart:io';

const base = 'http://207.148.105.182/api/v1';
const wsBase = 'ws://207.148.105.182/ws/v1';

Future<void> main() async {
  stdout.writeln('=== ws-test.html full button replay ===\n');

  // --- Member flow (WEB like ws-test) ---
  final mToken = await login('/auth/member/login', 'player01', 'WEB');
  if (mToken == null) return;

  await get('/member/rooms/verify?roomCode=679010', mToken, '验房 verify');
  final enter = await post('/member/rooms/enter', {'roomCode': '679010'}, mToken, '进房 enter');
  final roomId = enter?['data']?['roomId'];
  stdout.writeln('  roomId from enter: $roomId\n');

  // Member endpoints ws-test does NOT have buttons for — but App needs them
  for (final p in [
    '/member/wallet',
    '/member/rooms/games',
    '/member/bets?pageNum=1&pageSize=5',
    '/member/rooms/messages?gameType=JS_SC&limit=20',
  ]) {
    await get(p, mToken, 'GET $p', roomId: '$roomId');
  }

  await post('/member/bets', {
    'gameType': 'JS_SC',
    'items': [{'playCode': 'GYH_11', 'amount': 10}],
  }, mToken, '试下注 placeBet');

  // WS member
  await wsProbe('$wsBase/member', mToken, ['room:${roomId ?? '900010001'}:game:JS_SC'], 'WS member');

  stdout.writeln('\n--- owner portal ---\n');

  final oToken = await login('/auth/portal/login', 'owner01', 'WEB');
  if (oToken == null) return;

  await get('/auth/me', oToken, 'GET /auth/me');
  await get('/owner/room', oToken, '房主 GET /owner/room');
  await get('/owner/games', oToken, 'owner games (no button, extra)');
  await get('/owner/notices', oToken, 'owner notices (extra)');

  await wsProbe('$wsBase/owner', oToken, [
    'room:${roomId ?? '900010001'}:game:JS_SC',
    'room:${roomId ?? '900010001'}:sys',
  ], 'WS owner');

  // Test WITH vs WITHOUT X-Room-Id on wallet after enter
  stdout.writeln('\n--- X-Room-Id header test (wallet) ---');
  await get('/member/wallet', mToken, 'wallet NO X-Room-Id');
  await get('/member/wallet', mToken, 'wallet WITH X-Room-Id', roomId: '$roomId');
}

Future<String?> login(String path, String user, String clientType) async {
  final r = await _req('POST', path, body: {
    'username': user,
    'password': 'Pass1234',
    'clientType': clientType,
  });
  final code = r?['code'];
  stdout.writeln('[${code == 200 ? 'OK' : 'FAIL'}] POST $path => biz=$code msg=${r?['msg']}');
  return r?['data']?['accessToken'] as String?;
}

Future<void> get(String path, String token, String label, {String? roomId}) async {
  final r = await _req('GET', path, token: token, roomId: roomId);
  final code = r?['code'];
  stdout.writeln('[${code == 200 ? 'OK' : 'FAIL'}] $label => biz=$code msg=${r?['msg']}');
}

Future<Map?> post(String path, Map body, String token, String label) async {
  final r = await _req('POST', path, body: body, token: token);
  final code = r?['code'];
  stdout.writeln('[${code == 200 ? 'OK' : 'FAIL'}] $label => biz=$code msg=${r?['msg']}');
  return r;
}

Future<void> wsProbe(String url, String token, List<String> topics, String label) async {
  try {
    final ws = await WebSocket.connect('$url?token=$token')
        .timeout(const Duration(seconds: 10));
    final msgs = <String>[];
    final sub = ws.listen((e) => msgs.add('$e'));
    for (final t in topics) {
      ws.add(jsonEncode({'action': 'SUBSCRIBE', 'topic': t}));
    }
    ws.add(jsonEncode({'action': 'PING'}));
    await Future<void>.delayed(const Duration(seconds: 2));
    await sub.cancel();
    await ws.close();
    stdout.writeln('[OK] $label => connected, received=${msgs.length}');
  } catch (e) {
    stdout.writeln('[FAIL] $label => $e');
  }
}

Future<Map?> _req(String method, String path,
    {Map? body, String? token, String? roomId}) async {
  final client = HttpClient();
  try {
    final req = await client.openUrl(method, Uri.parse('$base$path'));
    req.headers.set('clientid', 'flyroom');
    req.headers.set('Content-Type', 'application/json');
    if (token != null) req.headers.set('Authorization', 'Bearer $token');
    if (roomId != null && roomId.isNotEmpty && roomId != 'null') {
      req.headers.set('X-Room-Id', roomId);
    }
    if (body != null) {
      final bytes = utf8.encode(jsonEncode(body));
      req.headers.contentLength = bytes.length;
      req.add(bytes);
    }
    final res = await req.close().timeout(const Duration(seconds: 20));
    final text = await res.transform(utf8.decoder).join();
    return jsonDecode(text) as Map?;
  } catch (e) {
    stdout.writeln('[ERROR] $method $path => $e');
    return null;
  } finally {
    client.close(force: true);
  }
}
