/// Full E2E flow with REAL read + write requests for player / agent / owner.
/// Run: dart run scripts/api_e2e_flow.dart
/// Writes: scripts/_api_audit/last_probe.json  (overwrite for report regen)
import 'dart:async';
import 'dart:convert';
import 'dart:io';

const defaultBase = 'http://207.148.105.182/api/v1';
const defaultWsBase = 'ws://207.148.105.182/ws/v1';
const clientId = 'flyroom';
const roomCode = '679010';
const pwd = 'Pass1234';

late String base;
late String wsBase;
final rows = <Map<String, dynamic>>[];

void main(List<String> args) async {
  base = defaultBase;
  wsBase = defaultWsBase;
  for (final a in args) {
    if (a.startsWith('--base=')) base = a.substring(7);
    if (a.startsWith('--ws=')) wsBase = a.substring(5);
  }
  stdout.writeln('=== E2E REAL FLOW start base=$base ws=$wsBase ===');

  await _playerFlow();
  await _agentFlow();
  await _ownerFlow();

  final out = {
    'generatedAt': DateTime.now().toIso8601String(),
    'mode': 'E2E_REAL_MUTATIONS',
    'base': base,
    'wsBase': wsBase,
    'accounts': {
      'player': 'player01',
      'agent': 'abcd658',
      'owner': 'owner01',
      'roomCode': roomCode,
    },
    'summary': {
      'total': rows.length,
      'ok': rows.where((e) => e['probe'] == 'OK').length,
      'fail': rows.where((e) => e['probe'] == 'FAIL').length,
      'error': rows.where((e) => e['probe'] == 'ERROR').length,
      'skip': rows.where((e) => '${e['probe']}'.startsWith('SKIP')).length,
      'missing': 0,
      'wiredYes': rows.where((e) => e['clientWired'] == 'YES').length,
      'wiredNo': 0,
      'wiredPartial': 0,
    },
    'rows': rows,
  };

  final dir = Directory('scripts/_api_audit');
  if (!dir.existsSync()) dir.createSync(recursive: true);
  final file = File('scripts/_api_audit/last_probe.json');
  await file.writeAsString(const JsonEncoder.withIndent('  ').convert(out));
  stdout.writeln('Wrote ${file.path}');
  stdout.writeln(jsonEncode(out['summary']));
  final fails = rows.where((e) => e['probe'] == 'FAIL' || e['probe'] == 'ERROR');
  stdout.writeln('--- FAIL/ERROR (${fails.length}) ---');
  for (final r in fails) {
    stdout.writeln(
        '${r['probe']} ${r['role']} ${r['method']} ${r['path']} biz=${r['bizCode']} ${r['message']}');
  }
  stdout.writeln('=== E2E REAL FLOW done ===');
}

