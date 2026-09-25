/// UI 选法 key → 机器 playCode（与后端 BetJudge 一致，不含中文）
library;

const _rankNames = [
  '冠军',
  '亚军',
  '三名',
  '四名',
  '五名',
  '六名',
  '七名',
  '八名',
  '九名',
  '十名',
];

/// 盘面选法 `冠军/大` → `LM-BIG`；已是机器码则原样返回。
String? uiKeyToPlayCode(String uiKey) {
  final key = uiKey.trim();
  if (key.isEmpty) return null;
  final upper = key.toUpperCase();
  if (upper.startsWith('LM-') ||
      upper.startsWith('TM-') ||
      upper.startsWith('POS-') ||
      upper.startsWith('DT-') ||
      upper.startsWith('GYH_') ||
      upper.startsWith('GYH-')) {
    return upper;
  }
  final parts = key.split('/');
  if (parts.isEmpty) return null;

  // 冠亚和/11、冠亚和/大
  if (parts.first == '冠亚和') {
    if (parts.length < 2) return null;
    final sel = parts[1];
    if (sel == '大') return 'GYH_BIG';
    if (sel == '小') return 'GYH_SMALL';
    if (sel == '单') return 'GYH_ODD';
    if (sel == '双') return 'GYH_EVEN';
    final n = int.tryParse(sel);
    if (n != null) return _sumValueCode(n);
    return null;
  }

  if (parts.length != 2) return null;
  final rankLabel = parts[0];
  final sel = parts[1];
  final pos = _rankIndex(rankLabel);
  if (pos == null) return null;

  if (sel == '大' || sel == '小' || sel == '单' || sel == '双') {
    final side = switch (sel) {
      '大' => 'BIG',
      '小' => 'SMALL',
      '单' => 'ODD',
      '双' => 'EVEN',
      _ => '',
    };
    return pos == 1 ? 'LM-$side' : 'LM-$pos-$side';
  }
  if (sel == '龙' || sel == '虎') {
    if (pos < 1 || pos > 5) return null;
    return 'DT-$pos-${sel == '龙' ? 'D' : 'T'}';
  }
  final num = int.tryParse(sel);
  if (num != null && num >= 1 && num <= 10) {
    return pos == 1 ? 'TM-$num' : 'POS-$pos-$num';
  }
  return null;
}

int? _rankIndex(String label) {
  final i = _rankNames.indexOf(label);
  return i >= 0 ? i + 1 : null;
}

String? _sumValueCode(int v) {
  if (v < 3 || v > 19) return null;
  return 'GYH-$v';
}

/// 注单码 → 房主赔率档，与 BetJudge.oddsKeyOf 一致。
String? oddsKeyOf(String? playCode) {
  if (playCode == null || playCode.isEmpty) return null;
  final p = playCode.toUpperCase();
  if (p.startsWith('TM-') || p == 'TM') return 'TM';
  if (p.startsWith('LM-') || p == 'LM') return 'LM';
  if (p.startsWith('POS-') || p == 'POS') return 'POS';
  if (p.startsWith('DT-') || p == 'DT') return 'DT';
  if (p.startsWith('GYH_')) return p;
  if (p.startsWith('GYH-')) {
    final n = int.tryParse(p.substring(4));
    if (n == 11) return 'GYH_11';
    if (n == 3 || n == 4 || n == 18 || n == 19) return 'GYH_3';
    if (n == 5 || n == 6 || n == 16 || n == 17) return 'GYH_5';
    if (n == 7 || n == 8 || n == 14 || n == 15) return 'GYH_7';
    if (n == 9 || n == 10 || n == 12 || n == 13) return 'GYH_9';
    return p;
  }
  return null;
}

/// 聊天/指令框文本是否像机器 playCode（不应作为 command 发送）
bool isMachinePlayCode(String text) {
  final p = text.trim().toUpperCase();
  return p.startsWith('LM-') ||
      p.startsWith('TM-') ||
      p.startsWith('POS-') ||
      p.startsWith('DT-') ||
      p.startsWith('GYH_') ||
      p.startsWith('GYH-');
}
