import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// 纯 Dart 联调探针：不经过 Flutter test HTTP 拦截，直接登录+WS 采样倒计时。
/// 运行: dart run scripts/lottery_countdown_live_probe.dart
/// 环境变量: LIVE_TEST_USER LIVE_TEST_PASSWORD LIVE_TEST_ROOM_CODE LIVE_TEST_GAME_ID LIVE_TEST_SAMPLE_SECONDS
Future<void> main(List<String> args) async {
  const base = String.fromEnvironment(
    'API_BASE',
    defaultValue: 'http://207.148.105.182/api/v1',
  );
  const wsBase = String.fromEnvironment(
    'WS_BASE',
    defaultValue: 'ws://207.148.105.182/ws/v1',
  );
  final user = Platform.environment['LIVE_TEST_USER'] ?? 'player01';
  final pwd = Platform.environment['LIVE_TEST_PASSWORD'] ?? 'Pass1234';
  final roomCode = Platform.environment['LIVE_TEST_ROOM_CODE'] ?? '679010';
  final gameId = Platform.environment['LIVE_TEST_GAME_ID'] ?? 'JS_SC';
  final sampleSec =
      int.tryParse(Platform.environment['LIVE_TEST_SAMPLE_SECONDS'] ?? '') ?? 20;
  final rolloverEnabled =
      (Platform.environment['LIVE_TEST_ROLLOVER'] ?? '0').toLowerCase() ==
          '1' ||
      (Platform.environment['LIVE_TEST_ROLLOVER'] ?? '').toLowerCase() == 'true';
  final rolloverMaxSec = int.tryParse(
        Platform.environment['LIVE_TEST_ROLLOVER_MAX_SEC'] ?? '',
      ) ??
      (gameId == 'AZXY10' ? 330 : 120);

  stdout.writeln('=== lottery countdown live probe ===');
  stdout.writeln(
    'api=$base ws=$wsBase user=$user room=$roomCode game=$gameId '
    'rollover=$rolloverEnabled',
  );

  final token = await _login(base, user, pwd);
  if (token.isEmpty) {
    stderr.writeln('LOGIN FAILED');
    exit(1);
  }

  final enter = await _enterRoom(base, token, roomCode);
  final roomId = enter['roomId']?.toString() ?? '';
  if (roomId.isEmpty) {
    stderr.writeln('ENTER ROOM FAILED: $enter');
    exit(1);
  }
  stdout.writeln('roomId=$roomId');

  final httpGames = await _getGames(base, token, roomId);
  final httpGame = httpGames.cast<Map?>().firstWhere(
        (g) => g?['gameType'] == gameId,
        orElse: () => httpGames.isNotEmpty ? httpGames.first : null,
      );
  if (httpGame == null) {
    stderr.writeln('NO GAMES');
    exit(1);
  }
  final httpCd = _toInt(httpGame['countdownSeconds']);
  final httpOpenAt = _toInt(httpGame['openAtEpochMs']);
  final httpIssue = httpGame['latestIssueNo']?.toString() ?? '';
  stdout.writeln(
    'HTTP snapshot: issue=$httpIssue countdown=$httpCd openAt=$httpOpenAt',
  );

  final uri = '$wsBase/member?token=$token';
  final ws = await WebSocket.connect(uri).timeout(const Duration(seconds: 15));
  ws.add(jsonEncode({
    'action': 'SUBSCRIBE',
    'topic': 'room:$roomId:game:$gameId',
  }));

  final wsSamples = <int>[];
  var lastWsCd = -1;
  var lastWsIssue = '';
  var lastWsLastIssue = '';
  var violations = 0;
  var httpWsMismatch = 0;
  var rolloverSeen = false;
  String? rolloverFromIssue;
  String? rolloverToIssue;
  String? rolloverLastIssue;

  final sub = ws.listen((raw) {
    Map<String, dynamic>? frame;
    try {
      if (raw is String) {
        frame = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      } else if (raw is Map) {
        frame = Map<String, dynamic>.from(raw);
      }
    } catch (_) {
      return;
    }
    if (frame == null) return;
    final type = (frame['event'] ?? frame['type'] ?? '').toString().toUpperCase();
    if (type != 'PERIOD_TICK' && type != 'PERIOD_SNAPSHOT') return;

    final data = frame['data'];
    if (data is! Map) return;
    final cd = _toInt(data['countdownSeconds']);
    final issue = data['issueNo']?.toString() ?? '';
    final lastIssue = data['lastIssueNo']?.toString() ?? '';

    if (issue.isNotEmpty &&
        lastWsIssue.isNotEmpty &&
        issue != lastWsIssue &&
        lastWsCd >= 0 &&
        lastWsCd <= 15 &&
        cd > LotteryPeriodRules.sealWarnSeconds) {
      rolloverSeen = true;
      rolloverFromIssue = lastWsIssue;
      rolloverToIssue = issue;
      rolloverLastIssue = lastIssue.isNotEmpty ? lastIssue : lastWsLastIssue;
      stdout.writeln(
        'ROLLOVER: $rolloverFromIssue → $issue lastIssue=$rolloverLastIssue '
        'cd $lastWsCd→$cd',
      );
    }

    if (cd > 0) {
      final sameIssue = issue.isNotEmpty && issue == lastWsIssue;
      if (lastWsCd >= 0 && sameIssue && cd > lastWsCd) {
        violations++;
        final wsOpenAt = _toInt(data['openAtEpochMs']);
        stdout.writeln(
          'WS 回跳: $lastWsCd → $cd issue=$issue '
          'openAt=$wsOpenAt type=$type',
        );
      }
      lastWsCd = cd;
      if (issue.isNotEmpty) lastWsIssue = issue;
      if (lastIssue.isNotEmpty) lastWsLastIssue = lastIssue;
      wsSamples.add(cd);
    } else if (issue.isNotEmpty) {
      lastWsIssue = issue;
      if (lastIssue.isNotEmpty) lastWsLastIssue = lastIssue;
    }
  });

  final end = DateTime.now().add(
    Duration(
      seconds: rolloverEnabled
          ? (sampleSec > rolloverMaxSec ? sampleSec : rolloverMaxSec)
          : sampleSec,
    ),
  );
  var lastHttpPoll = DateTime.fromMillisecondsSinceEpoch(0);
  while (DateTime.now().isBefore(end)) {
    if (rolloverEnabled && rolloverSeen) break;
    if (DateTime.now().difference(lastHttpPoll) >= const Duration(seconds: 2)) {
      lastHttpPoll = DateTime.now();
      final games = await _getGames(base, token, roomId);
      final g = games.cast<Map?>().firstWhere(
            (e) => e?['gameType'] == gameId,
            orElse: () => games.isNotEmpty ? games.first : null,
          );
      if (g != null) {
        final hcd = _toInt(g['countdownSeconds']);
        final hIssue = g['latestIssueNo']?.toString() ?? '';
        final hOpenAt = _toInt(g['openAtEpochMs']);
        final wsCd = lastWsCd;
        if (wsCd >= 0 && hIssue.isNotEmpty && lastWsIssue.isNotEmpty && hIssue != lastWsIssue) {
          stdout.writeln(
            '期号分叉: http=$hIssue ws=$lastWsIssue (HTTP 过期未对齐，非单纯倒计时问题)',
          );
        } else if (wsCd >= 0 && (hcd - wsCd).abs() > 3) {
          httpWsMismatch++;
          stdout.writeln(
            'HTTP≠WS: http=$hcd ws=$wsCd issue http=$hIssue ws=$lastWsIssue '
            'httpOpenAt=$hOpenAt',
          );
        }
      }
    }
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }

  await sub.cancel();
  await ws.close();

  stdout.writeln('WS samples (${wsSamples.length}): ${wsSamples.take(20).toList()}...');

  if (wsSamples.isEmpty) {
    stderr.writeln('NO WS PERIOD_TICK received — 检查 WS 连通/订阅');
    exit(2);
  }
  if (violations > 0) {
    stderr.writeln('FAILED: $violations WS countdown jump(s), $httpWsMismatch HTTP≠WS polls');
    exit(3);
  }
  if (httpWsMismatch > 0) {
    stderr.writeln('FAILED: HTTP and WS disagree ($httpWsMismatch polls) — 多实例或旧 jar 仍在跑');
    exit(4);
  }

  stdout.writeln('PASS: no countdown jump in ${sampleSec}s');

  if (rolloverEnabled) {
    stdout.writeln(
      '=== Rollover check (max ${rolloverMaxSec}s, issue consistency) ===',
    );
    if (!rolloverSeen) {
      stderr.writeln(
        'FAILED: no rollover observed in ${rolloverMaxSec}s '
        '(set LIVE_TEST_ROLLOVER_MAX_SEC higher for AZXY10)',
      );
      exit(5);
    }
    final fromK = _issueKey(rolloverFromIssue ?? '');
    final toK = _issueKey(rolloverToIssue ?? '');
    final lastK = _issueKey(rolloverLastIssue ?? '');
    if (fromK <= 0 || toK <= 0) {
      stderr.writeln('FAILED: rollover missing issue numbers');
      exit(6);
    }
    if (toK != fromK + 1) {
      stderr.writeln(
        'FAILED: issue jump not +1: $rolloverFromIssue → $rolloverToIssue',
      );
      exit(7);
    }
    if (lastK > 0 && lastK != fromK && lastK != toK - 1) {
      stderr.writeln(
        'FAILED: lastIssue=$rolloverLastIssue inconsistent with '
        '$rolloverFromIssue→$rolloverToIssue',
      );
      exit(8);
    }
    stdout.writeln(
      'PASS: rollover issue chain ok '
      '($rolloverFromIssue → $rolloverToIssue, last=$rolloverLastIssue)',
    );
  }
}