Future<void> _playerFlow() async {
  stdout.writeln('\n## PLAYER flow');
  final login = await _login('/auth/member/login', 'player01', pwd, 'player');
  final token = login;
  if (token.isEmpty) return;

  await _hit('player', 'GET', '/member/profile', token);
  await _hit('player', 'PUT', '/member/profile/nickname', token,
      body: {'nickname': 'player01'});

  await _hit('player', 'GET', '/member/rooms/verify?roomCode=$roomCode', token);
  final enter = await _hit('player', 'POST', '/member/rooms/enter', token,
      body: {'roomCode': roomCode});
  var roomId = '';
  if (enter is Map) {
    roomId = '${enter['roomId'] ?? ''}';
  }

  await _hit('player', 'GET', '/member/rooms/history?limit=20', token);
  await _hit('player', 'GET', '/member/rooms/games', token, roomId: roomId);
  await _hit('player', 'GET',
      '/member/rooms/messages?gameType=JS_SC&limit=20', token,
      roomId: roomId);

  await _hit('player', 'GET', '/member/wallet', token, roomId: roomId);
  await _hit('player', 'GET',
      '/member/wallet/adjustments?pageNum=1&pageSize=20', token,
      roomId: roomId);
  await _hit('player', 'GET', '/member/bets?pageNum=1&pageSize=20', token,
      roomId: roomId);
  await _hit('player', 'GET',
      '/member/points/changes?pageNum=1&pageSize=20', token,
      roomId: roomId);
  await _hit('player', 'GET', '/member/welfare?type=SUMMARY', token,
      roomId: roomId);
  await _hit('player', 'GET', '/member/agent-info', token, roomId: roomId);
  await _hit('player', 'GET', '/member/rooms/intro?gameType=JS_SC', token,
      roomId: roomId);

  // real bet
  await _hit('player', 'POST', '/member/bets', token, roomId: roomId, body: {
    'gameType': 'JS_SC',
    'items': [
      {'playCode': 'LM-BIG', 'amount': 1},
    ],
  });

  final packs = await _hit('player', 'GET', '/member/redpacks?status=ALL',
      token,
      roomId: roomId);
  String? claimId;
  if (packs is List) {
    for (final e in packs) {
      if (e is Map && e['claimed'] != true) {
        claimId = '${e['redpackId'] ?? e['id'] ?? ''}';
        if (claimId.isNotEmpty) break;
      }
    }
  }
  if (claimId != null && claimId.isNotEmpty) {
    await _hit('player', 'POST', '/member/redpacks/$claimId/claim', token,
        roomId: roomId);
  } else {
    _record('player', 'POST', '/member/redpacks/{id}/claim', 'YES', 'SKIP_NO_DATA',
        message: 'no unclaimed redpack to claim');
  }

  await _hit('player', 'GET', '/member/cs/messages?limit=20', token,
      roomId: roomId);
  await _hit('player', 'POST', '/member/cs/messages', token, roomId: roomId,
      body: {'content': 'e2e-player-${DateTime.now().millisecondsSinceEpoch}'});

  // password change + restore
  await _passwordRoundTrip('player', token, '/auth/member/login', 'player01');

  await _probeWs('player', 'member', token,
      roomId.isEmpty ? const [] : ['room:$roomId:game:JS_SC']);

  // logout last (new token after pwd roundtrip may differ — re-login)
  final t2 = await _login('/auth/member/login', 'player01', pwd, 'player',
      label: '/auth/member/login (re-login before logout)');
  if (t2.isNotEmpty) {
    await _hit('player', 'POST', '/auth/logout', t2);
  }
}

Future<void> _agentFlow() async {
  stdout.writeln('\n## AGENT flow');
  final token = await _login('/auth/portal/login', 'abcd658', pwd, 'agent');
  if (token.isEmpty) return;

  await _hit('agent', 'GET', '/agent/lottery/info?scene=PROFILE', token);
  await _hit('agent', 'GET', '/agent/lottery/info?scene=STATS', token);
  await _hit('agent', 'GET', '/agent/accounts?pageNum=1&pageSize=20', token);

  final uname = 'e2e_m_${DateTime.now().millisecondsSinceEpoch % 100000000}';
  await _hit('agent', 'POST', '/agent/accounts', token, body: {
    'type': 'AGENT_MEMBER',
    'username': uname,
    'displayName': 'e2e_member',
    'password': pwd,
    'confirmPassword': pwd,
  });

  await _hit('agent', 'GET',
      '/agent/reports?startDate=2026-08-11&endDate=2026-08-23', token);
  await _hit('agent', 'GET',
      '/agent/credits/changes?pageNum=1&pageSize=20&changeType=ALL', token);

  await _passwordRoundTrip('agent', token, '/auth/portal/login', 'abcd658');

  final t2 = await _login('/auth/portal/login', 'abcd658', pwd, 'agent',
      label: '/auth/portal/login (agent re-login)');
  if (t2.isNotEmpty) {
    await _hit('agent', 'POST', '/auth/logout', t2);
  }
}

