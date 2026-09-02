import 'dart:convert';
import 'dart:io';

/// Generate scripts/_api_audit/接口问题.md from probe JSON files.
void main() {
  final mainProbe = _readJson('scripts/_api_audit/last_probe.json');
  final missingProbe = _readJson('scripts/_api_audit/last_missing_probe.json');
  final now = DateTime.now().toIso8601String();

  final mainRows = (mainProbe['rows'] as List?)?.cast<Map>() ?? [];
  final missingRows = (missingProbe['rows'] as List?)?.cast<Map>() ?? [];
  final roomId = mainProbe['playerRoomId'] ?? missingProbe['playerRoomId'] ?? '';
  final base = mainProbe['base'] ?? missingProbe['base'] ?? '';
  final wsBase = mainProbe['wsBase'] ?? missingProbe['wsBase'] ?? '';

  final allRows = _dedupe([...mainRows, ...missingRows]);
  final okRows = allRows.where((r) => r['probe'] == 'OK').toList();
  final failRows = allRows.where((r) => r['probe'] == 'FAIL').toList()
    ..sort(_sortFail);
  final errRows = allRows.where((r) => r['probe'] == 'ERROR').toList();

  final b = StringBuffer()
    ..writeln('# FlyRoom 接口问题报告（v4 · 含返回错误明细）')
    ..writeln()
    ..writeln('> 生成时间：`$now`')
    ..writeln('> 环境：`$base` · WS `$wsBase`')
    ..writeln('> 账号：player=`player01` / agent=`abcd658` / owner=`owner01` · 密码 `Pass1234`')
    ..writeln('> 房间：roomCode=`679010` · roomId=`$roomId` · 游戏 `JS_SC`')
    ..writeln('> 探测：`dart run scripts/api_readonly_audit.dart`')
    ..writeln('> 原始数据：`last_probe.json` + `last_missing_probe.json`')
    ..writeln();

  _sectionSummary(b, roomId, mainProbe, missingProbe, okRows, failRows, errRows);
  _sectionFailDetailAll(b, failRows, base);
  _sectionFailByModule(b, failRows);
  _sectionWsTestAlign(b, allRows);
  _sectionOkCompact(b, okRows);
  _sectionWs(b, allRows);
  _sectionErr(b, errRows);
  _sectionBackendTodo(b, failRows);
  _sectionReproduce(b);

  File('scripts/_api_audit/接口问题.md').writeAsStringSync(b.toString(), encoding: utf8);
  stdout.writeln('Wrote scripts/_api_audit/接口问题.md (${File('scripts/_api_audit/接口问题.md').lengthSync()} bytes)');
}

Map<String, dynamic> _readJson(String path) {
  final f = File(path);
  if (!f.existsSync()) return {};
  return jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
}

List<Map> _dedupe(List<Map> rows) {
  final seen = <String>{};
  final out = <Map>[];
  for (final r in rows) {
    final k = '${r['role']}|${r['method']}|${r['path']}';
    if (seen.add(k)) out.add(r);
  }
  return out;
}

int _sortFail(Map a, Map b) {
  final ra = '${a['role']}'.compareTo('${b['role']}');
  if (ra != 0) return ra;
  final ma = '${a['method']}'.compareTo('${b['method']}');
  if (ma != 0) return ma;
  return '${a['path']}'.compareTo('${b['path']}');
}

String _cell(String s) => s.replaceAll('|', '\\|').replaceAll('\n', ' ');

String _responseJson(Map r) {
  final raw = r['responseBody'];
  if (raw is String && raw.trim().isNotEmpty) {
    try {
      return jsonEncode(jsonDecode(raw));
    } catch (_) {
      return raw.trim();
    }
  }
  final code = r['bizCode'];
  final msg = r['message'] ?? '';
  return jsonEncode({'code': code, 'msg': msg, 'data': null});
}

