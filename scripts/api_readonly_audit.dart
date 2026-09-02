/// Read-only HTTP + WS audit (login + enter + GET + WS, no mutations).
/// Run: dart run scripts/api_readonly_audit.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

const base = 'http://207.148.105.182/api/v1';
const wsBase = 'ws://207.148.105.182/ws/v1';
const clientId = 'flyroom';
const roomCode = '679010';
const pwd = 'Pass1234';

final mainRows = <Map<String, dynamic>>[];
final missingRows = <Map<String, dynamic>>[];

Future<void> main() async {
  stdout.writeln('=== READONLY AUDIT base=$base ws=$wsBase ===');

  final pToken = await _login('/auth/member/login', 'player01', 'player');
  var roomId = '';
  if (pToken.isNotEmpty) {
    final enter = await _hit(mainRows, 'player', 'POST', '/member/rooms/enter', pToken,
        body: {'roomCode': roomCode});
    if (enter is Map) roomId = '${enter['roomId'] ?? ''}';
  }

  if (pToken.isNotEmpty) {
    await _hit(mainRows, 'player', 'GET', '/member/profile', pToken);
    await _hit(mainRows, 'player', 'GET', '/member/rooms/verify?roomCode=$roomCode', pToken);
    await _hit(mainRows, 'player', 'GET', '/member/rooms/history?limit=20', pToken);
    if (roomId.isNotEmpty) {
      for (final p in [
        '/member/rooms/games',
        '/member/rooms/messages?gameType=JS_SC&limit=20',
        '/member/wallet',
        '/member/wallet/adjustments?pageNum=1&pageSize=20',
        '/member/bets?pageNum=1&pageSize=20',
        '/member/points/changes?pageNum=1&pageSize=20',
        '/member/welfare?type=SUMMARY',
        '/member/agent-info',
        '/member/rooms/intro?gameType=JS_SC',
        '/member/redpacks?status=ALL',
        '/member/cs/messages?limit=20',
      ]) {
        await _hit(mainRows, 'player', 'GET', p, pToken, roomId: roomId);
      }
    }
    await _probeWs(mainRows, 'player', 'member', pToken,
        roomId.isEmpty ? [] : ['room:$roomId:game:JS_SC']);
    // ws-test「试下注」对齐探测
    await _hit(mainRows, 'player', 'POST', '/member/bets', pToken, body: {
      'gameType': 'JS_SC',
      'items': [{'playCode': 'GYH_11', 'amount': 10}],
    });
  }

  final aToken = await _login('/auth/portal/login', 'abcd658', 'agent');
  if (aToken.isNotEmpty) {
    for (final p in [
      '/agent/lottery/info?scene=PROFILE',
      '/agent/lottery/info?scene=STATS',
      '/agent/accounts?pageNum=1&pageSize=20',
      '/agent/reports?startDate=2026-08-11&endDate=2026-08-23',
      '/agent/credits/changes?pageNum=1&pageSize=20&changeType=ALL',
    ]) {
      await _hit(mainRows, 'agent', 'GET', p, aToken);
    }
  }

  final oToken = await _login('/auth/portal/login', 'owner01', 'owner');
  if (oToken.isNotEmpty) {
    for (final p in [
      '/owner/notices',
      '/owner/games',
      '/owner/games/JS_SC/history?date=2026-08-12',
      '/owner/games/JS_SC/messages?limit=20',
      '/owner/room',
      '/owner/room/announcement',
      '/owner/room/members?presence=ALL&pageNum=1&pageSize=20',
      '/owner/room/agents?pageNum=1&pageSize=20',
      '/owner/room/odds?gameType=JS_SC',
      '/owner/room/rebate',
      '/owner/room/op-logs?startDate=2026-08-11&endDate=2026-08-23',
      '/owner/room/games/settings',
      '/owner/manage/dashboard',
      '/owner/manage/applications/up?status=PENDING&pageNum=1&pageSize=20',
      '/owner/manage/applications/down?status=PENDING&pageNum=1&pageSize=20',
      '/owner/manage/applications/enter?status=PENDING&pageNum=1&pageSize=20',
      '/owner/manage/reports/bets?startDate=2026-08-01&endDate=2026-08-23&category=ALL',
      '/owner/manage/welfare?type=SUMMARY&startDate=2026-08-01&endDate=2026-08-23',
      '/owner/manage/credits/records?startDate=2026-08-01&endDate=2026-08-23&pageNum=1&pageSize=20',
      '/owner/manage/bets?startDate=2026-08-01&endDate=2026-08-23&pageNum=1&pageSize=20',
      '/owner/manage/redpacks?pageNum=1&pageSize=20',
      '/owner/feipan/status',
      '/owner/feipan/credit?gameType=JS_SC',
      '/owner/feipan/reports?startDate=2026-08-01&endDate=2026-08-23&category=ALL',
      '/owner/feipan/odds?gameType=JS_SC',
      '/owner/feipan/points/changes?changeType=ALL&pageNum=1&pageSize=20',
      '/owner/feipan/op-logs?startDate=2026-08-11&endDate=2026-08-23',
      '/owner/cs/sessions?pageNum=1&pageSize=20',
      '/owner/room/assistants',
      '/owner/room/rebate/batch-preview?presence=ALL',
    ]) {
      await _hit(mainRows, 'owner', 'GET', p, oToken);
    }
    final ownerRoom = mainRows
        .where((r) => r['path'] == '/owner/room' && r['probe'] == 'OK')
        .toList();
    var ownerRoomId = roomId;
    await _probeWs(mainRows, 'owner', 'owner', oToken, [
      if (ownerRoomId.isNotEmpty) 'room:$ownerRoomId:game:JS_SC',
      if (ownerRoomId.isNotEmpty) 'room:$ownerRoomId:sys',
    ]);
  }

  // Missing APIs (readonly GETs + enter already done)
  if (pToken.isNotEmpty && roomId.isNotEmpty) {
    missingRows.addAll(mainRows.where((r) =>
        r['path'] == '/auth/member/login' || r['path'] == '/member/rooms/enter'));
    for (final p in [
      '/member/wallet/applications/pending',
      '/member/wallet/applications?applyType=ALL&status=ALL&pageNum=1&pageSize=20',
      '/member/rooms/enter-applications/pending?roomCode=$roomCode',
      '/member/games/JS_SC/history?date=2026-08-12&pageNum=1&pageSize=50',
      '/member/games/JS_SC/trends/long-dragon?limit=100',
      '/member/notices',
      '/member/rooms/announcement',
    ]) {
      await _hit(missingRows, 'player', 'GET', p, pToken, roomId: roomId);
    }
    await _probeWs(missingRows, 'player', 'member', pToken, ['room:$roomId:game:JS_SC']);
  }
  if (oToken.isNotEmpty) {
    missingRows.add({
      'role': 'owner',
      'method': 'POST',
      'path': '/auth/portal/login',
      'clientWired': 'YES',
      'probe': 'OK',
      'bizCode': 200,
      'message': '操作成功',
    });
    for (final p in [
      '/owner/cs/sessions?pageNum=1&pageSize=20',
      '/owner/room/assistants',
      '/owner/room/rebate/batch-preview?presence=ALL',
      '/owner/room',
    ]) {
      await _hit(missingRows, 'owner', 'GET', p, oToken);
    }
    await _probeWs(missingRows, 'owner', 'owner', oToken, [
      if (roomId.isNotEmpty) 'room:$roomId:game:JS_SC',
      if (roomId.isNotEmpty) 'room:$roomId:sys',
    ]);
  }

  await _write('scripts/_api_audit/last_probe.json', {
    'generatedAt': DateTime.now().toIso8601String(),
    'mode': 'READONLY_AUDIT',
    'base': base,
    'wsBase': wsBase,
    'accounts': {'player': 'player01', 'agent': 'abcd658', 'owner': 'owner01', 'roomCode': roomCode},
    'playerRoomId': roomId,
    'summary': _summary(mainRows),
    'rows': mainRows,
  });
  await _write('scripts/_api_audit/last_missing_probe.json', {
    'generatedAt': DateTime.now().toIso8601String(),
    'mode': 'READONLY_MISSING',
    'base': base,
    'wsBase': wsBase,
    'roomCode': roomCode,
    'playerRoomId': roomId,
    'summary': _summary(missingRows),
    'rows': missingRows,
  });

  stdout.writeln('main: ${jsonEncode(_summary(mainRows))}');
  stdout.writeln('missing: ${jsonEncode(_summary(missingRows))}');
}