/// 与 [issueCompareKey] 对齐：长号取后 4 位。
int _issueKey(String issue) {
  final n = int.tryParse(issue.trim());
  if (n == null) return 0;
  return n >= 10000 ? n % 10000 : n;
}

/// 封盘线秒数，与 LotteryPeriodRules.sealWarnSeconds 一致。
abstract final class LotteryPeriodRules {
  static const sealWarnSeconds = 10;
}

Future<String> _login(String base, String user, String pwd) async {
  final client = HttpClient();
  try {
    final req = await client.postUrl(Uri.parse('$base/auth/member/login'));
    req.headers.set('clientid', 'flyroom');
    req.headers.set('Content-Type', 'application/json');
    req.write(jsonEncode({
      'username': user,
      'password': pwd,
      'clientType': 'APP',
    }));
    final res = await req.close();
    final body = await res.transform(utf8.decoder).join();
    final map = jsonDecode(body);
    if (map is Map && map['code'] == 200 && map['data'] is Map) {
      return '${map['data']['accessToken'] ?? ''}';
    }
    stderr.writeln('login body: $body');
  } finally {
    client.close(force: true);
  }
  return '';
}

Future<Map<String, dynamic>> _enterRoom(
  String base,
  String token,
  String roomCode,
) async {
  final client = HttpClient();
  try {
    final req = await client.postUrl(Uri.parse('$base/member/rooms/enter'));
    req.headers.set('clientid', 'flyroom');
    req.headers.set('Authorization', 'Bearer $token');
    req.headers.set('Content-Type', 'application/json');
    req.write(jsonEncode({'roomCode': roomCode}));
    final res = await req.close();
    final body = await res.transform(utf8.decoder).join();
    final map = jsonDecode(body);
    if (map is Map && map['code'] == 200 && map['data'] is Map) {
      return Map<String, dynamic>.from(map['data'] as Map);
    }
    stderr.writeln('enter body: $body');
  } finally {
    client.close(force: true);
  }
  return {};
}

Future<List<dynamic>> _getGames(
  String base,
  String token,
  String roomId,
) async {
  final client = HttpClient();
  try {
    final req = await client.getUrl(
      Uri.parse('$base/member/rooms/games?roomId=$roomId'),
    );
    req.headers.set('clientid', 'flyroom');
    req.headers.set('Authorization', 'Bearer $token');
    final res = await req.close();
    final body = await res.transform(utf8.decoder).join();
    final map = jsonDecode(body);
    if (map is Map && map['code'] == 200 && map['data'] is List) {
      return List<dynamic>.from(map['data'] as List);
    }
    stderr.writeln('games body: $body');
  } finally {
    client.close(force: true);
  }
  return [];
}

int _toInt(dynamic v) =>
    v is int ? v : (v is num ? v.toInt() : int.tryParse('$v') ?? 0);
