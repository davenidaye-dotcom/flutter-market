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
      upper.startsWith('GYH_')) {
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
  if ({3, 4, 18, 19}.contains(v)) return 'GYH_3';
  if ({5, 6, 16, 17}.contains(v)) return 'GYH_5';
  if ({7, 8, 14, 15}.contains(v)) return 'GYH_7';
  if ({9, 10, 12, 13}.contains(v)) return 'GYH_9';
  if (v == 11) return 'GYH_11';
  return null;
}

/// 聊天/指令框文本是否像机器 playCode（不应作为 command 发送）
bool isMachinePlayCode(String text) {
  final p = text.trim().toUpperCase();
  return p.startsWith('LM-') ||
      p.startsWith('TM-') ||
      p.startsWith('POS-') ||
      p.startsWith('DT-') ||
      p.startsWith('GYH_');
}
