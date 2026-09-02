/// Full HTTP + WebSocket audit against FlyRoom test host.
/// Run: dart run scripts/api_full_audit.dart
/// Writes: scripts/_api_audit/last_probe.json
import 'dart:async';
import 'dart:convert';
import 'dart:io';

const defaultBase = 'http://207.148.105.182/api/v1';
const defaultWs = 'ws://207.148.105.182:9080/ws/v1';
const clientId = 'flyroom';

Future<void> main(List<String> args) async {
  var base = defaultBase;
  var wsBase = defaultWs;
  for (final a in args) {
    if (a.startsWith('--base=')) base = a.substring(7);
    if (a.startsWith('--ws=')) wsBase = a.substring(5);
  }

  final rows = <Map<String, dynamic>>[];

  Future<void> add(
    String role,
    String method,
    String path, {
    required String clientWired,
    String? note,
    String? roomId,
    String? token,
    Map<String, dynamic>? body,
    bool destructive = false,
  }) async {
    if (destructive) {
      rows.add({
        'role': role,
        'method': method,
        'path': path,
        'clientWired': clientWired,
        'probe': 'SKIP_MUTATION',
        'httpStatus': null,
        'bizCode': null,
        'message': note ?? 'skipped write/mutation in audit',
      });
      return;
    }
    if (token == null || token.isEmpty) {
      rows.add({
        'role': role,
        'method': method,
        'path': path,
        'clientWired': clientWired,
        'probe': 'SKIP_NO_TOKEN',
        'httpStatus': null,
        'bizCode': null,
        'message': 'login failed; not probed',
      });
      return;
    }
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
      rows.add({
        'role': role,
        'method': method,
        'path': path,
        'clientWired': clientWired,
        'probe': ok ? 'OK' : 'FAIL',
        'httpStatus': res.$1,
        'bizCode': biz,
        'message': _short(msg),
      });
    } catch (e) {
      rows.add({
        'role': role,
        'method': method,
        'path': path,
        'clientWired': clientWired,
        'probe': 'ERROR',
        'httpStatus': null,
        'bizCode': null,
        'message': _short('$e'),
      });
    }
  }

  // ---------- PLAYER ----------
  final player = await _login(base, '/auth/member/login', 'player01', 'Pass1234');
  rows.add({
    'role': 'player',
    'method': 'POST',
    'path': '/auth/member/login',
    'clientWired': 'YES',
    'probe': player.$1 ? 'OK' : 'FAIL',
    'httpStatus': null,
    'bizCode': player.$1 ? 200 : null,
    'message': player.$1 ? 'token ok' : _short(player.$2),
  });
  final pToken = player.$3;
  String roomId = '';

  await add('player', 'GET', '/member/profile',
      clientWired: 'YES', token: pToken);
  await add('player', 'PUT', '/member/profile/nickname',
      clientWired: 'YES',
      token: pToken,
      body: {'nickname': 'player01'},
      note: 'safe idempotent nickname');
  // Actually PUT may mutate - still OK for smoke with same nick
  // Re-do above without destructive flag - already ran

  await add('player', 'GET', '/member/rooms/verify?roomCode=679010',
      clientWired: 'YES', token: pToken);
  // enter
  if (pToken.isNotEmpty) {
    try {
      final res = await _request(
        'POST',
        Uri.parse('$base/member/rooms/enter'),
        headers: {
          'clientid': clientId,
          'Authorization': 'Bearer $pToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'roomCode': '679010'}),
      );
      final map = jsonDecode(res.$2);
      final ok = map is Map && map['code'] == 200;
      final data = ok && map['data'] is Map ? map['data'] as Map : null;
      roomId = '${data?['roomId'] ?? ''}';
      rows.add({
        'role': 'player',
        'method': 'POST',
        'path': '/member/rooms/enter',
        'clientWired': 'YES',
        'probe': ok ? 'OK' : 'FAIL',
        'httpStatus': res.$1,
        'bizCode': map is Map ? map['code'] : null,
        'message': _short('${map is Map ? map['msg'] : res.$2} roomId=$roomId'),
      });
    } catch (e) {
      rows.add({
        'role': 'player',
        'method': 'POST',
        'path': '/member/rooms/enter',
        'clientWired': 'YES',
        'probe': 'ERROR',
        'httpStatus': null,
        'bizCode': null,
        'message': _short('$e'),
      });
    }
  }

  await add('player', 'GET', '/member/rooms/history?limit=20',
      clientWired: 'YES', token: pToken);
  await add('player', 'GET', '/member/rooms/games',
      clientWired: 'YES', token: pToken, roomId: roomId);
  await add('player', 'GET', '/member/rooms/messages?gameType=JS_SC&limit=20',
      clientWired: 'YES', token: pToken, roomId: roomId);
  await add('player', 'GET', '/member/wallet',
      clientWired: 'YES', token: pToken, roomId: roomId);
  await add('player', 'GET', '/member/wallet/adjustments?pageNum=1&pageSize=20',
      clientWired: 'YES', token: pToken, roomId: roomId);
  await add('player', 'GET', '/member/bets?pageNum=1&pageSize=20',
      clientWired: 'YES', token: pToken, roomId: roomId);
  await add('player', 'GET', '/member/points/changes?pageNum=1&pageSize=20',
      clientWired: 'YES', token: pToken, roomId: roomId);
  await add('player', 'GET', '/member/welfare?type=SUMMARY',
      clientWired: 'YES', token: pToken, roomId: roomId);
  await add('player', 'GET', '/member/agent-info',
      clientWired: 'YES', token: pToken, roomId: roomId);
  await add('player', 'GET', '/member/rooms/intro?gameType=JS_SC',
      clientWired: 'YES', token: pToken, roomId: roomId);
  await add('player', 'GET', '/member/redpacks?status=ALL',
      clientWired: 'YES', token: pToken, roomId: roomId);
  await add('player', 'POST', '/member/redpacks/{id}/claim',
      clientWired: 'YES',
      token: pToken,
      roomId: roomId,
      destructive: true,
      note: 'needs real redpackId');
  await add('player', 'GET', '/member/cs/messages?limit=20',
      clientWired: 'YES', token: pToken, roomId: roomId);
  await add('player', 'POST', '/member/cs/messages',
      clientWired: 'YES',
      token: pToken,
      roomId: roomId,
      body: {'content': 'audit-ping'},
      note: 'sends one CS message');
  await add('player', 'POST', '/member/bets',
      clientWired: 'YES',
      token: pToken,
      roomId: roomId,
      destructive: true,
      note: 'real money bet skipped');
  await add('player', 'POST', '/auth/password/change',
      clientWired: 'YES', destructive: true, token: pToken);
  await add('player', 'POST', '/auth/logout',
      clientWired: 'YES', destructive: true, token: pToken);
  await add('player', 'POST', '/auth/member/register',
      clientWired: 'YES', destructive: true, token: pToken);

  // Player WS
  rows.add(await _probeWs(
    role: 'player',
    wsBase: wsBase,
    path: 'member',
    token: pToken,
    topics: roomId.isEmpty
        ? const []
        : ['room:$roomId:game:JS_SC'],
    clientWired: 'YES',
  ));

  // ---------- AGENT ----------
  final agent = await _login(base, '/auth/portal/login', 'abcd658', 'Pass1234');
  rows.add({
    'role': 'agent',
    'method': 'POST',
    'path': '/auth/portal/login',
    'clientWired': 'YES',
    'probe': agent.$1 ? 'OK' : 'FAIL',
    'httpStatus': null,
    'bizCode': agent.$1 ? 200 : null,
    'message': agent.$1 ? 'token ok' : _short(agent.$2),
  });
  final aToken = agent.$3;
  await add('agent', 'GET', '/agent/lottery/info?scene=PROFILE',
      clientWired: 'YES', token: aToken);
  await add('agent', 'GET', '/agent/lottery/info?scene=STATS',
      clientWired: 'YES', token: aToken);
  await add('agent', 'GET', '/agent/accounts?pageNum=1&pageSize=20',
      clientWired: 'YES', token: aToken);
  await add('agent', 'POST', '/agent/accounts',
      clientWired: 'YES', destructive: true, token: aToken);
  await add('agent', 'GET',
      '/agent/reports?startDate=2026-08-11&endDate=2026-08-23',
      clientWired: 'YES',
      token: aToken);
  await add('agent', 'GET',
      '/agent/credits/changes?pageNum=1&pageSize=20&changeType=ALL',
      clientWired: 'YES',
      token: aToken);
  await add('agent', 'POST', '/auth/password/change',
      clientWired: 'YES', destructive: true, token: aToken);
  await add('agent', 'POST', '/auth/logout',
      clientWired: 'YES', destructive: true, token: aToken);
  rows.add({
    'role': 'agent',
    'method': 'WS',
    'path': '/ws/v1/*',
    'clientWired': 'N/A',
    'probe': 'N/A',
    'httpStatus': null,
    'bizCode': null,
    'message': 'docs: agent has no dedicated WS channel',
  });

  // ---------- OWNER ----------
  final owner = await _login(base, '/auth/portal/login', 'owner01', 'Pass1234');
  rows.add({
    'role': 'owner',
    'method': 'POST',
    'path': '/auth/portal/login',
    'clientWired': 'YES',
    'probe': owner.$1 ? 'OK' : 'FAIL',
    'httpStatus': null,
    'bizCode': owner.$1 ? 200 : null,
    'message': owner.$1 ? 'token ok' : _short(owner.$2),
  });
  final oToken = owner.$3;

  final ownerGets = <(String, String)>[
    ('YES', '/owner/notices'),
    ('YES', '/owner/games'),
    ('YES', '/owner/games/JS_SC/history?date=2026-08-12'),
    ('YES', '/owner/games/JS_SC/messages?limit=20'),
    ('YES', '/owner/room'),
    ('YES', '/owner/room/announcement'),
    ('YES', '/owner/room/members?presence=ALL&pageNum=1&pageSize=20'),
    ('YES', '/owner/room/agents?pageNum=1&pageSize=20'),
    ('YES', '/owner/room/odds?gameType=JS_SC'),
    ('YES', '/owner/room/rebate'),
    ('YES', '/owner/room/op-logs?startDate=2026-08-11&endDate=2026-08-23'),
    ('YES', '/owner/room/games/settings'),
    ('YES', '/owner/manage/dashboard'),
    ('YES', '/owner/manage/applications/up?status=PENDING&pageNum=1&pageSize=20'),
    ('YES', '/owner/manage/applications/down?status=PENDING&pageNum=1&pageSize=20'),
    ('YES', '/owner/manage/applications/enter?status=PENDING&pageNum=1&pageSize=20'),
    ('YES', '/owner/manage/reports/bets?startDate=2026-08-01&endDate=2026-08-23&category=ALL'),
    ('YES', '/owner/manage/welfare?type=SUMMARY&startDate=2026-08-01&endDate=2026-08-23'),
    ('YES', '/owner/manage/credits/records?startDate=2026-08-01&endDate=2026-08-23&pageNum=1&pageSize=20'),
    ('YES', '/owner/manage/bets?startDate=2026-08-01&endDate=2026-08-23&pageNum=1&pageSize=20'),
    ('YES', '/owner/manage/redpacks?pageNum=1&pageSize=20'),
    ('YES', '/owner/feipan/status'),
    ('YES', '/owner/feipan/credit?gameType=JS_SC'),
    ('YES', '/owner/feipan/reports?startDate=2026-08-01&endDate=2026-08-23&category=ALL'),
    ('YES', '/owner/feipan/odds?gameType=JS_SC'),
    ('YES', '/owner/feipan/points/changes?changeType=ALL&pageNum=1&pageSize=20'),
    ('YES', '/owner/feipan/op-logs?startDate=2026-08-11&endDate=2026-08-23'),
  ];
  for (final e in ownerGets) {
    await add('owner', 'GET', e.$2, clientWired: e.$1, token: oToken);
  }

  final ownerMutations = <String>[
    'PUT /owner/room/name',
    'PUT /owner/room/announcement',
    'PUT /owner/room/password',
    'PUT /owner/room/members/{accountId}/status',
    'PUT /owner/room/members/{accountId}/rebate',
    'PUT /owner/room/odds',
    'PUT /owner/room/rebate',
    'POST /owner/room/rebate/advance',
    'PUT /owner/room/games/settings',
    'POST /owner/manage/applications/{id}/approve',
    'POST /owner/manage/applications/{id}/reject',
    'POST /owner/manage/welfare/advance',
    'POST /owner/manage/redpacks',
    'POST /owner/feipan/bind',
    'POST /owner/feipan/unbind',
    'PUT /owner/feipan/odds',
  ];
  for (final m in ownerMutations) {
    final parts = m.split(' ');
    await add('owner', parts[0], parts[1],
        clientWired: 'YES', token: oToken, destructive: true);
  }
  await add('owner', 'POST', '/auth/password/change',
      clientWired: 'YES', destructive: true, token: oToken);
  await add('owner', 'POST', '/auth/logout',
      clientWired: 'YES', destructive: true, token: oToken);

  // Owner roomId from /owner/room if possible
  String ownerRoomId = roomId;
  if (oToken.isNotEmpty) {
    try {
      final res = await _request(
        'GET',
        Uri.parse('$base/owner/room'),
        headers: {
          'clientid': clientId,
          'Authorization': 'Bearer $oToken',
        },
      );
      final map = jsonDecode(res.$2);
      if (map is Map && map['code'] == 200 && map['data'] is Map) {
        ownerRoomId = '${map['data']['roomId'] ?? ownerRoomId}';
      }
    } catch (_) {}
  }

  rows.add(await _probeWs(
    role: 'owner',
    wsBase: wsBase,
    path: 'owner',
    token: oToken,
    topics: ownerRoomId.isEmpty
        ? const []
        : ['room:$ownerRoomId:game:JS_SC', 'room:$ownerRoomId:sys'],
    clientWired: 'YES',
  ));

  // Docs missing / UI-only gaps (documented as client notes)
  const gaps = [
    (
      'player',
      'N/A',
      'member credit up/down apply',
      'NO',
      'MISSING_IN_DOCS',
      'chat 上分/下分; no member apply API in member.md'
    ),
    (
      'player',
      'N/A',
      'member draw history HTTP',
      'PARTIAL',
      'MISSING_IN_DOCS',
      'player history uses owner history or local mock'
    ),
    (
      'player',
      'N/A',
      'long dragon',
      'NO',
      'MISSING_IN_DOCS',
      'LongDragonPanel uses mockLongDragonRows'
    ),
    (
      'player',
      'N/A',
      'share app',
      'NO',
      'MISSING_IN_DOCS',
      'profile share toast'
    ),
    (
      'player',
      'N/A',
      'GET member announcements list',
      'NO',
      'MISSING_IN_DOCS',
      'room_repository.getAnnouncements returns mockList'
    ),
    (
      'owner',
      'N/A',
      'owner CS session list/reply',
      'NO',
      'MISSING_IN_DOCS',
      'host_service_page uses HostMock.csSessions'
    ),
    (
      'owner',
      'N/A',
      'assistants / batch rebate',
      'NO',
      'MISSING_IN_DOCS',
      'host_assistants_page / host_batch_rebate_page UI only'
    ),
    (
      'owner',
      'N/A',
      'dedicated atmosphere API',
      'PARTIAL',
      'MISSING_IN_DOCS',
      'reuses PUT /owner/room/games/settings'
    ),
    (
      'common',
      'N/A',
      'Dingxiang captcha verify',
      'PARTIAL',
      'CLIENT_STUB',
      'captcha page uses mock_dx_token'
    ),
  ];
  for (final g in gaps) {
    rows.add({
      'role': g.$1,
      'method': g.$2,
      'path': g.$3,
      'clientWired': g.$4,
      'probe': g.$5,
      'httpStatus': null,
      'bizCode': null,
      'message': g.$6,
    });
  }

  final out = {
    'generatedAt': DateTime.now().toIso8601String(),
    'base': base,
    'wsBase': wsBase,
    'accounts': {
      'player': 'player01',
      'agent': 'abcd658',
      'owner': 'owner01',
      'roomCode': '679010',
      'playerRoomId': roomId,
      'ownerRoomId': ownerRoomId,
    },
    'summary': {
      'total': rows.length,
      'ok': rows.where((e) => e['probe'] == 'OK').length,
      'fail': rows.where((e) => e['probe'] == 'FAIL').length,
      'error': rows.where((e) => e['probe'] == 'ERROR').length,
      'skip': rows
          .where((e) =>
              '${e['probe']}'.startsWith('SKIP') || e['probe'] == 'N/A')
          .length,
      'missing': rows.where((e) => e['probe'] == 'MISSING_IN_DOCS' || e['probe'] == 'CLIENT_STUB').length,
      'wiredYes': rows.where((e) => e['clientWired'] == 'YES').length,
      'wiredNo': rows.where((e) => e['clientWired'] == 'NO').length,
      'wiredPartial': rows.where((e) => e['clientWired'] == 'PARTIAL').length,
    },
    'rows': rows,
  };

  final dir = Directory('scripts/_api_audit');
  if (!dir.existsSync()) dir.createSync(recursive: true);
  final file = File('scripts/_api_audit/last_probe.json');
  await file.writeAsString(const JsonEncoder.withIndent('  ').convert(out));
  stdout.writeln('Wrote ${file.path}');
  stdout.writeln(jsonEncode(out['summary']));
  for (final r in rows) {
    if (r['probe'] == 'FAIL' || r['probe'] == 'ERROR' || r['probe'] == 'OK' && r['method'] == 'WS') {
      stdout.writeln(
          '${r['probe']} ${r['role']} ${r['method']} ${r['path']} biz=${r['bizCode']} ${r['message']}');
    }
  }
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

Future<Map<String, dynamic>> _probeWs({
  required String role,
  required String wsBase,
  required String path,
  required String token,
  required List<String> topics,
  required String clientWired,
}) async {
  final uriPath = '$wsBase/$path?token=$token';
  if (token.isEmpty) {
    return {
      'role': role,
      'method': 'WS',
      'path': '/ws/v1/$path',
      'clientWired': clientWired,
      'probe': 'SKIP_NO_TOKEN',
      'httpStatus': null,
      'bizCode': null,
      'message': 'no token',
    };
  }
  try {
    final client = HttpClient();
    final uri = Uri.parse(uriPath.replaceFirst('ws://', 'http://').replaceFirst('wss://', 'https://'));
    // Use dart:io WebSocket
    final ws = await WebSocket.connect(uriPath).timeout(const Duration(seconds: 8));
    final received = <String>[];
    final sub = ws.listen((e) {
      received.add(_short('$e'));
    });
    for (final t in topics) {
      ws.add(jsonEncode({'action': 'SUBSCRIBE', 'topic': t}));
    }
    ws.add(jsonEncode({'action': 'PING'}));
    await Future<void>.delayed(const Duration(seconds: 3));
    await sub.cancel();
    await ws.close();
    client.close(force: true);
    return {
      'role': role,
      'method': 'WS',
      'path': '/ws/v1/$path',
      'clientWired': clientWired,
      'probe': 'OK',
      'httpStatus': 101,
      'bizCode': 200,
      'message':
          'connected; topics=${topics.join(",")}; received=${received.length} msgs; sample=${received.isEmpty ? "-" : received.first}',
    };
  } catch (e) {
    return {
      'role': role,
      'method': 'WS',
      'path': '/ws/v1/$path',
      'clientWired': clientWired,
      'probe': 'ERROR',
      'httpStatus': null,
      'bizCode': null,
      'message': _short('$e'),
    };
  }
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
  return t.length > 220 ? '${t.substring(0, 220)}...' : t;
}