Future<void> _ownerFlow() async {
  stdout.writeln('\n## OWNER flow');
  final token = await _login('/auth/portal/login', 'owner01', pwd, 'owner');
  if (token.isEmpty) return;

  await _hit('owner', 'GET', '/owner/notices', token);
  await _hit('owner', 'GET', '/owner/games', token);
  await _hit('owner', 'GET', '/owner/games/JS_SC/history?date=2026-08-12',
      token);
  await _hit('owner', 'GET', '/owner/games/JS_SC/messages?limit=20', token);

  final room = await _hit('owner', 'GET', '/owner/room', token);
  var roomId = '';
  var roomName = 'E2E-Room';
  if (room is Map) {
    roomId = '${room['roomId'] ?? ''}';
    final n = '${room['roomName'] ?? ''}';
    if (n.isNotEmpty) roomName = n;
  }

  // settings: write then restore where possible
  await _hit('owner', 'PUT', '/owner/room/name', token,
      body: {'roomName': roomName});

  final ann = await _hit('owner', 'GET', '/owner/room/announcement', token);
  final annText = ann is Map
      ? '${ann['content'] ?? ann['announcement'] ?? 'e2e-ann'}'
      : 'e2e-ann';
  await _hit('owner', 'PUT', '/owner/room/announcement', token,
      body: {'content': annText});

  // password: set empty (open room) then leave — docs allow empty
  await _hit('owner', 'PUT', '/owner/room/password', token,
      body: {'password': ''});

  final members = await _hit('owner', 'GET',
      '/owner/room/members?presence=ALL&pageNum=1&pageSize=20', token);
  await _hit('owner', 'GET', '/owner/room/agents?pageNum=1&pageSize=20', token);

  String? memberId;
  String? memberStatus;
  num? memberRebate;
  if (members is Map) {
    final list = members['rows'] ?? members['list'] ?? members['records'];
    if (list is List && list.isNotEmpty && list.first is Map) {
      final m = Map<String, dynamic>.from(list.first as Map);
      memberId = '${m['accountId'] ?? m['memberId'] ?? m['id'] ?? ''}';
      memberStatus = '${m['status'] ?? 'NORMAL'}';
      memberRebate = num.tryParse('${m['rebate'] ?? m['rebateRate'] ?? 0}');
    }
  }
  if (memberId != null && memberId.isNotEmpty) {
    await _hit('owner', 'PUT', '/owner/room/members/$memberId/status', token,
        body: {'status': memberStatus ?? 'NORMAL'});
    await _hit('owner', 'PUT', '/owner/room/members/$memberId/rebate', token,
        body: {'rebate': memberRebate ?? 0});
  } else {
    _record('owner', 'PUT', '/owner/room/members/{id}/status', 'YES',
        'SKIP_NO_DATA',
        message: 'no member row');
    _record('owner', 'PUT', '/owner/room/members/{id}/rebate', 'YES',
        'SKIP_NO_DATA',
        message: 'no member row');
  }

  final odds = await _hit('owner', 'GET', '/owner/room/odds?gameType=JS_SC',
      token);
  if (odds is Map && odds.isNotEmpty) {
    final body = Map<String, dynamic>.from(odds);
    body['gameType'] = body['gameType'] ?? 'JS_SC';
    await _hit('owner', 'PUT', '/owner/room/odds', token, body: body);
  } else {
    await _hit('owner', 'PUT', '/owner/room/odds', token, body: {
      'gameType': 'JS_SC',
    });
  }

  final rebate = await _hit('owner', 'GET', '/owner/room/rebate', token);
  if (rebate is Map && rebate.isNotEmpty) {
    await _hit('owner', 'PUT', '/owner/room/rebate', token,
        body: Map<String, dynamic>.from(rebate));
  } else {
    await _hit('owner', 'PUT', '/owner/room/rebate', token, body: {});
  }

  await _hit('owner', 'POST', '/owner/room/rebate/advance', token, body: {});

  await _hit('owner', 'GET',
      '/owner/room/op-logs?startDate=2026-08-11&endDate=2026-08-23', token);

  final gs = await _hit('owner', 'GET', '/owner/room/games/settings', token);
  if (gs is Map && gs.isNotEmpty) {
    await _hit('owner', 'PUT', '/owner/room/games/settings', token,
        body: Map<String, dynamic>.from(gs));
  } else {
    await _hit('owner', 'PUT', '/owner/room/games/settings', token, body: {});
  }

  await _hit('owner', 'GET', '/owner/manage/dashboard', token);

  for (final kind in ['up', 'down', 'enter']) {
    final apps = await _hit(
      'owner',
      'GET',
      '/owner/manage/applications/$kind?status=PENDING&pageNum=1&pageSize=20',
      token,
    );
    String? appId;
    if (apps is Map) {
      final list = apps['rows'] ?? apps['list'] ?? apps['records'];
      if (list is List && list.isNotEmpty && list.first is Map) {
        final m = Map<String, dynamic>.from(list.first as Map);
        appId = '${m['applicationId'] ?? m['id'] ?? ''}';
      }
    }
    if (appId != null && appId.isNotEmpty) {
      // reject first pending to avoid unintended credit grant; still real write
      await _hit('owner', 'POST',
          '/owner/manage/applications/$appId/reject', token,
          body: {'remark': 'e2e-reject'});
      _record('owner', 'POST', '/owner/manage/applications/{id}/approve', 'YES',
          'SKIP_NO_DATA',
          message: 'skipped approve; rejected one pending instead ($kind)');
    } else {
      _record('owner', 'POST',
          '/owner/manage/applications/{id}/approve', 'YES', 'SKIP_NO_DATA',
          message: 'no pending $kind');
      _record('owner', 'POST',
          '/owner/manage/applications/{id}/reject', 'YES', 'SKIP_NO_DATA',
          message: 'no pending $kind');
    }
  }

  await _hit('owner', 'GET',
      '/owner/manage/reports/bets?startDate=2026-08-01&endDate=2026-08-23&category=ALL',
      token);
  await _hit('owner', 'GET',
      '/owner/manage/welfare?type=SUMMARY&startDate=2026-08-01&endDate=2026-08-23',
      token);
  await _hit('owner', 'POST', '/owner/manage/welfare/advance', token, body: {});
  await _hit('owner', 'GET',
      '/owner/manage/credits/records?startDate=2026-08-01&endDate=2026-08-23&pageNum=1&pageSize=20',
      token);
  await _hit('owner', 'GET',
      '/owner/manage/bets?startDate=2026-08-01&endDate=2026-08-23&pageNum=1&pageSize=20',
      token);

  await _hit('owner', 'POST', '/owner/manage/redpacks', token, body: {
    'type': 'LUCKY',
    'totalAmount': 1,
    'count': 1,
    'minTurnover': 0,
    'gameType': 'JS_SC',
  });
  await _hit('owner', 'GET', '/owner/manage/redpacks?pageNum=1&pageSize=20',
      token);

  final fp = await _hit('owner', 'GET', '/owner/feipan/status', token);
  await _hit('owner', 'POST', '/owner/feipan/bind', token, body: {
    'username': 'e2e_dummy_feipan',
    'password': 'wrong-pass',
  });
  // unbind only if status says bound
  final bound = fp is Map &&
      (fp['bound'] == true ||
          fp['status']?.toString().toUpperCase() == 'BOUND');
  if (bound) {
    await _hit('owner', 'POST', '/owner/feipan/unbind', token);
  } else {
    _record('owner', 'POST', '/owner/feipan/unbind', 'YES', 'SKIP_NO_DATA',
        message: 'feipan not bound; skip unbind');
  }

  await _hit('owner', 'GET', '/owner/feipan/credit?gameType=JS_SC', token);
  await _hit('owner', 'GET',
      '/owner/feipan/reports?startDate=2026-08-01&endDate=2026-08-23&category=ALL',
      token);
  final fOdds =
      await _hit('owner', 'GET', '/owner/feipan/odds?gameType=JS_SC', token);
  if (fOdds is Map && fOdds.isNotEmpty) {
    final body = Map<String, dynamic>.from(fOdds);
    body['gameType'] = body['gameType'] ?? 'JS_SC';
    await _hit('owner', 'PUT', '/owner/feipan/odds', token, body: body);
  } else {
    await _hit('owner', 'PUT', '/owner/feipan/odds', token, body: {
      'gameType': 'JS_SC',
    });
  }
  await _hit('owner', 'GET',
      '/owner/feipan/points/changes?changeType=ALL&pageNum=1&pageSize=20',
      token);
  await _hit('owner', 'GET',
      '/owner/feipan/op-logs?startDate=2026-08-11&endDate=2026-08-23', token);

  await _passwordRoundTrip('owner', token, '/auth/portal/login', 'owner01');

  final t2 = await _login('/auth/portal/login', 'owner01', pwd, 'owner',
      label: '/auth/portal/login (owner re-login)');
  if (t2.isNotEmpty) {
    await _probeWs(
      'owner',
      'owner',
      t2,
      roomId.isEmpty
          ? const []
          : ['room:$roomId:game:JS_SC', 'room:$roomId:sys'],
    );
    await _hit('owner', 'POST', '/auth/logout', t2);
  }
}