Map<String, dynamic> _summary(List<Map<String, dynamic>> rows) => {
      'total': rows.length,
      'ok': rows.where((e) => e['probe'] == 'OK').length,
      'fail': rows.where((e) => e['probe'] == 'FAIL').length,
      'error': rows.where((e) => e['probe'] == 'ERROR').length,
      'skip': rows.where((e) => '${e['probe']}'.startsWith('SKIP')).length,
    };

Future<void> _write(String path, Map<String, dynamic> data) async {
  final f = File(path);
  await f.parent.create(recursive: true);
  await f.writeAsString(const JsonEncoder.withIndent('  ').convert(data));
  stdout.writeln('Wrote $path');
}

Future<String> _login(String path, String user, String role) async {
  try {
    final res = await _req('POST', '$base$path', headers: {
      'clientid': clientId,
      'Content-Type': 'application/json',
    }, body: jsonEncode({'username': user, 'password': pwd, 'clientType': 'APP'}));
    final map = jsonDecode(res.$2);
    final ok = map is Map && map['code'] == 200;
    final token = ok && map['data'] is Map ? '${map['data']['accessToken'] ?? ''}' : '';
    _rec(mainRows, role, 'POST', path, ok && token.isNotEmpty ? 'OK' : 'FAIL',
        biz: map is Map ? map['code'] : null, msg: '${map is Map ? map['msg'] : res.$2}');
    return token;
  } catch (e) {
    _rec(mainRows, role, 'POST', path, 'ERROR', msg: '$e');
    return '';
  }
}

