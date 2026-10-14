import 'display_number.dart';

/// 注单行名次。特码是冠军位的号码；名次玩法按位显示。
/// 标题末尾若带赔率数字，统一走 [displayNumber] 抹零（最多 4 位）。
String rankBetTitle(Map<dynamic, dynamic> row) {
  final title = '${row['title'] ?? '—'}'.trim();
  final code = '${row['playCode'] ?? ''}'.trim().toUpperCase();
  final odds = _oddsTail(row, title);
  final tail = odds.isEmpty ? '' : ' $odds';

  if (code.startsWith('TM-')) {
    return '冠军 [${code.substring(3)}]$tail';
  }
  if (code.startsWith('POS-')) {
    final parts = code.split('-');
    if (parts.length >= 3) {
      final pos = int.tryParse(parts[1]) ?? 0;
      return '${_rankTitle(pos)} [${parts[2]}]$tail';
    }
  }

  final tm = RegExp(r'^特码-(\d+)\s*[【\[]([^】\]]+)[】\]]\s*(.*)$').firstMatch(title);
  if (tm != null) {
    final rest = _formatTitleRest(tm.group(3));
    return rest.isEmpty ? '冠军 [${tm.group(2)}]' : '冠军 [${tm.group(2)}] $rest';
  }
  final pos = RegExp(r'^第(\d+)名\s*[【\[]([^】\]]+)[】\]]\s*(.*)$').firstMatch(title);
  if (pos != null) {
    final rank = int.tryParse(pos.group(1) ?? '') ?? 0;
    final rest = _formatTitleRest(pos.group(3));
    final name = _rankTitle(rank);
    return rest.isEmpty ? '$name [${pos.group(2)}]' : '$name [${pos.group(2)}] $rest';
  }
  return _stripOddsInTitle(title);
}

/// 飞单明细标题：按注单原文，不显示赔率档名。
/// 冠亚和/大/10 → 冠亚和-大；其余去掉金额后照搬，如 4/龙、4/3、1/大。
String slipBetTitle(Map<dynamic, dynamic> row) {
  final code = '${row['playCode'] ?? ''}'.trim().toUpperCase();
  final label = _slipLabel(code);
  final odds = _oddsTail(row, '${row['title'] ?? ''}');
  final tail = odds.isEmpty ? '' : ' @ $odds';
  if (label != null) return '$label$tail';
  return _stripOddsInTitle('${row['title'] ?? row['playName'] ?? '—'}');
}

String? _slipLabel(String code) {
  if (code.isEmpty) return null;
  if (code.startsWith('GYH-')) {
    return '冠亚和-${code.substring(4)}';
  }
  if (code.startsWith('GYH_')) {
    return switch (code) {
      'GYH_BIG' => '冠亚和-大',
      'GYH_SMALL' => '冠亚和-小',
      'GYH_ODD' => '冠亚和-单',
      'GYH_EVEN' => '冠亚和-双',
      'GYH_DS' => '冠亚和-大双',
      'GYH_XS' => '冠亚和-小单',
      _ => '冠亚和-${code.substring(4)}',
    };
  }
  if (code.startsWith('DT-')) {
    final parts = code.split('-');
    if (parts.length >= 3) {
      return '${parts[1]}/${parts[2] == 'D' ? '龙' : '虎'}';
    }
  }
  if (code.startsWith('LM-')) {
    final parts = code.split('-');
    if (parts.length == 2) return '1/${_cnSide(parts[1])}';
    if (parts.length >= 3) return '${parts[1]}/${_cnSide(parts[2])}';
  }
  if (code.startsWith('TM-')) {
    return '1/${code.substring(3)}';
  }
  if (code.startsWith('POS-')) {
    final parts = code.split('-');
    if (parts.length >= 3) return '${parts[1]}/${parts[2]}';
  }
  return null;
}

String _cnSide(String side) {
  return switch (side) {
    'BIG' => '大',
    'SMALL' => '小',
    'ODD' => '单',
    'EVEN' => '双',
    _ => side,
  };
}

String _rankTitle(int position) {
  const names = ['', '冠军', '亚军', '第三名', '第四名', '第五名', '第六名', '第七名', '第八名', '第九名', '第十名'];
  if (position >= 1 && position < names.length) return names[position];
  return '第$position名';
}

/// 优先用 row.odds / oddsSnapshot，否则从 title 末尾抠数字，再抹零。
String _oddsTail(Map<dynamic, dynamic> row, String title) {
  final fromField = row['odds'] ?? row['oddsSnapshot'];
  if (fromField != null && '$fromField'.trim().isNotEmpty) {
    return displayNumber(fromField, maxDecimals: 4);
  }
  final raw = RegExp(r'(\d+(?:\.\d+)?)\s*$').firstMatch(title)?.group(1);
  if (raw == null || raw.isEmpty) return '';
  return displayNumber(raw, maxDecimals: 4);
}

String _formatTitleRest(String? rest) {
  final s = (rest ?? '').trim();
  if (s.isEmpty) return '';
  return _stripOddsInTitle(s);
}

/// 把文案里 `@ 9.50000000` / 末尾赔率抹成 `@ 9.5`。
String _stripOddsInTitle(String title) {
  var s = title;
  s = s.replaceAllMapped(RegExp(r'@\s*(\d+(?:\.\d+)?)'), (m) {
    return '@ ${displayNumber(m.group(1), maxDecimals: 4)}';
  });
  final m = RegExp(r'^(.*?)(\d+(?:\.\d+)?)\s*$').firstMatch(s);
  if (m != null && m.group(1) != null && (m.group(1)!.contains('[') || m.group(1)!.trim().isNotEmpty)) {
    final head = m.group(1)!;
    // 仅当末尾像赔率（带小数或跟在空格后）才抹
    final tail = m.group(2)!;
    if (tail.contains('.') || head.endsWith(' ')) {
      return '${head.trimRight()} ${displayNumber(tail, maxDecimals: 4)}'.trim();
    }
  }
  return s;
}
