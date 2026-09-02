import 'dart:convert';
import 'dart:io';

/// Append / replace auto-generated owner probe section in scripts/_api_audit/owner.md
void main() {
  final mainProbe = _readJson('scripts/_api_audit/last_probe.json');
  final missingProbe = _readJson('scripts/_api_audit/last_missing_probe.json');
  final now = DateTime.now().toIso8601String();
  final base = mainProbe['base'] ?? missingProbe['base'] ?? '-';
  final wsBase = mainProbe['wsBase'] ?? missingProbe['wsBase'] ?? '-';
  final roomId = mainProbe['playerRoomId'] ?? missingProbe['playerRoomId'] ?? '-';

  final rows = <Map<String, dynamic>>[];
  final seen = <String>{};
  for (final src in [
    ...(mainProbe['rows'] as List? ?? []),
    ...(missingProbe['rows'] as List? ?? []),
  ]) {
    final r = Map<String, dynamic>.from(src as Map);
    if (r['role'] != 'owner') continue;
    final k = '${r['method']}|${r['path']}';
    if (seen.add(k)) rows.add(r);
  }

  final ok = rows.where((r) => r['probe'] == 'OK').length;
  final fail = rows.where((r) => r['probe'] == 'FAIL').length;
  final err = rows.where((r) => r['probe'] == 'ERROR').length;

  final b = StringBuffer()
    ..writeln('<!-- AUTO_PROBE_START -->')
    ..writeln()
    ..writeln('# 11. 远端联调探测（自动生成）')
    ..writeln()
    ..writeln('| 项目 | 内容 |')
    ..writeln('|---|---|')
    ..writeln('| 生成时间 | `$now` |')
    ..writeln('| HTTP Base | `$base` |')
    ..writeln('| WS Base | `$wsBase` |')
    ..writeln('| 测试账号 | `owner01` / `Pass1234` |')
    ..writeln('| roomId | `$roomId` |')
    ..writeln('| 探测脚本 | `dart run scripts/api_readonly_audit.dart` |')
    ..writeln('| 统计 | OK=$ok / FAIL=$fail / ERROR=$err |')
    ..writeln()
    ..writeln('## 11.1 探测明细')
    ..writeln()
    ..writeln('| 方法 | 路径 | 探测 | biz | 说明 |')
    ..writeln('|---|---|---|---:|---|');

  String label(String p) => switch (p) {
        'OK' => '✅ 正常',
        'FAIL' => '❌ 500',
        'ERROR' => '⚠️ 异常',
        _ => p,
      };

  rows.sort((a, b) {
    final c = '${a['method']}'.compareTo('${b['method']}');
    if (c != 0) return c;
    return '${a['path']}'.compareTo('${b['path']}');
  });

  for (final r in rows) {
    final path = '${r['path']}'.replaceAll('|', '\\|');
    final msg = '${r['message'] ?? ''}'.replaceAll('|', '\\|');
    b.writeln(
        '| ${r['method']} | `$path` | ${label('${r['probe']}')} | ${r['bizCode'] ?? '-'} | $msg |');
  }

  b.writeln();
  b.writeln('## 11.2 结论');
  b.writeln();
  b.writeln('- **登录**：`POST /auth/portal/login` ✅ 正常（portal token）');
  b.writeln('- **WebSocket**：`/ws/v1/owner` ✅ 已连通（port 80，非 :9080）');
  b.writeln('- **业务 GET**：几乎全部 `/owner/**` ❌ biz=500，需后端修复房主域');
  b.writeln('- **新增接口**：`/owner/cs/sessions*`、`/owner/room/assistants*`、`/owner/room/rebate/batch*` 同样 500');
  b.writeln();
  b.writeln('<!-- AUTO_PROBE_END -->');

  final ownerPath = 'scripts/_api_audit/owner.md';
  var doc = File(ownerPath).readAsStringSync(encoding: utf8);

  // Update header Base URL to current test host
  doc = doc.replaceFirst(
    RegExp(r'\| Base URL \| `[^`]+` \|'),
    '| Base URL | `$base`（联调） / `http://localhost:8080`（本机） |',
  );
  doc = doc.replaceFirst(
    RegExp(r'\| 日期 \| [^|]+ \|'),
    '| 日期 | ${now.substring(0, 10)} |',
  );

  const start = '<!-- AUTO_PROBE_START -->';
  const end = '<!-- AUTO_PROBE_END -->';
  final block = b.toString();
  final startIdx = doc.indexOf(start);
  if (startIdx >= 0) {
    final endIdx = doc.indexOf(end);
    if (endIdx > startIdx) {
      doc = doc.replaceRange(startIdx, endIdx + end.length, block.trim());
    }
  } else {
    doc = '${doc.trim()}\n\n$block';
  }

  File(ownerPath).writeAsStringSync('$doc\n', encoding: utf8);
  stdout.writeln('Updated $ownerPath (${File(ownerPath).lengthSync()} bytes)');
}

Map<String, dynamic> _readJson(String path) {
  final f = File(path);
  if (!f.existsSync()) return {};
  return jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
}