Future<dynamic> _hit(List<Map<String, dynamic>> out, String role, String method,
    String path, String token,
    {String? roomId, Map<String, dynamic>? body}) async {
  try {
    final res = await _req(method, '$base$path', headers: {
      'clientid': clientId,
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
      if (roomId != null && roomId.isNotEmpty) 'X-Room-Id': roomId,
    }, body: body == null ? null : jsonEncode(body));
    dynamic map;
    try {
      map = jsonDecode(res.$2);
    } catch (_) {
      map = null;
    }
    final biz = map is Map ? map['code'] : null;
    final msg = map is Map ? '${map['msg'] ?? ''}' : res.$2;
    final ok = biz == 200;
    _rec(out, role, method, path, ok ? 'OK' : 'FAIL',
        http: res.$1, biz: biz, msg: msg, body: res.$2);
    stdout.writeln('  [${ok ? 'OK' : 'FAIL'}] $role $method $path biz=$biz $msg');
    if (ok && map is Map) return map['data'];
  } catch (e) {
    _rec(out, role, method, path, 'ERROR', msg: '$e');
    stdout.writeln('  [ERROR] $role $method $path $e');
  }
  return null;
}

Future<void> _probeWs(List<Map<String, dynamic>> out, String role, String path,
    String token, List<String> topics) async {
  if (token.isEmpty) return;
  final uri = '$wsBase/$path?token=$token';
  try {
    final ws = await WebSocket.connect(uri).timeout(const Duration(seconds: 12));
    final received = <String>[];
    final sub = ws.listen((e) => received.add('$e'));
    for (final t in topics) {
      ws.add(jsonEncode({'action': 'SUBSCRIBE', 'topic': t}));
    }
    ws.add(jsonEncode({'action': 'PING'}));
    await Future<void>.delayed(const Duration(seconds: 3));
    await sub.cancel();
    await ws.close();
    _rec(out, role, 'WS', '/ws/v1/$path', 'OK',
        msg: 'connected; topics=${topics.join(",")}; received=${received.length}; sample=${received.isEmpty ? "-" : received.first}');
    stdout.writeln('  [OK] WS $path received=${received.length}');
  } catch (e) {
    _rec(out, role, 'WS', '/ws/v1/$path', 'ERROR', msg: '$e');
    stdout.writeln('  [ERROR] WS $path $e');
  }
}

void _rec(List<Map<String, dynamic>> out, String role, String method, String path,
    String probe,
    {int? http, Object? biz, String? msg, String? body}) {
  out.add({
    'role': role,
    'method': method,
    'path': path,
    'clientWired': 'YES',
    'probe': probe,
    'httpStatus': http,
    'bizCode': biz,
    'message': msg ?? '',
    if (body != null && body.isNotEmpty) 'responseBody': body,
  });
}

Future<(int, String)> _req(String method, String url,
    {required Map<String, String> headers, String? body}) async {
  final client = HttpClient();
  try {
    final req = await client.openUrl(method, Uri.parse(url));
    headers.forEach((k, v) {
      if (k.toLowerCase() == 'content-type') return;
      req.headers.set(k, v);
    });
    if (body != null) {
      final bytes = utf8.encode(body);
      req.headers.set(HttpHeaders.contentTypeHeader, 'application/json; charset=utf-8');
      req.headers.contentLength = bytes.length;
      req.add(bytes);
    }
    final res = await req.close().timeout(const Duration(seconds: 30));
    final text = await res.transform(utf8.decoder).join();
    return (res.statusCode, text);
  } finally {
    client.close(force: true);
  }
}
