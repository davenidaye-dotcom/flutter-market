/// Smoke-test script for FlyRoom HTTP APIs (member / agent / owner).
/// Run: dart run scripts/api_smoke_test.dart
/// Optional: dart run scripts/api_smoke_test.dart --base=http://207.148.105.182/api/v1
import 'dart:convert';
import 'dart:io';

const defaultBase = 'http://207.148.105.182/api/v1';
const clientId = 'flyroom';

Future<void> main(List<String> args) async {
  var base = defaultBase;
  for (final a in args) {
    if (a.startsWith('--base=')) base = a.substring(7);
  }

  final results = <String>[];
  void log(String s) {
    results.add(s);
    stdout.writeln(s);
  }

  // Player
  final player = await _login(base, '/auth/member/login', 'player01', 'Pass1234');
  log('PLAYER login: ${player.$1 ? "OK" : "FAIL ${player.$2}"}');
  if (player.$1) {
    final token = player.$3;
    await _hit(log, base, 'GET', '/member/profile', token);
    await _hit(log, base, 'GET', '/member/rooms/verify?roomCode=679010', token);
    final enter = await _hit(log, base, 'POST', '/member/rooms/enter', token,
        body: {'roomCode': '679010'});
    final roomId = enter is Map ? '${enter['roomId'] ?? ''}' : '';
    await _hit(log, base, 'GET', '/member/rooms/history', token);
    await _hit(log, base, 'GET', '/member/rooms/games', token, roomId: roomId);
    await _hit(log, base, 'GET', '/member/rooms/messages?gameType=JS_SC&limit=20', token, roomId: roomId);
    await _hit(log, base, 'GET', '/member/wallet', token, roomId: roomId);
    await _hit(log, base, 'GET', '/member/wallet/adjustments', token, roomId: roomId);
    await _hit(log, base, 'GET', '/member/bets', token, roomId: roomId);
    await _hit(log, base, 'GET', '/member/points/changes', token, roomId: roomId);
    await _hit(log, base, 'GET', '/member/welfare?type=SUMMARY', token, roomId: roomId);
    await _hit(log, base, 'GET', '/member/agent-info', token, roomId: roomId);
    await _hit(log, base, 'GET', '/member/rooms/intro', token, roomId: roomId);
    await _hit(log, base, 'GET', '/member/redpacks?status=ALL', token, roomId: roomId);
    await _hit(log, base, 'GET', '/member/cs/messages?limit=20', token, roomId: roomId);
  }

  // Agent
  final agent = await _login(base, '/auth/portal/login', 'abcd658', 'Pass1234');
  log('AGENT login: ${agent.$1 ? "OK" : "FAIL ${agent.$2}"}');
  if (agent.$1) {
    final token = agent.$3;
    await _hit(log, base, 'GET', '/agent/lottery/info?scene=PROFILE', token);
    await _hit(log, base, 'GET', '/agent/lottery/info?scene=STATS', token);
    await _hit(log, base, 'GET', '/agent/accounts?pageNum=1&pageSize=20', token);
    await _hit(log, base, 'GET', '/agent/reports?startDate=2026-08-11&endDate=2026-08-23', token);
    await _hit(log, base, 'GET', '/agent/credits/changes?pageNum=1&pageSize=20', token);
  }

  // Owner
  final owner = await _login(base, '/auth/portal/login', 'owner01', 'Pass1234');
  log('OWNER login: ${owner.$1 ? "OK" : "FAIL ${owner.$2}"}');
  if (owner.$1) {
    final token = owner.$3;
    await _hit(log, base, 'GET', '/owner/notices', token);
    await _hit(log, base, 'GET', '/owner/games', token);
    await _hit(log, base, 'GET', '/owner/room', token);
    await _hit(log, base, 'GET', '/owner/room/announcement', token);
    await _hit(log, base, 'GET', '/owner/room/members?pageNum=1&pageSize=20', token);
    await _hit(log, base, 'GET', '/owner/room/agents', token);
    await _hit(log, base, 'GET', '/owner/room/odds?gameType=JS_SC', token);
    await _hit(log, base, 'GET', '/owner/room/rebate', token);
    await _hit(log, base, 'GET', '/owner/room/op-logs', token);
    await _hit(log, base, 'GET', '/owner/room/games/settings', token);
    await _hit(log, base, 'GET', '/owner/manage/dashboard', token);
    await _hit(log, base, 'GET', '/owner/manage/applications/up?status=PENDING', token);
    await _hit(log, base, 'GET', '/owner/manage/applications/down?status=PENDING', token);
    await _hit(log, base, 'GET', '/owner/manage/applications/enter?status=PENDING', token);
    await _hit(log, base, 'GET', '/owner/manage/reports/bets', token);
    await _hit(log, base, 'GET', '/owner/manage/welfare?type=SUMMARY', token);
    await _hit(log, base, 'GET', '/owner/manage/credits/records', token);
    await _hit(log, base, 'GET', '/owner/manage/bets', token);
    await _hit(log, base, 'GET', '/owner/manage/redpacks', token);
    await _hit(log, base, 'GET', '/owner/feipan/status', token);
  }

  final fails = results.where((e) => e.contains('FAIL')).length;
  log('DONE fails=$fails');
  exit(fails == 0 ? 0 : 1);
}

Future<(bool, String, String)> _login(
  String base,
  String path,
  String username,
  String password,
) async {
  try {
    final res = await _request(
      'POST',
      Uri.parse('$base$path'),
      headers: {'clientid': clientId, 'Content-Type': 'application/json'},
      body: jsonEncode({
        'username': username,
        'password': password,
        'clientType': 'APP',
      }),
    );
    final map = jsonDecode(res.$2);
    if (map is Map && map['code'] == 200) {
      final data = map['data'];
      final token = data is Map ? '${data['accessToken'] ?? ''}' : '';
      return (token.isNotEmpty, res.$2, token);
    }
    return (false, res.$2, '');
  } catch (e) {
    return (false, '$e', '');
  }
}

Future<dynamic> _hit(
  void Function(String) log,
  String base,
  String method,
  String path,
  String token, {
  String? roomId,
  Map<String, dynamic>? body,
}) async {
  final headers = <String, String>{
    'clientid': clientId,
    'Authorization': 'Bearer $token',
    'Content-Type': 'application/json',
  };
  if (roomId != null && roomId.isNotEmpty) {
    headers['X-Room-Id'] = roomId;
  }
  try {
    final res = await _request(
      method,
      Uri.parse('$base$path'),
      headers: headers,
      body: body == null ? null : jsonEncode(body),
    );
    final map = jsonDecode(res.$2);
    final ok = map is Map && map['code'] == 200;
    log('${ok ? "OK" : "FAIL"} $method $path  status=${res.$1} body=${_short(res.$2)}');
    if (ok && map is Map) return map['data'];
  } catch (e) {
    log('FAIL $method $path  $e');
  }
  return null;
}

Future<(int, String)> _request(
  String method,
  Uri uri, {
  required Map<String, String> headers,
  String? body,
}) async {
  final client = HttpClient();
  try {
    final req = await client.openUrl(method, uri);
    headers.forEach(req.headers.set);
    if (body != null) req.write(body);
    final res = await req.close().timeout(const Duration(seconds: 20));
    final text = await res.transform(utf8.decoder).join();
    return (res.statusCode, text);
  } finally {
    client.close(force: true);
  }
}

String _short(String s) {
  final t = s.replaceAll('\n', ' ');
  return t.length > 160 ? '${t.substring(0, 160)}...' : t;
}
