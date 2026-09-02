import 'dart:convert';
import 'dart:io';

void main() {
  final j = jsonDecode(File('scripts/_api_audit/last_probe.json').readAsStringSync())
      as Map<String, dynamic>;
  final rows = (j['rows'] as List).cast<Map<String, dynamic>>();
  final summary = j['summary'] as Map;
  final accounts = j['accounts'] as Map;
  final b = StringBuffer();

  String sl(String probe) => switch (probe) {
        'OK' => 'OK',
        'FAIL' => 'FAIL',
        'ERROR' => 'ERROR',
        'SKIP_MUTATION' => 'SKIP_MUTATION',
        'SKIP_NO_TOKEN' => 'SKIP_NO_TOKEN',
        'MISSING_IN_DOCS' => 'MISSING_IN_DOCS',
        'CLIENT_STUB' => 'CLIENT_STUB',
        'N/A' => 'N/A',
        _ => probe,
      };

  String wl(String w) => switch (w) {
        'YES' => 'wired',
        'NO' => 'not_wired',
        'PARTIAL' => 'partial',
        'N/A' => 'n/a',
        _ => w,
      };

  void table(String title, bool Function(Map r) pred) {
    b.writeln('## $title');
    b.writeln();
    b.writeln('| role | method | path | client | probe | bizCode | message |');
    b.writeln('|---|---|---|---|---|---:|---|');
    final list = rows.where(pred).toList();
    if (list.isEmpty) {
      b.writeln('| - | - | - | - | - | - | (empty) |');
    } else {
      for (final r in list) {
        final path = '${r['path']}'.replaceAll('|', '\\|');
        final msg = '${r['message'] ?? ''}'.replaceAll('|', '\\|');
        b.writeln(
            '| ${r['role']} | ${r['method']} | `$path` | ${wl('${r['clientWired']}')} | ${sl('${r['probe']}')} | ${r['bizCode'] ?? '-'} | $msg |');
      }
    }
    b.writeln();
  }

  Map? findRow(String role, String method, String pathPrefix) {
    for (final r in rows) {
      if (r['role'] != role) continue;
      if (method == 'WS') {
        if (r['method'] == 'WS' && '${r['path']}'.contains(pathPrefix)) return r;
        continue;
      }
      if ('${r['method']}' != method) continue;
      final p = '${r['path']}';
      if (p == pathPrefix || p.startsWith(pathPrefix)) return r;
    }
    return null;
  }

  void roleMap(String title, String role, Map<String, String> items) {
    b.writeln('### $title');
    b.writeln();
    b.writeln('| doc API | repo/page | client | probe | message |');
    b.writeln('|---|---|---|---|---|');
    for (final e in items.entries) {
      final method = e.key.split(' ').first;
      var pathKey = e.key.split(' ').last.split('?').first;
      if (method == 'WS') pathKey = pathKey.contains('owner') ? 'owner' : 'member';
      final row = findRow(role, method, pathKey);
      final msg = '${row?['message'] ?? ''}'.replaceAll('|', '\\|');
      b.writeln(
          '| `${e.key}` | ${e.value} | ${wl('${row?['clientWired'] ?? 'YES'}')} | ${sl('${row?['probe'] ?? '-'}')} | $msg |');
    }
    b.writeln();
  }

  b.writeln('# FlyRoom App API / WebSocket Full Audit Report');
  b.writeln();
  b.writeln('- Generated: `${j['generatedAt']}`');
  b.writeln('- HTTP: `${j['base']}`');
  b.writeln('- WS: `${j['wsBase']}`');
  b.writeln(
      '- Accounts: player=`${accounts['player']}` agent=`${accounts['agent']}` owner=`${accounts['owner']}` roomCode=`${accounts['roomCode']}`');
  b.writeln('- Probe: `dart run scripts/api_full_audit.dart` -> `scripts/_api_audit/last_probe.json`');
  b.writeln();
  b.writeln('## 0. Executive summary');
  b.writeln();
  b.writeln('| metric | count | note |');
  b.writeln('|---|---:|---|');
  b.writeln('| total rows | ${summary['total']} | docs APIs + WS + gaps + skipped mutations |');
  b.writeln('| OK | ${summary['ok']} | biz code 200 or WS connected |');
  b.writeln('| FAIL | ${summary['fail']} | HTTP OK but biz != 200 (mostly server 500) |');
  b.writeln('| ERROR | ${summary['error']} | timeout/network (WS this run) |');
  b.writeln('| SKIP / N/A | ${summary['skip']} | mutations not executed / no agent WS |');
  b.writeln('| missing/stub | ${summary['missing']} | UI needs but no dedicated API in docs |');
  b.writeln('| client wired YES | ${summary['wiredYes']} | repository/page calls path |');
  b.writeln('| client NO | ${summary['wiredNo']} | still Mock / toast |');
  b.writeln('| client PARTIAL | ${summary['wiredPartial']} | fallback mock or reused API |');
  b.writeln();
  b.writeln('### Server blockers (this environment)');
  b.writeln();
  b.writeln('1. Player room chain broken: `GET /member/rooms/verify`, `POST /member/rooms/enter`, `GET /member/rooms/history` -> biz **500**.');
  b.writeln('2. Cascading room-context failures: wallet/bets/redpacks/cs/intro -> biz **500** `please enter room first` (because enter failed).');
  b.writeln('3. Almost all `GET /owner/**` -> biz **500**.');
  b.writeln('4. WebSocket `ws://207.148.105.182:9080/ws/v1/{member|owner}` -> **TimeoutException 8s**.');
  b.writeln('5. Agent mostly healthy; only `GET /agent/credits/changes` -> 500.');
  b.writeln();
  b.writeln('### Client wiring verdict');
  b.writeln();
  b.writeln('- Documented HTTP endpoints are largely **wired** (`clientWired=YES`).');
  b.writeln('- Most FAIL/ERROR are **server-side**, not wrong client paths.');
  b.writeln('- Real gaps: credit up/down apply, long-dragon, share-app, owner CS list, assistants, batch rebate, member draw-history HTTP, hall announcements list, Dingxiang captcha.');
  b.writeln();

  table('1. Probe OK (correct + healthy)', (r) => r['probe'] == 'OK');
  table('2. Probe FAIL (wired, server business error)', (r) => r['probe'] == 'FAIL');
  table('3. Probe ERROR (network/timeout)', (r) => r['probe'] == 'ERROR');
  table('4. Mutations skipped (wired, not executed in audit)', (r) => r['probe'] == 'SKIP_MUTATION');
  table('5. Missing in docs / not wired / partial / stub', (r) {
    final p = '${r['probe']}';
    final w = '${r['clientWired']}';
    return p == 'MISSING_IN_DOCS' || p == 'CLIENT_STUB' || w == 'NO' || w == 'PARTIAL';
  });

  b.writeln('## 6. WebSocket detail');
  b.writeln();
  b.writeln('| role | endpoint | client | documented events | this probe |');
  b.writeln('|---|---|---|---|---|');
  b.writeln('| player | `/ws/v1/member?token=` | `FlyroomWsClient` + `roomLotteryLiveProvider` subscribe `room:{roomId}:game:{gameType}` | PERIOD_TICK, SEAL_WARN, SEALED, DRAW_RESULT, CHAT, REDPACK_NOTICE | ERROR timeout 8s |');
  b.writeln('| owner | `/ws/v1/owner?token=` | same, role=owner; also doc topic `room:{id}:sys` | + APPLY_NOTICE | ERROR timeout 8s |');
  b.writeln('| agent | (none) | not implemented | no WS chapter in agent.md | N/A |');
  b.writeln();
  b.writeln('Inbound handled in `_onWsEvent`: PERIOD_TICK / SEAL_WARN / SEALED / DRAW_RESULT. CHAT / REDPACK_NOTICE / APPLY_NOTICE not fully consumed by UI yet.');
  b.writeln();

  b.writeln('## 7. By role: docs <-> client <-> probe');
  b.writeln();
  roleMap('7.1 Player (member)', 'player', {
    'POST /auth/member/login': 'AuthRepository.login',
    'POST /auth/member/register': 'AuthRepository.register',
    'POST /auth/password/change': 'AuthRepository.changePassword',
    'POST /auth/logout': 'AuthRepository.logout',
    'GET /member/profile': 'MemberRepository.getProfile',
    'PUT /member/profile/nickname': 'MemberRepository.updateNickname',
    'GET /member/rooms/verify': 'RoomRepository.verifyRoom',
    'POST /member/rooms/enter': 'RoomRepository.enterRoom / HomePage',
    'GET /member/rooms/history': 'RoomRepository.getHistoryRooms',
    'GET /member/rooms/games': 'LotteryRepository.getGames',
    'GET /member/rooms/messages': 'LotteryRepository.getChatMessages',
    'WS /ws/v1/member': 'FlyroomWsClient + RoomLotteryLive',
    'GET /member/redpacks': 'MemberRepository.getRedpacks',
    'POST /member/redpacks/{id}/claim': 'MemberRepository.claimRedpack',
    'GET /member/cs/messages': 'MemberRepository.getCsMessages',
    'POST /member/cs/messages': 'MemberRepository.sendCsMessage',
    'GET /member/wallet': 'WalletRepository.getSummary',
    'GET /member/wallet/adjustments': 'WalletRepository.getAdjustments',
    'GET /member/welfare': 'WalletRepository.getWelfare',
    'GET /member/bets': 'WalletRepository.getBets',
    'POST /member/bets': 'LotteryRepository.submitBet',
    'GET /member/points/changes': 'WalletRepository.getPointsChanges',
    'GET /member/agent-info': 'MemberRepository.getAgentInfo',
    'GET /member/rooms/intro': 'MemberRepository.getRoomIntro',
  });

  roleMap('7.2 Agent', 'agent', {
    'POST /auth/portal/login': 'AuthRepository.login(portal)',
    'GET /agent/lottery/info': 'AgentRepository PROFILE/STATS + header',
    'GET /agent/accounts': 'AgentRepository.getAccounts',
    'POST /agent/accounts': 'AgentRepository.createAccount',
    'GET /agent/reports': 'AgentRepository.getReports',
    'GET /agent/credits/changes': 'AgentRepository.getCreditChanges',
    'POST /auth/password/change': 'AuthRepository.changePassword',
    'POST /auth/logout': 'AuthRepository.logout',
  });

  b.writeln('### 7.3 Owner');
  b.writeln();
  b.writeln('`OwnerRepository` covers documented GETs/PUTs/POSTs; host pages call them.');
  b.writeln();
  b.writeln('| API family | client | probe |');
  b.writeln('|---|---|---|');
  b.writeln('| `POST /auth/portal/login` | wired | OK |');
  b.writeln('| all probed `GET /owner/**` | wired | FAIL biz=500 |');
  b.writeln('| owner mutations PUT/POST | wired | SKIP_MUTATION |');
  b.writeln('| `WS /ws/v1/owner` | wired | ERROR timeout |');
  b.writeln();

  b.writeln('## 8. UI still Mock / toast gaps');
  b.writeln();
  b.writeln('| location | behavior | docs API? | suggestion |');
  b.writeln('|---|---|---|---|');
  b.writeln('| chat_bet_page credit up/down | toast pending | no member apply API | add member apply or reuse channel |');
  b.writeln('| chat_bet_page long dragon | mockLongDragonRows | no | add long-dragon API |');
  b.writeln('| chat_bet_page history (player) | fallback mockHistoryDraws | member no history; owner has | expose member history |');
  b.writeln('| room_repository.getAnnouncements | AnnouncementModel.mockList | no member notices list | reuse room announcement/intro |');
  b.writeln('| profile_page share app | toast | no | client share SDK only |');
  b.writeln('| host_service_page | HostMock.csSessions | no owner CS list | add owner CS API |');
  b.writeln('| host_assistants / batch_rebate | hardcoded UI | no | add docs or remove entry |');
  b.writeln('| captcha_page | mock_dx_token | Dingxiang external | wire real captcha |');
  b.writeln('| agent_ui balance fallback | AgentMock on fail | PROFILE exists | remove after backend healthy |');
  b.writeln();

  b.writeln('## 9. Full probe table');
  b.writeln();
  b.writeln('| # | role | method | path | client | probe | HTTP | biz | message |');
  b.writeln('|---:|---|---|---|---|---|---:|---:|---|');
  for (var i = 0; i < rows.length; i++) {
    final r = rows[i];
    final path = '${r['path']}'.replaceAll('|', '\\|');
    final msg = '${r['message'] ?? ''}'.replaceAll('|', '\\|');
    b.writeln(
        '| ${i + 1} | ${r['role']} | ${r['method']} | `$path` | ${r['clientWired']} | ${r['probe']} | ${r['httpStatus'] ?? '-'} | ${r['bizCode'] ?? '-'} | $msg |');
  }
  b.writeln();
  b.writeln('## 10. Reproduce');
  b.writeln();
  b.writeln(r'```bash');
  b.writeln('dart run scripts/api_full_audit.dart');
  b.writeln('dart run scripts/gen_audit_md.dart');
  b.writeln(r'```');
  b.writeln();
  b.writeln('Raw JSON: `scripts/_api_audit/last_probe.json`');
  b.writeln();
  b.writeln('---');
  b.writeln();
  b.writeln(
      'Note: `clientWired=YES` means the app already calls the documented path. `probe=FAIL/ERROR` means the current test server did not return healthy data. Re-run after fixing enter + `/owner/**` + WS:9080.');

  // Chinese companion title block at top via UTF-8 file
  final zhHead = StringBuffer()
    ..writeln('# FlyRoom App \u63a5\u53e3 / WebSocket \u5168\u91cf\u5bf9\u63a5\u4e0e\u8054\u8c03\u62a5\u544a\uff08\u8be6\u60c5\u7248\uff09')
    ..writeln()
    ..writeln('> \u4e2d\u6587\u6458\u8981\u89c1\u4e0b\u65b9\u300c0. Executive summary\u300d\u4e0e\u5404\u5206\u7c7b\u8868\u3002\u672c\u6587\u4e3a\u4e2d\u82f1\u53cc\u8bed\u7ed3\u6784\uff1a\u6807\u9898\u4e2d\u6587\uff0c\u8868\u5934\u82f1\u6587\u4ee5\u4fbf\u811a\u672c\u7a33\u5b9a\u751f\u6210\u3002')
    ..writeln()
    ..writeln('## \u4e00\u53e5\u8bdd\u7ed3\u8bba')
    ..writeln()
    ..writeln('- **\u5df2\u5bf9\u63a5\u4e14\u670d\u52a1\u7aef\u6b63\u5e38**\uff1a\u73a9\u5bb6\u767b\u5f55/\u8d44\u6599/\u6635\u79f0\uff1b\u4ee3\u7406\u767b\u5f55\u4e0e\u5927\u90e8\u5206 agent API\uff1b\u623f\u4e3b\u767b\u5f55\u3002')
    ..writeln('- **\u5df2\u5bf9\u63a5\u4f46\u670d\u52a1\u7aef\u62a5\u9519(500)**\uff1a\u73a9\u5bb6\u8fdb\u623f\u94fe\u53ca\u623f\u95f4\u4e0a\u4e0b\u6587\u63a5\u53e3\uff1b\u5168\u90e8\u63a2\u6d4b\u5230\u7684 `GET /owner/**`\uff1b`GET /agent/credits/changes`\u3002')
    ..writeln('- **WebSocket \u5f02\u5e38**\uff1amember/owner \u5747\u8fde\u63a5\u8d85\u65f6\uff08:9080\uff09\u3002')
    ..writeln('- **\u6587\u6863\u7f3a\u5931/\u672a\u5bf9\u63a5**\uff1a\u4e0a\u4e0b\u5206\u7533\u8bf7\u3001\u957f\u9f99\u3001\u5206\u4eab\u3001\u623f\u4e3b\u5ba2\u670d\u5217\u8868\u3001\u52a9\u624b\u53f7/\u6279\u91cf\u56de\u6c34\u3001\u73a9\u5bb6\u5f00\u5956\u5386\u53f2 HTTP\u3001\u5927\u5385\u516c\u544a\u5217\u8868\u3001\u9876\u8c61\u9a8c\u8bc1\u7801\u3002')
    ..writeln()
    ..writeln('---')
    ..writeln();

  final out = File('scripts/_api_audit/API_WS_FULL_AUDIT.md');
  out.writeAsStringSync(zhHead.toString() + b.toString(), encoding: utf8);
  stdout.writeln('Wrote ${out.path} (${out.lengthSync()} bytes)');
}
