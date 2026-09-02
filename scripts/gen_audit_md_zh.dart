import 'dart:convert';
import 'dart:io';

/// Build Chinese detailed audit MD from last_probe.json
void main() {
  final j = jsonDecode(File('scripts/_api_audit/last_probe.json').readAsStringSync())
      as Map<String, dynamic>;
  final rows = (j['rows'] as List).cast<Map<String, dynamic>>();
  final s = j['summary'] as Map;
  final a = j['accounts'] as Map;
  final b = StringBuffer();

  String probeZh(String p) => switch (p) {
        'OK' => '\u2705 \u6b63\u5e38',
        'FAIL' => '\u274c \u62a5\u9519',
        'ERROR' => '\u26a0\ufe0f \u5f02\u5e38',
        'SKIP_MUTATION' => '\u23ed \u8df3\u8fc7\u5199\u64cd\u4f5c',
        'SKIP_NO_TOKEN' => '\u23ed \u65e0Token',
        'SKIP_NO_DATA' => '\u23ed \u65e0\u53ef\u7528\u6570\u636e',
        'MISSING_IN_DOCS' => '\ud83d\udced \u6587\u6863\u7f3a\u5931',
        'CLIENT_STUB' => '\ud83e\udde9 \u5ba2\u6237\u7aef\u6869',
        'N/A' => '\u2014',
        _ => p,
      };

  String wiredZh(String w) => switch (w) {
        'YES' => '\u5df2\u5bf9\u63a5',
        'NO' => '\u672a\u5bf9\u63a5',
        'PARTIAL' => '\u90e8\u5206\u5bf9\u63a5',
        'N/A' => '\u4e0d\u9002\u7528',
        _ => w,
      };

  void tbl(String title, bool Function(Map r) pred) {
    b.writeln('## $title');
    b.writeln();
    b.writeln(
        '| \u89d2\u8272 | \u65b9\u6cd5 | \u8def\u5f84/\u80fd\u529b | \u5ba2\u6237\u7aef | \u63a2\u6d4b | bizCode | \u8bf4\u660e |');
    b.writeln('|---|---|---|---|---|---:|---|');
    final list = rows.where(pred).toList();
    if (list.isEmpty) {
      b.writeln('| \u2014 | \u2014 | \u2014 | \u2014 | \u2014 | \u2014 | \uff08\u65e0\uff09 |');
    } else {
      for (final r in list) {
        final path = '${r['path']}'.replaceAll('|', '\\|');
        final msg = '${r['message'] ?? ''}'.replaceAll('|', '\\|');
        b.writeln(
            '| ${r['role']} | ${r['method']} | `$path` | ${wiredZh('${r['clientWired']}')} | ${probeZh('${r['probe']}')} | ${r['bizCode'] ?? '-'} | $msg |');
      }
    }
    b.writeln();
  }

  b.writeln(
      '# FlyRoom App \u63a5\u53e3 / WebSocket \u5168\u91cf\u5bf9\u63a5\u4e0e\u8054\u8c03\u62a5\u544a\uff08\u8be6\u60c5\u7248\uff09');
  b.writeln();
  b.writeln('> \u751f\u6210\u65f6\u95f4\uff1a`${j['generatedAt']}`  ');
  b.writeln('> HTTP Base\uff1a`${j['base']}`  ');
  b.writeln('> WS Base\uff1a`${j['wsBase']}`  ');
  b.writeln(
      '> \u6d4b\u8bd5\u8d26\u53f7\uff1aplayer=`${a['player']}` / agent=`${a['agent']}` / owner=`${a['owner']}` / roomCode=`${a['roomCode']}`  ');
  b.writeln(
      '> \u63a2\u6d4b\u547d\u4ee4\uff1a`dart run scripts/api_e2e_flow.dart`\uff08\u542b\u771f\u5b9e\u5199\u64cd\u4f5c\uff09 \u2192 `scripts/_api_audit/last_probe.json`  ');
  b.writeln('> \u6a21\u5f0f\uff1a`${j['mode'] ?? 'PROBE'}`  ');
  b.writeln(
      '> \u539f\u59cb\u6587\u6863\uff1a`scripts/_api_audit/member.md` / `agent.md` / `owner.md`');
  b.writeln();

  b.writeln('## 0. \u7ed3\u8bba\u6458\u8981');
  b.writeln();
  b.writeln('| \u6307\u6807 | \u6570\u91cf | \u8bf4\u660e |');
  b.writeln('|---|---:|---|');
  b.writeln(
      '| \u6761\u76ee\u603b\u8ba1 | ${s['total']} | \u542b\u6587\u6863\u63a5\u53e3\u3001WS\u3001\u6587\u6863\u7f3a\u53e3\u3001\u8df3\u8fc7\u7684\u5199\u64cd\u4f5c |');
  b.writeln(
      '| \u63a2\u6d4b\u6210\u529f OK | ${s['ok']} | \u4e1a\u52a1 code=200 \u6216 WS \u5df2\u8fde\u901a |');
  b.writeln(
      '| \u63a2\u6d4b\u5931\u8d25 FAIL | ${s['fail']} | HTTP \u901a\u4f46\u4e1a\u52a1\u7801\u975e 200\uff08\u591a\u4e3a\u670d\u52a1\u7aef 500\uff09 |');
  b.writeln(
      '| \u63a2\u6d4b\u5f02\u5e38 ERROR | ${s['error']} | \u8d85\u65f6/\u7f51\u7edc\u5f02\u5e38\uff08\u672c\u6b21\u4e3b\u8981\u4e3a WS\uff09 |');
  b.writeln(
      '| \u8df3\u8fc7 SKIP / N/A | ${s['skip']} | \u5199\u64cd\u4f5c\u672a\u5b9e\u6253\u3001Agent \u65e0 WS |');
  b.writeln(
      '| \u6587\u6863/\u4ea7\u54c1\u7f3a\u5931 | ${s['missing']} | \u524d\u7aef\u6709\u5165\u53e3\uff0c\u6587\u6863\u65e0\u72ec\u7acb\u63a5\u53e3 |');
  b.writeln(
      '| \u5ba2\u6237\u7aef\u5df2\u63a5\u7ebf YES | ${s['wiredYes']} | Repository / Provider / \u9875\u9762\u5df2\u8c03\u7528 |');
  b.writeln(
      '| \u5ba2\u6237\u7aef\u672a\u63a5\u7ebf NO | ${s['wiredNo']} | \u4ecd Mock / Toast\u300c\u5f85\u5bf9\u63a5\u300d |');
  b.writeln(
      '| \u5ba2\u6237\u7aef\u90e8\u5206 PARTIAL | ${s['wiredPartial']} | \u6709\u964d\u7ea7 Mock \u6216\u590d\u7528\u5176\u5b83\u63a5\u53e3 |');
  b.writeln();

  b.writeln('### 0.1 \u4e00\u53e5\u8bdd\u5224\u5b9a');
  b.writeln();
  b.writeln(
      '1. **\u5df2\u5bf9\u63a5\u4e14\u670d\u52a1\u7aef\u6b63\u5e38**\uff1a\u73a9\u5bb6\u767b\u5f55\u3001`GET /member/profile`\u3001`PUT /member/profile/nickname`\uff1b\u4ee3\u7406\u767b\u5f55\u53ca PROFILE/STATS/accounts/reports\uff1b\u623f\u4e3b\u767b\u5f55\u3002');
  b.writeln(
      '2. **\u5df2\u5bf9\u63a5\u4f46\u670d\u52a1\u7aef\u62a5\u9519**\uff1a\u73a9\u5bb6\u8fdb\u623f\u94fe\uff08verify/enter/history\uff09\u53ca\u6240\u6709\u4f9d\u8d56\u623f\u95f4\u4e0a\u4e0b\u6587\u7684\u63a5\u53e3\uff1b\u672c\u6b21\u5168\u90e8 `GET /owner/**`\uff1b`GET /agent/credits/changes`\u3002');
  b.writeln(
      '3. **WebSocket \u5f02\u5e38**\uff1a`/ws/v1/member` \u4e0e `/ws/v1/owner` \u5747 **8s \u8fde\u63a5\u8d85\u65f6**\uff08`:9080`\uff09\u3002');
  b.writeln(
      '4. **\u6587\u6863\u7f3a\u5931 / \u672a\u5bf9\u63a5**\uff1a\u4e0a\u4e0b\u5206\u7533\u8bf7\u3001\u957f\u9f99\u3001\u5206\u4eab App\u3001\u623f\u4e3b\u5ba2\u670d\u4f1a\u8bdd\u5217\u8868\u3001\u52a9\u624b\u53f7/\u6279\u91cf\u56de\u6c34\u3001\u73a9\u5bb6\u5f00\u5956\u5386\u53f2 HTTP\u3001\u5927\u5385\u516c\u544a\u5217\u8868\u3001\u9876\u8c61\u9a8c\u8bc1\u7801\u3002');
  b.writeln(
      '5. **\u8def\u5f84\u662f\u5426\u5bf9**\uff1a\u6587\u6863\u5185 HTTP \u7edd\u5927\u591a\u6570\u5df2\u5728 Repository \u6309\u6b63\u786e path \u63a5\u7ebf\uff1b\u5f53\u524d FAIL \u4e3b\u56e0\u662f\u670d\u52a1\u7aef 500\uff0c\u4e0d\u662f\u5ba2\u6237\u7aef\u62fc\u9519 URL\u3002');
  b.writeln();

  b.writeln('### 0.2 \u5173\u952e\u963b\u585e\uff08\u670d\u52a1\u7aef\uff09');
  b.writeln();
  b.writeln(
      '| \u4f18\u5148\u7ea7 | \u95ee\u9898 | \u5f71\u54cd |');
  b.writeln('|---:|---|---|');
  b.writeln(
      '| P0 | `POST /member/rooms/enter` \u53ca verify/history \u8fd4\u56de 500 | \u73a9\u5bb6\u65e0\u6cd5\u8fdb\u623f\uff0c\u623f\u95f4\u5185\u5168\u90e8\u4e1a\u52a1\u94fe\u5d29\u6e83 |');
  b.writeln(
      '| P0 | \u5168\u90e8 `GET /owner/**` \u8fd4\u56de 500 | \u623f\u4e3b\u7aef\u9875\u9762\u65e0\u6cd5\u62c9\u5230\u771f\u5b9e\u6570\u636e |');
  b.writeln(
      '| P0 | WS `:9080` \u8fde\u4e0d\u4e0a | \u671f\u6001/\u5f00\u5956/\u804a\u5929\u63a8\u9001\u5168\u65e0 |');
  b.writeln(
      '| P1 | `GET /agent/credits/changes` 500 | \u4ee3\u7406\u989d\u5ea6\u53d8\u66f4\u9875\u62a5\u9519 |');
  b.writeln();

  tbl('1. \u63a2\u6d4b\u6210\u529f\uff08\u63a5\u53e3\u5bf9\u4e14\u670d\u52a1\u7aef\u6b63\u5e38\uff09',
      (r) => r['probe'] == 'OK');
  tbl('2. \u63a2\u6d4b\u5931\u8d25 FAIL\uff08\u5df2\u5bf9\u63a5\uff0c\u670d\u52a1\u7aef\u4e1a\u52a1\u62a5\u9519\uff09',
      (r) => r['probe'] == 'FAIL');
  tbl('3. \u63a2\u6d4b\u5f02\u5e38 ERROR\uff08\u7f51\u7edc/\u8d85\u65f6\uff09',
      (r) => r['probe'] == 'ERROR');
  tbl('4. \u8df3\u8fc7\uff08\u65e0\u6570\u636e\u53ef\u64cd\u4f5c\uff0c\u975e\u6545\u610f\u4e0d\u8bf7\u6c42\uff09',
      (r) => '${r['probe']}'.startsWith('SKIP'));
  tbl('5. \u6587\u6863\u7f3a\u5931 / \u672a\u5bf9\u63a5 / \u90e8\u5206\u5bf9\u63a5 / \u6869', (r) {
    final p = '${r['probe']}';
    final w = '${r['clientWired']}';
    return p == 'MISSING_IN_DOCS' ||
        p == 'CLIENT_STUB' ||
        w == 'NO' ||
        w == 'PARTIAL';
  });

  b.writeln('## 6. WebSocket \u8be6\u60c5');
  b.writeln();
  b.writeln(
      '| \u89d2\u8272 | \u7aef\u70b9 | \u5ba2\u6237\u7aef\u5b9e\u73b0 | \u6587\u6863 event | \u672c\u6b21\u63a2\u6d4b |');
  b.writeln('|---|---|---|---|---|');
  b.writeln(
      '| player | `ws://{host}/ws/v1/member?token=` | `FlyroomWsClient(member)` + `roomLotteryLiveProvider`\uff1bSUBSCRIBE `room:{roomId}:game:{gameType}` | PERIOD_TICK / SEAL_WARN / SEALED / DRAW_RESULT / CHAT / REDPACK_NOTICE | **ERROR \u8d85\u65f6 8s** |');
  b.writeln(
      '| owner | `ws://{host}/ws/v1/owner?token=` | \u540c\u4e0a role=owner\uff1b\u6587\u6863\u8fd8\u6709 `room:{id}:sys` | \u53e6\u542b APPLY_NOTICE | **ERROR \u8d85\u65f6 8s** |');
  b.writeln(
      '| agent | \uff08\u65e0\uff09 | \u672a\u5b9e\u73b0 | agent.md \u65e0 WS \u7ae0\u8282 | N/A |');
  b.writeln();
  b.writeln(
      '**\u5ba2\u6237\u7aef\u5df2\u5904\u7406\u7684\u5165\u7ad9 event**\uff08`lottery_live_provider._onWsEvent`\uff09\uff1a`PERIOD_TICK` / `SEAL_WARN` / `SEALED` / `DRAW_RESULT`\u3002');
  b.writeln(
      '**\u5c1a\u672a\u5b8c\u6574\u6d88\u8d39**\uff1a`CHAT` / `REDPACK_NOTICE` / `APPLY_NOTICE`\uff08\u901a\u9053\u5df2\u9884\u7559\uff0cUI \u672a\u5168\u91cf\u7ed1\u5b9a\uff09\u3002');
  b.writeln();
  b.writeln('### 6.1 WS \u5bf9\u7167\u6587\u6863\u7684\u5ba2\u6237\u7aef\u884c\u4e3a');
  b.writeln();
  b.writeln('| \u9879 | \u6587\u6863 | App |');
  b.writeln('|---|---|---|');
  b.writeln('| \u8fde\u63a5 URL | `/ws/v1/member` `/ws/v1/owner` | `EnvConfig.wsBaseUrl` + role path |');
  b.writeln('| SUBSCRIBE | `room:{roomId}:game:{gameType}` | \u8fdb\u5385\u540e\u6309\u6e38\u620f\u5217\u8868\u8ba2\u9605 |');
  b.writeln('| owner sys topic | `room:{id}:sys` | **\u672a\u8ba2\u9605**\uff08\u90e8\u5206\u7f3a\u53e3\uff09 |');
  b.writeln('| PING | \u6709 | `FlyroomWsClient.ping()` \u5b58\u5728\uff0c\u672a\u505a\u5b9a\u65f6\u5fc3\u8df3 |');
  b.writeln('| \u91cd\u8fde | \u5efa\u8bae | **\u672a\u5b9e\u73b0\u81ea\u52a8\u91cd\u8fde** |');
  b.writeln();

  b.writeln('## 7. \u6309\u89d2\u8272\uff1a\u6587\u6863 \u2194 \u5ba2\u6237\u7aef \u2194 \u63a2\u6d4b');
  b.writeln();
  b.writeln('### 7.1 \u73a9\u5bb6 member');
  b.writeln();
  b.writeln(
      '| \u6587\u6863\u63a5\u53e3 | \u5ba2\u6237\u7aef\u4f4d\u7f6e | \u5bf9\u63a5 | \u63a2\u6d4b |');
  b.writeln('|---|---|---|---|');

  void line(String api, String where, String role, String method, String prefix) {
    Map? row;
    for (final r in rows) {
      if (r['role'] != role) continue;
      if (method == 'WS') {
        if (r['method'] == 'WS' && '${r['path']}'.contains(prefix)) {
          row = r;
          break;
        }
        continue;
      }
      if ('${r['method']}' != method) continue;
      final p = '${r['path']}';
      if (p == prefix || p.startsWith(prefix)) {
        row = r;
        break;
      }
    }
    final msg = '${row?['message'] ?? ''}'.replaceAll('|', '\\|');
    b.writeln(
        '| `$api` | $where | ${wiredZh('${row?['clientWired'] ?? 'YES'}')} | ${probeZh('${row?['probe'] ?? '-'}')} $msg |');
  }

  line('POST /auth/member/login', 'AuthRepository.login', 'player', 'POST',
      '/auth/member/login');
  line('POST /auth/member/register', 'AuthRepository.register', 'player', 'POST',
      '/auth/member/register');
  line('POST /auth/password/change', 'AuthRepository.changePassword', 'player',
      'POST', '/auth/password/change');
  line('POST /auth/logout', 'AuthRepository.logout', 'player', 'POST',
      '/auth/logout');
  line('GET /member/profile', 'MemberRepository', 'player', 'GET',
      '/member/profile');
  line('PUT /member/profile/nickname', 'MemberRepository / \u4e2a\u4eba\u8bbe\u7f6e',
      'player', 'PUT', '/member/profile/nickname');
  line('GET /member/rooms/verify', 'RoomRepository.verifyRoom', 'player', 'GET',
      '/member/rooms/verify');
  line('POST /member/rooms/enter', 'RoomRepository.enterRoom / HomePage',
      'player', 'POST', '/member/rooms/enter');
  line('GET /member/rooms/history', 'RoomRepository.getHistoryRooms', 'player',
      'GET', '/member/rooms/history');
  line('GET /member/rooms/games', 'LotteryRepository.getGames', 'player', 'GET',
      '/member/rooms/games');
  line('GET /member/rooms/messages', 'LotteryRepository.getChatMessages',
      'player', 'GET', '/member/rooms/messages');
  line('WS /ws/v1/member', 'FlyroomWsClient + RoomLotteryLive', 'player', 'WS',
      'member');
  line('GET /member/redpacks', 'MemberRepository + chat FAB', 'player', 'GET',
      '/member/redpacks');
  line('POST /member/redpacks/{id}/claim', 'MemberRepository.claimRedpack',
      'player', 'POST', '/member/redpacks/');
  line('GET /member/cs/messages', 'customer_service_page', 'player', 'GET',
      '/member/cs/messages');
  line('POST /member/cs/messages', 'customer_service_page', 'player', 'POST',
      '/member/cs/messages');
  line('GET /member/wallet', 'WalletRepository + \u94b1\u5305/\u76f4\u64ad\u9876\u680f',
      'player', 'GET', '/member/wallet');
  line('GET /member/wallet/adjustments', 'apply_records_page', 'player', 'GET',
      '/member/wallet/adjustments');
  line('GET /member/welfare', 'welfare_report_page', 'player', 'GET',
      '/member/welfare');
  line('GET /member/bets', 'bet_records_page', 'player', 'GET', '/member/bets');
  line('POST /member/bets', 'chat_bet / market_bet', 'player', 'POST',
      '/member/bets');
  line('GET /member/points/changes', 'points_change_page', 'player', 'GET',
      '/member/points/changes');
  line('GET /member/agent-info', 'agent_info_page', 'player', 'GET',
      '/member/agent-info');
  line('GET /member/rooms/intro', 'room_intro_page', 'player', 'GET',
      '/member/rooms/intro');
  b.writeln();

  b.writeln('### 7.2 \u4ee3\u7406 agent');
  b.writeln();
  b.writeln(
      '| \u6587\u6863\u63a5\u53e3 | \u5ba2\u6237\u7aef\u4f4d\u7f6e | \u5bf9\u63a5 | \u63a2\u6d4b |');
  b.writeln('|---|---|---|---|');
  line('POST /auth/portal/login', 'AuthRepository.login(portal)', 'agent',
      'POST', '/auth/portal/login');
  line('GET /agent/lottery/info', 'AgentRepository PROFILE/STATS + \u9876\u680f',
      'agent', 'GET', '/agent/lottery/info');
  line('GET /agent/accounts', 'agent_account_manage_page', 'agent', 'GET',
      '/agent/accounts');
  line('POST /agent/accounts', 'agent_account_manage_page', 'agent', 'POST',
      '/agent/accounts');
  line('GET /agent/reports', 'agent_report_query_page', 'agent', 'GET',
      '/agent/reports');
  line('GET /agent/credits/changes', 'agent_quota_change_page', 'agent', 'GET',
      '/agent/credits/changes');
  line('POST /auth/password/change', 'agent_change_password_page', 'agent',
      'POST', '/auth/password/change');
  line('POST /auth/logout', 'agent_ui logout', 'agent', 'POST', '/auth/logout');
  b.writeln();

  b.writeln('### 7.3 \u623f\u4e3b owner');
  b.writeln();
  b.writeln(
      '`OwnerRepository` \u5df2\u8986\u76d6\u6587\u6863\u4e2d\u7684 GET/PUT/POST\uff1b\u5ba1\u6838/\u7ba1\u7406\u4e2d\u5fc3/\u623f\u95f4\u8bbe\u7f6e/\u8d54\u7387\u56de\u6c34/\u62a5\u8868/\u98de\u76d8\u7b49\u9875\u9762\u5df2\u8c03\u7528\u3002');
  b.writeln();
  b.writeln('| \u63a5\u53e3\u65cf | \u5ba2\u6237\u7aef | \u672c\u6b21\u63a2\u6d4b |');
  b.writeln('|---|---|---|');
  b.writeln('| `POST /auth/portal/login` | \u5df2\u5bf9\u63a5 | \u2705 \u6b63\u5e38 |');
  b.writeln(
      '| \u5168\u90e8\u63a2\u6d4b\u5230\u7684 `GET /owner/**` | \u5df2\u5bf9\u63a5 | \u274c \u5168\u90e8 biz=500 |');
  b.writeln(
      '| \u5404\u7c7b PUT/POST \u53d8\u66f4 | \u5df2\u5bf9\u63a5 | \u23ed \u5ba1\u8ba1\u8df3\u8fc7\u5b9e\u6253 |');
  b.writeln('| `WS /ws/v1/owner` | \u5df2\u5bf9\u63a5 | \u26a0\ufe0f \u8fde\u63a5\u8d85\u65f6 |');
  b.writeln();
  b.writeln(
      '\u8be6\u7ec6 GET \u6e05\u5355\u89c1\u7b2c 2 \u8282\u4e0e\u7b2c 9 \u8282\u5168\u8868\u3002');
  b.writeln();

  b.writeln(
      '## 8. UI \u4ecd Mock / Toast\u300c\u5f85\u5bf9\u63a5\u300d\uff08\u4ea7\u54c1/\u6587\u6863\u7f3a\u53e3\uff09');
  b.writeln();
  b.writeln(
      '| \u4f4d\u7f6e | \u73b0\u8c61 | \u6587\u6863\u662f\u5426\u6709\u63a5\u53e3 | \u5efa\u8bae |');
  b.writeln('|---|---|---|---|');
  b.writeln(
      '| `chat_bet_page` \u4e0a\u5206/\u4e0b\u5206 | Toast \u5f85\u5bf9\u63a5 | \u65e0 member \u7533\u8bf7\u63a5\u53e3\uff1b\u4ec5\u6709 owner applications \u5ba1\u6838 | \u8865\u73a9\u5bb6\u7533\u8bf7 API |');
  b.writeln(
      '| `chat_bet_page` \u957f\u9f99 | `mockLongDragonRows` | \u65e0 | \u8865\u957f\u9f99\u7edf\u8ba1\u63a5\u53e3 |');
  b.writeln(
      '| `chat_bet_page` \u5386\u53f2\u5f00\u5956\uff08\u73a9\u5bb6\uff09 | \u5931\u8d25\u56de\u9000 `mockHistoryDraws` | member \u65e0 history\uff1bowner \u6709 | \u7ed9 member \u5f00 history |');
  b.writeln(
      '| `room_repository.getAnnouncements` | \u56fa\u5b9a `AnnouncementModel.mockList` | \u65e0\u72ec\u7acb member notices | \u7528\u623f\u95f4\u516c\u544a/intro \u6216\u65b0\u589e list |');
  b.writeln(
      '| `profile_page` \u5206\u4eab App | Toast | \u65e0 | \u5ba2\u6237\u7aef\u5206\u4eab SDK\uff0c\u53ef\u4e0d\u505a\u540e\u7aef |');
  b.writeln(
      '| `host_service_page` | `HostMock.csSessions` | owner \u65e0 CS \u5217\u8868 | \u8865 owner CS API |');
  b.writeln(
      '| `host_assistants_page` / `host_batch_rebate_page` | \u786c\u7f16\u7801 UI | \u65e0 | \u8865\u6587\u6863\u6216\u4e0b\u7ebf\u5165\u53e3 |');
  b.writeln(
      '| `captcha_page` | `mock_dx_token` | \u9876\u8c61\u4e3a\u5916\u90e8 SDK | \u63a5\u771f\u5b9e\u9a8c\u8bc1\u7801 |');
  b.writeln(
      '| `agent_ui` \u4f59\u989d\u515c\u5e95 | API \u5931\u8d25\u65f6\u7528 `AgentMock.balance` | \u6709 PROFILE | \u540e\u7aef\u7a33\u5b9a\u540e\u53ef\u53bb\u6389\u515c\u5e95 |');
  b.writeln(
      '| owner `room:{id}:sys` WS topic | \u672a SUBSCRIBE | \u6587\u6863\u6709 | \u623f\u4e3b\u8fde WS \u65f6\u8865\u8ba2 |');
  b.writeln();

  b.writeln('## 9. \u5168\u91cf\u660e\u7ec6\u8868\uff08\u672c\u6b21 probe \u539f\u59cb\u7ed3\u679c\uff09');
  b.writeln();
  b.writeln(
      '| # | \u89d2\u8272 | \u65b9\u6cd5 | \u8def\u5f84 | \u5ba2\u6237\u7aef | \u63a2\u6d4b | HTTP | biz | message |');
  b.writeln('|---:|---|---|---|---|---|---:|---:|---|');
  for (var i = 0; i < rows.length; i++) {
    final r = rows[i];
    final path = '${r['path']}'.replaceAll('|', '\\|');
    final msg = '${r['message'] ?? ''}'.replaceAll('|', '\\|');
    b.writeln(
        '| ${i + 1} | ${r['role']} | ${r['method']} | `$path` | ${r['clientWired']} | ${r['probe']} | ${r['httpStatus'] ?? '-'} | ${r['bizCode'] ?? '-'} | $msg |');
  }
  b.writeln();

  b.writeln('## 10. \u5206\u7c7b\u7edf\u8ba1\uff08\u4fbf\u4e8e\u6392\u671f\uff09');
  b.writeln();
  b.writeln('### A. \u5df2\u5bf9\u63a5 + \u670d\u52a1\u7aef\u6b63\u5e38\uff08\u4f18\u5148\u4fdd\u6301\uff09');
  b.writeln();
  for (final r in rows.where((e) => e['probe'] == 'OK')) {
    b.writeln('- `${r['method']} ${r['path']}`');
  }
  b.writeln();
  b.writeln(
      '### B. \u5df2\u5bf9\u63a5 + \u670d\u52a1\u7aef\u62a5\u9519\uff08\u9700\u540e\u7aef\u4fee\uff09');
  b.writeln();
  for (final r in rows.where((e) => e['probe'] == 'FAIL' || e['probe'] == 'ERROR')) {
    b.writeln(
        '- `${r['method']} ${r['path']}` \u2192 ${r['probe']} biz=${r['bizCode'] ?? '-'} ${r['message']}');
  }
  b.writeln();
  b.writeln(
      '### C. \u5df2\u5bf9\u63a5 + \u672a\u5b9e\u6253\u5199\u64cd\u4f5c\uff08\u9700\u529f\u80fd\u6d4b\u8bd5\u8865\u9a8c\uff09');
  b.writeln();
  for (final r in rows.where((e) => e['probe'] == 'SKIP_MUTATION')) {
    b.writeln('- `${r['method']} ${r['path']}`');
  }
  b.writeln();
  b.writeln('### D. \u6587\u6863\u7f3a\u5931 / \u672a\u5bf9\u63a5\uff08\u9700\u4ea7\u54c1\u8865\u63a5\u53e3\u6216\u4e0b\u7ebf\u5165\u53e3\uff09');
  b.writeln();
  for (final r in rows.where((e) {
    final p = '${e['probe']}';
    final w = '${e['clientWired']}';
    return p == 'MISSING_IN_DOCS' ||
        p == 'CLIENT_STUB' ||
        w == 'NO' ||
        w == 'PARTIAL';
  })) {
    b.writeln('- `${r['path']}` \u2192 client=${r['clientWired']} / ${r['message']}');
  }
  b.writeln();

  b.writeln('## 11. \u590d\u73b0\u547d\u4ee4');
  b.writeln();
  b.writeln(r'```bash');
  b.writeln('dart run scripts/api_e2e_flow.dart');
  b.writeln('dart run scripts/gen_audit_md_zh.dart');
  b.writeln(r'```');
  b.writeln();
  b.writeln(
      '\u539f\u59cb JSON\uff1a`scripts/_api_audit/last_probe.json`');
  b.writeln();
  b.writeln('---');
  b.writeln();
  b.writeln(
      '*\u8bf4\u660e\uff1a`clientWired=YES` \u8868\u793a App \u5df2\u6309\u6587\u6863\u8def\u5f84\u8c03\u7528\uff1b`probe=FAIL/ERROR` \u8868\u793a\u5f53\u524d\u6d4b\u8bd5\u73af\u5883\u670d\u52a1\u7aef\u672a\u6b63\u786e\u8fd4\u56de\u3002\u4fee\u590d\u8fdb\u623f + `/owner/**` + WS:9080 \u540e\uff0c\u7528\u540c\u4e00\u811a\u672c\u53ef\u91cd\u65b0\u51fa\u62a5\u544a\u3002*');

  final out = File('scripts/_api_audit/API_WS_FULL_AUDIT.md');
  out.writeAsStringSync(b.toString(), encoding: utf8);
  stdout.writeln('Wrote ${out.path} (${out.lengthSync()} bytes)');
}
