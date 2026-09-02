/// Compare ws-test.html flow vs our audit (APP vs WEB clientType).
import 'dart:convert';
import 'dart:io';

const base = 'http://207.148.105.182/api/v1';

Future<void> main() async {
  await playerFlow('APP', '我们的探测脚本');
  await playerFlow('WEB', 'ws-test.html 会员登录');
  await ownerFlow('APP', '我们的 owner 探测');
  await ownerFlow('WEB', 'ws-test.html 房主登录');
}

Future<void> playerFlow(String clientType, String label) async {
  stdout.writeln('\n=== $label (clientType=$clientType) ===');
  final token = await login('/auth/member/login', 'player01', clientType);
  if (token == null) return;
  final enter = await post('/member/rooms/enter', {'roomCode': '679010'}, token);
  final roomId = enter?['data']?['roomId'];
  stdout.writeln('enter roomId=$roomId code=${enter?['code']} msg=${enter?['msg']}');
  for (final p in [
    '/member/rooms/verify?roomCode=679010',
    '/member/wallet',
    '/member/rooms/games',
    '/member/bets?pageNum=1&pageSize=5',
  ]) {
    await getAndPrint(p, token);
  }
  final bet = await post('/member/bets', {
    'gameType': 'JS_SC',
    'items': [{'playCode': 'GYH_11', 'amount': 10}],
  }, token);
  stdout.writeln('POST /member/bets => biz=${bet?['code']} msg=${bet?['msg']}');
}

Future<void> ownerFlow(String clientType, String label) async {
  stdout.writeln('\n=== $label (clientType=$clientType) ===');
  final token = await login('/auth/portal/login', 'owner01', clientType);
  if (token == null) return;
  for (final p in [
    '/owner/room',
    '/owner/games',
    '/owner/notices',
    '/owner/room/members?presence=ALL&pageNum=1&pageSize=5',
  ]) {
    await getAndPrint(p, token);
  }
}

Future<String?> login(String path, String user, String clientType) async {
  final r = await post(path, {
    'username': user,
    'password': 'Pass1234',
    'clientType': clientType,
  });
  stdout.writeln('POST $path => biz=${r?['code']} msg=${r?['msg']}');
  return r?['data']?['accessToken'] as String?;
}

Future<void> getAndPrint(String path, String token) async {
  final r = await get(path, token);
  stdout.writeln('GET $path => biz=${r?['code']} msg=${r?['msg']}');
}

Future<Map?> post(String path, Map body, [String? token]) async {
  return _req('POST', path, body: body, token: token);
}

Future<Map?> get(String path, String token) async {
  return _req('GET', path, token: token);
}

Future<Map?> _req(String method, String path, {Map? body, String? token}) async {
  final client = HttpClient();
  try {
    final req = await client.openUrl(method, Uri.parse('$base$path'));
    req.headers.set('clientid', 'flyroom');
    req.headers.set('Content-Type', 'application/json');
    if (token != null) req.headers.set('Authorization', 'Bearer $token');
    if (body != null) {
      final bytes = utf8.encode(jsonEncode(body));
      req.headers.contentLength = bytes.length;
      req.add(bytes);
    }
    final res = await req.close().timeout(const Duration(seconds: 20));
    final text = await res.transform(utf8.decoder).join();
    return jsonDecode(text) as Map?;
  } catch (e) {
    stdout.writeln('$method $path ERROR: $e');
    return null;
  } finally {
    client.close(force: true);
  }
}