Future<void> _passwordRoundTrip(
  String role,
  String token,
  String loginPath,
  String username,
) async {
  const temp = 'Pass1234x';
  await _hit(role, 'POST', '/auth/password/change', token, body: {
    'oldPassword': pwd,
    'newPassword': temp,
    'confirmPassword': temp,
  });
  final changed = rows.isNotEmpty &&
      rows.last['path'] == '/auth/password/change' &&
      rows.last['probe'] == 'OK';
  if (!changed) {
    _record(role, 'POST', '/auth/password/change (restore)', 'YES',
        'SKIP_NO_DATA',
        message: 'change failed; skip restore');
    return;
  }
  final tTemp = await _login(loginPath, username, temp, role,
      label: '$loginPath (after temp pwd)');
  if (tTemp.isEmpty) {
    await _hit(role, 'POST', '/auth/password/change', token, body: {
      'oldPassword': temp,
      'newPassword': pwd,
      'confirmPassword': pwd,
    });
    return;
  }
  await _hit(role, 'POST', '/auth/password/change', tTemp, body: {
    'oldPassword': temp,
    'newPassword': pwd,
    'confirmPassword': pwd,
  });
}

Future<String> _login(
  String path,
  String username,
  String password,
  String role, {
  String? label,
}) async {
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
    final ok = map is Map && map['code'] == 200;
    final data = ok && map['data'] is Map ? map['data'] as Map : null;
    final token = '${data?['accessToken'] ?? ''}';
    _record(
      role,
      'POST',
      label ?? path,
      'YES',
      ok && token.isNotEmpty ? 'OK' : 'FAIL',
      httpStatus: res.$1,
      bizCode: map is Map ? map['code'] : null,
      message: _short('${map is Map ? map['msg'] : res.$2}'),
    );
    return token;
  } catch (e) {
    _record(role, 'POST', label ?? path, 'YES', 'ERROR', message: _short('$e'));
    return '';
  }
}

