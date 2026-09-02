/// E2E for 21 missing APIs per FlyRoom缺失接口规范.md
/// Run: dart run scripts/api_e2e_missing.dart
///      dart run scripts/api_e2e_missing.dart --base=http://207.148.105.182/api/v1 --ws=ws://207.148.105.182:9080/ws/v1
import 'dart:async';
import 'dart:convert';
import 'dart:io';

const clientId = 'flyroom';
const roomCode = '679010';
const pwd = 'Pass1234';

late String _base;
late String _wsBase;
final rows = <Map<String, dynamic>>[];

Future<void> main(List<String> args) async {
  _base = 'http://207.148.105.182/api/v1';
  _wsBase = 'ws://207.148.105.182/ws/v1';
  for (final a in args) {
    if (a.startsWith('--base=')) _base = a.substring(7);
    if (a.startsWith('--ws=')) _wsBase = a.substring(5);
  }

  stdout.writeln('=== MISSING APIs E2E base=$_base ===');

  final pToken = await _login('/auth/member/login', 'player01', pwd, 'player');
  var roomId = '';
  if (pToken.isNotEmpty) {
    final enter = await _hit('player', 'POST', '/member/rooms/enter', pToken,
        body: {'roomCode': roomCode});
    if (enter is Map) roomId = '${enter['roomId'] ?? ''}';
    stdout.writeln('roomId=$roomId');
  }

  if (pToken.isNotEmpty && roomId.isNotEmpty) {
    final app = await _hit('player', 'POST', '/member/wallet/applications', pToken,
        roomId: roomId,
        body: {'applyType': 'UP', 'amount': 10, 'remark': 'e2e-up'});
    final appId = app is Map ? '${app['applicationId'] ?? ''}' : '';

    await _hit('player', 'GET', '/member/wallet/applications/pending', pToken,
        roomId: roomId);
    await _hit('player', 'GET',
        '/member/wallet/applications?applyType=ALL&status=ALL&pageNum=1&pageSize=20',
        pToken,
        roomId: roomId);
    if (appId.isNotEmpty) {
      await _hit('player', 'POST', '/member/wallet/applications/$appId/cancel',
          pToken,
          roomId: roomId);
    } else {
      _skip('player', 'POST', '/member/wallet/applications/{id}/cancel',
          'no applicationId');
    }

    await _hit('player', 'POST', '/member/rooms/enter-applications', pToken, body: {
      'roomCode': roomCode,
      'remark': 'e2e-enter',
    });
    await _hit('player', 'GET',
        '/member/rooms/enter-applications/pending?roomCode=$roomCode', pToken);

    await _hit('player', 'GET',
        '/member/games/JS_SC/history?date=2026-08-12&pageNum=1&pageSize=50', pToken,
        roomId: roomId);
    await _hit('player', 'GET',
        '/member/games/JS_SC/trends/long-dragon?limit=100', pToken,
        roomId: roomId);
    await _hit('player', 'GET', '/member/notices', pToken, roomId: roomId);
    await _hit('player', 'GET', '/member/rooms/announcement', pToken,
        roomId: roomId);

    await _probeWs('player', 'member', pToken, ['room:$roomId:game:JS_SC']);
  } else {
    _skip('player', 'ALL', 'member missing APIs', 'enter failed or no roomId');
  }

  final oToken = await _login('/auth/portal/login', 'owner01', pwd, 'owner');
  if (oToken.isNotEmpty) {
    final sessions = await _hit('owner', 'GET',
        '/owner/cs/sessions?pageNum=1&pageSize=20', oToken);
    var accountId = '10001';
    if (sessions is Map) {
      final list = sessions['rows'];
      if (list is List && list.isNotEmpty && list.first is Map) {
        final id = '${list.first['accountId'] ?? ''}';
        if (id.isNotEmpty) accountId = id;
      }
    }

    await _hit('owner', 'GET',
        '/owner/cs/sessions/$accountId/messages?limit=20', oToken);
    await _hit('owner', 'POST', '/owner/cs/sessions/$accountId/messages', oToken,
        body: {'content': 'e2e-reply-${DateTime.now().millisecondsSinceEpoch}'});

    final uname = 'e2e_asst_${DateTime.now().millisecondsSinceEpoch % 100000}';
    final created = await _hit('owner', 'POST', '/owner/room/assistants', oToken, body: {
      'username': uname,
      'password': pwd,
      'displayName': 'e2e_assist',
      'permissions': ['CS_REPLY', 'MANAGE_APPLICATION'],
    });
    final newId = created is Map
        ? '${created['delegationId'] ?? created['id'] ?? ''}'
        : '';
    if (newId.isNotEmpty) {
      await _hit('owner', 'PUT', '/owner/room/assistants/$newId', oToken, body: {
        'displayName': 'e2e_assist_updated',
        'status': 'ACTIVE',
        'permissions': ['CS_REPLY'],
      });
      await _hit('owner', 'DELETE', '/owner/room/assistants/$newId', oToken);
    } else {
      _skip('owner', 'PUT/DELETE', '/owner/room/assistants/{id}',
          'create assistant failed');
    }

    final preview = await _hit('owner', 'GET',
        '/owner/room/rebate/batch-preview?presence=ALL', oToken);
    final ids = <int>[];
    if (preview is Map && preview['members'] is List) {
      for (final e in preview['members'] as List) {
        if (e is Map) {
          final id = int.tryParse('${e['accountId'] ?? ''}');
          if (id != null) ids.add(id);
          if (ids.length >= 2) break;
        }
      }
    }
    if (ids.isNotEmpty) {
      await _hit('owner', 'POST', '/owner/room/rebate/batch', oToken, body: {
        'items': [for (final id in ids) {'accountId': id, 'rebateRatio': 1.0}],
      });
      await _hit('owner', 'POST', '/owner/room/rebate/batch-advance', oToken,
          body: {'accountIds': ids, 'remark': 'e2e-batch'});
    } else {
      _skip('owner', 'POST', '/owner/room/rebate/batch*', 'no members');
    }

    final room = await _hit('owner', 'GET', '/owner/room', oToken);
    final ownerRoomId = room is Map ? '${room['roomId'] ?? roomId}' : roomId;
    await _probeWs('owner', 'owner', oToken, [
      if (ownerRoomId.isNotEmpty) 'room:$ownerRoomId:game:JS_SC',
      if (ownerRoomId.isNotEmpty) 'room:$ownerRoomId:sys',
    ]);
  }

  final out = {
    'generatedAt': DateTime.now().toIso8601String(),
    'mode': 'E2E_MISSING_APIS',
    'base': _base,
    'wsBase': _wsBase,
    'roomCode': roomCode,
    'playerRoomId': roomId,
    'summary': {
      'total': rows.length,
      'ok': rows.where((e) => e['probe'] == 'OK').length,
      'fail': rows.where((e) => e['probe'] == 'FAIL').length,
      'error': rows.where((e) => e['probe'] == 'ERROR').length,
      'skip': rows.where((e) => '${e['probe']}'.startsWith('SKIP')).length,
    },
    'rows': rows,
  };

  final file = File('scripts/_api_audit/last_missing_probe.json');
  await file.parent.create(recursive: true);
  await file.writeAsString(const JsonEncoder.withIndent('  ').convert(out));
  stdout.writeln('Wrote ${file.path}');
  stdout.writeln(jsonEncode(out['summary']));
}