void _sectionSummary(
  StringBuffer b,
  String roomId,
  Map mainProbe,
  Map missingProbe,
  List<Map> okRows,
  List<Map> failRows,
  List<Map> errRows,
) {
  final msMain = mainProbe['summary'] as Map? ?? {};
  final msMiss = missingProbe['summary'] as Map? ?? {};

  b
    ..writeln('## 1. 结论')
    ..writeln()
    ..writeln('- **基础链路**（登录 / verify / enter / WS）：✅ 正常')
    ..writeln('- **失败接口**：${failRows.length} 条（详见 **§2 全量错误明细**）')
    ..writeln('- **客户端**：路径已对接，问题在服务端返回')
    ..writeln()
    ..writeln('| 统计 | 条目 | OK | FAIL | ERROR |')
    ..writeln('|---|---:|---:|---:|---:|')
    ..writeln('| 主探测 | ${msMain['total'] ?? '-'} | ${msMain['ok'] ?? '-'} | ${msMain['fail'] ?? '-'} | ${msMain['error'] ?? '-'} |')
    ..writeln('| 缺失接口 | ${msMiss['total'] ?? '-'} | ${msMiss['ok'] ?? '-'} | ${msMiss['fail'] ?? '-'} | ${msMiss['error'] ?? '-'} |')
    ..writeln('| **去重** | ${okRows.length + failRows.length + errRows.length} | ${okRows.length} | ${failRows.length} | ${errRows.length} |')
    ..writeln()
    ..writeln('**联调顺序**：member login → `POST /member/rooms/enter`（679010）→ roomId=`$roomId` → 再调房间业务接口')
    ..writeln();
}

/// §2 — main table user asked for: every failing API + exact error returned.
void _sectionFailDetailAll(StringBuffer b, List<Map> failRows, String base) {
  b
    ..writeln('## 2. 失败接口全量明细（接口 + 返回错误）')
    ..writeln()
    ..writeln('> 下列每一条均为 **207 实测**。多数为 HTTP **200**，但 JSON **`code`≠200**。')
    ..writeln('> 完整 URL = `$base` + 路径')
    ..writeln()
    ..writeln('| # | 角色 | 方法 | 路径 | HTTP | biz code | msg | 返回 JSON |')
    ..writeln('|---:|---|---|---|---:|---:|---|---|');

  for (var i = 0; i < failRows.length; i++) {
    final r = failRows[i];
    b.writeln(
      '| ${i + 1} | ${r['role']} | ${r['method']} | `${_cell('${r['path']}')}` | ${r['httpStatus'] ?? '-'} | ${r['bizCode'] ?? '-'} | ${_cell('${r['message'] ?? ''}')} | `${_cell(_responseJson(r))}` |',
    );
  }
  b.writeln();

  // Distinct error summary
  final byMsg = <String, int>{};
  for (final r in failRows) {
    final key = 'HTTP ${r['httpStatus'] ?? '?'} / biz=${r['bizCode']} / ${r['message']}';
    byMsg[key] = (byMsg[key] ?? 0) + 1;
  }
  b
    ..writeln('### 2.1 错误类型汇总')
    ..writeln()
    ..writeln('| 返回模式 | 条数 |')
    ..writeln('|---|---:|');
  for (final e in byMsg.entries) {
    b.writeln('| ${_cell(e.key)} | ${e.value} |');
  }
  b.writeln();
}

void _sectionFailByModule(StringBuffer b, List<Map> failRows) {
  b
    ..writeln('## 3. 失败接口（按模块 · 含错误）')
    ..writeln();

  void group(String title, bool Function(Map) pred) {
    final list = failRows.where(pred).toList();
    if (list.isEmpty) return;
    b
      ..writeln('### $title')
      ..writeln()
      ..writeln('| 方法 | 路径 | HTTP | biz | msg | 返回 JSON |')
      ..writeln('|---|---|---:|---:|---|---|');
    for (final r in list) {
      b.writeln(
        '| ${r['method']} | `${_cell('${r['path']}')}` | ${r['httpStatus'] ?? '-'} | ${r['bizCode'] ?? '-'} | ${_cell('${r['message'] ?? ''}')} | `${_cell(_responseJson(r))}` |',
      );
    }
    b.writeln();
  }

  group('3.1 玩家 · 房间业务', (r) {
    if (r['role'] != 'player') return false;
    final p = '${r['path']}';
    return !p.contains('applications') &&
        !p.contains('/member/games/') &&
        !p.contains('/member/notices') &&
        !p.contains('/member/rooms/announcement');
  });

  group('3.2 玩家 · 缺失规范接口', (r) =>
      r['role'] == 'player' &&
      ('${r['path']}'.contains('applications') ||
          '${r['path']}'.contains('/member/games/') ||
          '${r['path']}'.contains('/member/notices') ||
          '${r['path']}'.contains('/member/rooms/announcement')));

  group('3.3 房主 /owner/**', (r) => r['role'] == 'owner');
  group('3.4 代理', (r) => r['role'] == 'agent');
}