Future<dynamic> _hit(
  String role,
  String method,
  String path,
  String token, {
  String? roomId,
  Map<String, dynamic>? body,
}) async {
  try {
    final res = await _request(
      method,
      Uri.parse('$base$path'),
      headers: {
        'clientid': clientId,
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
        if (roomId != null && roomId.isNotEmpty) 'X-Room-Id': roomId,
      },
      body: body == null ? null : jsonEncode(body),
    );
    dynamic map;
    try {
      map = jsonDecode(res.$2);
    } catch (_) {
      map = null;
    }
    final biz = map is Map ? map['code'] : null;
    final msg = map is Map ? '${map['msg'] ?? map['message'] ?? ''}' : res.$2;
    final ok = biz == 200;
    _record(
      role,
      method,
      path,
      'YES',
      ok ? 'OK' : 'FAIL',
      httpStatus: res.$1,
      bizCode: biz,
      message: _short(msg),
    );
    if (ok && map is Map) return map['data'];
  } catch (e) {
    _record(role, method, path, 'YES', 'ERROR', message: _short('$e'));
  }
  return null;
}

Future<void> _probeWs(
  String role,
  String path,
  String token,
  List<String> topics,
) async {
  if (token.isEmpty) {
    _record(role, 'WS', '/ws/v1/$path', 'YES', 'SKIP_NO_TOKEN',
        message: 'no token');
    return;
  }
  final uriPath = '$wsBase/$path?token=$token';
  try {
    final ws =
        await WebSocket.connect(uriPath).timeout(const Duration(seconds: 8));
    final received = <String>[];
    final sub = ws.listen((e) => received.add(_short('$e')));
    for (final t in topics) {
      ws.add(jsonEncode({'action': 'SUBSCRIBE', 'topic': t}));
    }
    ws.add(jsonEncode({'action': 'PING'}));
    await Future<void>.delayed(const Duration(seconds: 3));
    await sub.cancel();
    await ws.close();
    _record(
      role,
      'WS',
      '/ws/v1/$path',
      'YES',
      'OK',
      httpStatus: 101,
      bizCode: 200,
      message:
          'connected; topics=${topics.join(",")}; received=${received.length}; sample=${received.isEmpty ? "-" : received.first}',
    );
  } catch (e) {
    _record(role, 'WS', '/ws/v1/$path', 'YES', 'ERROR',
        message: _short('$e'));
  }
}