Future<String> _login(
  String path,
  String username,
  String password,
  String role,
) async {
  try {
    final res = await _request('POST', Uri.parse('$_base$path'), headers: {
      'clientid': clientId,
      'Content-Type': 'application/json',
    }, body: jsonEncode({
      'username': username,
      'password': password,
      'clientType': 'APP',
    }));
    final map = jsonDecode(res.$2);
    final ok = map is Map && map['code'] == 200;
    final token = ok && map['data'] is Map
        ? '${map['data']['accessToken'] ?? ''}'
        : '';
    _record(role, 'POST', path, ok && token.isNotEmpty ? 'OK' : 'FAIL',
        bizCode: map is Map ? map['code'] : null,
        message: _short('${map is Map ? map['msg'] : res.$2}'));
    return token;
  } catch (e) {
    _record(role, 'POST', path, 'ERROR', message: _short('$e'));
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
    final res = await _request(method, Uri.parse('$_base$path'), headers: {
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
    _record(role, method, path, ok ? 'OK' : 'FAIL',
        httpStatus: res.$1, bizCode: biz, message: _short(msg));
    if (ok && map is Map) return map['data'];
    stdout.writeln(
        '  [${ok ? 'OK' : 'FAIL'}] $role $method $path biz=$biz $msg');
  } catch (e) {
    _record(role, method, path, 'ERROR', message: _short('$e'));
    stdout.writeln('  [ERROR] $role $method $path $e');
  }
  return null;
}

Future<void> _probeWs(
  String role,
  String wsPath,
  String token,
  List<String> topics,
) async {
  if (token.isEmpty) {
    _skip(role, 'WS', '/ws/v1/$wsPath', 'no token');
    return;
  }
  final uri = '$_wsBase/$wsPath?token=$token';
  try {
    final ws = await WebSocket.connect(uri).timeout(const Duration(seconds: 10));
    final received = <String>[];
    final sub = ws.listen((e) => received.add(_short('$e')));
    for (final t in topics) {
      ws.add(jsonEncode({'action': 'SUBSCRIBE', 'topic': t}));
    }
    ws.add(jsonEncode({'action': 'PING'}));
    await Future<void>.delayed(const Duration(seconds: 3));
    await sub.cancel();
    await ws.close();
    _record(role, 'WS', '/ws/v1/$wsPath', 'OK',
        message: 'topics=${topics.join(",")} received=${received.length}');
    stdout.writeln('  [OK] WS $wsPath received=${received.length}');
  } catch (e) {
    _record(role, 'WS', '/ws/v1/$wsPath', 'ERROR', message: _short('$e'));
    stdout.writeln('  [ERROR] WS $wsPath $e');
  }
}

void _skip(String role, String method, String path, String reason) {
  _record(role, method, path, 'SKIP_NO_DATA', message: reason);
  stdout.writeln('  [SKIP] $role $method $path $reason');
}

void _record(
  String role,
  String method,
  String path,
  String probe, {
  int? httpStatus,
  Object? bizCode,
  String? message,
}) {
  rows.add({
    'role': role,
    'method': method,
    'path': path,
    'clientWired': 'YES',
    'probe': probe,
    'httpStatus': httpStatus,
    'bizCode': bizCode,
    'message': message ?? '',
  });
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
  } finally {
    client.close(force: true);
  }
}

String _short(String s) {
  final t = s.replaceAll('\n', ' ');
  return t.length > 200 ? '${t.substring(0, 200)}...' : t;
}