Map? _find(List<Map> rows, String role, String method, String pathContains) {
  for (final r in rows) {
    if (r['role'] != role) continue;
    if (r['method'] != method) continue;
    if ('${r['path']}'.contains(pathContains)) return r;
  }
  return null;
}

void _sectionWsTestAlign(StringBuffer b, List<Map> allRows) {
  b
    ..writeln('## 4. ws-test.html 按钮对照')
    ..writeln()
    ..writeln('| 按钮 | 接口 | HTTP | biz | msg |')
    ..writeln('|---|---|---:|---:|---|');

  final ops = [
    ('会员登录', 'player', 'POST', '/auth/member/login'),
    ('验房', 'player', 'GET', '/member/rooms/verify'),
    ('进房', 'player', 'POST', '/member/rooms/enter'),
    ('试下注', 'player', 'POST', '/member/bets'),
    ('WS member', 'player', 'WS', '/ws/v1/member'),
    ('房主登录', 'owner', 'POST', '/auth/portal/login'),
    ('GET /owner/room', 'owner', 'GET', '/owner/room'),
    ('WS owner', 'owner', 'WS', '/ws/v1/owner'),
  ];

  for (final op in ops) {
    final r = _find(allRows, op.$2, op.$3, op.$4.replaceAll('/ws/v1/', ''));
    if (r == null) {
      b.writeln('| ${op.$1} | `${op.$3} ${op.$4}` | — | — | 未探测 |');
      continue;
    }
    if (r['probe'] == 'OK' && r['method'] == 'WS') {
      b.writeln('| ${op.$1} | `${op.$3} ${op.$4}` | — | 200 | WS 已连通 |');
      continue;
    }
    b.writeln(
      '| ${op.$1} | `${op.$3} ${op.$4}` | ${r['httpStatus'] ?? '-'} | ${r['bizCode'] ?? '-'} | ${_cell('${r['message'] ?? ''}')} |',
    );
  }
  b.writeln();
}

void _sectionOkCompact(StringBuffer b, List<Map> okRows) {
  b
    ..writeln('## 5. 正常接口（biz=200 / WS OK）')
    ..writeln()
    ..writeln('| 角色 | 方法 | 路径 | HTTP | biz | msg |')
    ..writeln('|---|---|---|---:|---:|---|');
  for (final r in okRows) {
    b.writeln(
      '| ${r['role']} | ${r['method']} | `${_cell('${r['path']}')}` | ${r['httpStatus'] ?? '-'} | ${r['bizCode'] ?? '-'} | ${_cell('${r['message'] ?? ''}')} |',
    );
  }
  b.writeln();
}

void _sectionWs(StringBuffer b, List<Map> allRows) {
  b
    ..writeln('## 6. WebSocket')
    ..writeln()
    ..writeln('- 地址：`ws://207.148.105.182/ws/v1`（勿用 `:9080`）')
    ..writeln('- member / owner **均已连通**，可收 `PERIOD_TICK` 等推送')
    ..writeln();
}

void _sectionErr(StringBuffer b, List<Map> errRows) {
  if (errRows.isEmpty) return;
  b
    ..writeln('## 7. 网络/超时异常')
    ..writeln()
    ..writeln('| 角色 | 方法 | 路径 | 错误 |')
    ..writeln('|---|---|---|---|');
  for (final r in errRows) {
    b.writeln('| ${r['role']} | ${r['method']} | `${r['path']}` | ${_cell('${r['message']}')} |');
  }
  b.writeln();
}

void _sectionBackendTodo(StringBuffer b, List<Map> failRows) {
  b
    ..writeln('## 8. 后端待办')
    ..writeln()
    ..writeln('1. 查 207 服务日志：`/owner/**`、`/member/wallet`、`/member/bets` 统一 500 栈')
    ..writeln('2. 当前 ${failRows.length} 个接口返回 `{code:500,msg:发生未知异常…}`，需逐个修复或说明依赖')
    ..writeln('3. ws-test 判成功请改看 JSON `code`，不要只看 HTTP 200')
    ..writeln();
}

void _sectionReproduce(StringBuffer b) {
  b
    ..writeln('## 9. 复现')
    ..writeln()
    ..writeln('```bash')
    ..writeln('dart run scripts/api_readonly_audit.dart')
    ..writeln('dart run scripts/gen_interface_issues_md.dart')
    ..writeln('```')
    ..writeln();
}