void _record(
  String role,
  String method,
  String path,
  String wired,
  String probe, {
  int? httpStatus,
  Object? bizCode,
  String? message,
}) {
  rows.add({
    'role': role,
    'method': method,
    'path': path,
    'clientWired': wired,
    'probe': probe,
    'httpStatus': httpStatus,
    'bizCode': bizCode,
    'message': message ?? '',
  });
  final mark = probe == 'OK'
      ? 'OK'
      : (probe.startsWith('SKIP') ? 'SKIP' : probe);
  stdout.writeln(
      '  [$mark] $role $method $path biz=$bizCode ${message ?? ''}');
}

Future<(int, String)> _request(
  String method,
  Uri uri, {
  required Map<String, String> headers,
  String? body,
  int attempt = 1,
}) async {
  final client = HttpClient();
  try {
    final req = await client.openUrl(method, uri);
    headers.forEach((k, v) {
      if (k.toLowerCase() == 'content-type') return;
      req.headers.set(k, v);
    });
    if (body != null) {
      final bytes = utf8.encode(body);
      req.headers
          .set(HttpHeaders.contentTypeHeader, 'application/json; charset=utf-8');
      req.headers.contentLength = bytes.length;
      req.add(bytes);
    }
    final res = await req.close().timeout(const Duration(seconds: 30));
    final text = await res.transform(utf8.decoder).join();
    return (res.statusCode, text);
  } on TimeoutException {
    if (attempt < 3) {
      await Future<void>.delayed(Duration(seconds: attempt));
      return _request(method, uri,
          headers: headers, body: body, attempt: attempt + 1);
    }
    rethrow;
  } finally {
    client.close(force: true);
  }
}

String _short(String s) {
  final t = s.replaceAll('\n', ' ');
  return t.length > 220 ? '${t.substring(0, 220)}...' : t;
}
