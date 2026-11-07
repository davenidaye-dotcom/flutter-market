/// 对齐后端 ChatPlayText / BetService.preview 的号码展示口径。
/// TM-n → 冠军 n；POS-r-n → 冠军/亚军/第r名 n。
String playDisplayLabel(String? playCode, {String? fallbackName}) {
  final p = (playCode ?? '').trim().toUpperCase();
  if (p.isEmpty) {
    final fb = (fallbackName ?? '').trim();
    return fb.isEmpty ? '—' : fb;
  }
  final group = _groupName(p, fallbackName);
  final sel = _selection(p);
  if (sel.isEmpty) return group;
  return '$group $sel';
}

String _groupName(String p, String? fallbackName) {
  if (p.startsWith('P28-')) return _pc28Group(p);
  if (p.startsWith('POS-') ||
      (p.startsWith('LM-') && p.split('-').length == 3) ||
      p.startsWith('DT-')) {
    final parts = p.split('-');
    if (parts.length >= 2) {
      final rank = int.tryParse(parts[1]);
      if (rank != null) return _rankTitle(rank);
    }
  }
  // TM-n：特码始终是冠军位。
  if (p.startsWith('TM-')) {
    return '冠军';
  }
  if (p == 'LM-BIG' ||
      p == 'LM-SMALL' ||
      p == 'LM-ODD' ||
      p == 'LM-EVEN') {
    return '冠军';
  }
  if (p.startsWith('GYH_') || p.startsWith('GYH-')) {
    return '冠亚和';
  }
  final fb = (fallbackName ?? '').trim();
  return fb.isEmpty ? p : fb;
}

String _selection(String p) {
  if (p.startsWith('P28-')) return _pc28Selection(p);
  if (p.startsWith('POS-')) {
    final parts = p.split('-');
    if (parts.length >= 3) return parts[2];
  }
  if (p.startsWith('TM-')) {
    return p.substring(3);
  }
  if (p.startsWith('LM-')) {
    final parts = p.split('-');
    final side = parts.last;
    return switch (side) {
      'BIG' => '大',
      'SMALL' => '小',
      'ODD' => '单',
      'EVEN' => '双',
      _ => side,
    };
  }
  if (p.startsWith('GYH-')) {
    return p.substring(4);
  }
  if (p.startsWith('GYH_')) {
    return switch (p) {
      'GYH_DS' => '大双',
      'GYH_XS' => '小单',
      'GYH_BIG' => '大',
      'GYH_SMALL' => '小',
      'GYH_ODD' => '单',
      'GYH_EVEN' => '双',
      _ => p.substring(4),
    };
  }
  if (p.startsWith('DT-')) {
    final parts = p.split('-');
    if (parts.length >= 3) {
      return parts[2] == 'D' ? '龙' : '虎';
    }
  }
  return '';
}

String _pc28Group(String p) {
  if (p.startsWith('P28-POS-') || p.startsWith('P28-BALL-')) {
    final parts = p.split('-');
    if (parts.length >= 3) {
      return switch (parts[2]) {
        '1' => '第一球',
        '2' => '第二球',
        '3' => '第三球',
        _ => '定位',
      };
    }
  }
  if (p.startsWith('P28-WAVE') || p == 'P28-BAO') return '色波';
  if (p.startsWith('P28-DT')) return '龙虎';
  return '总和';
}

String _pc28Selection(String p) {
  if (p.startsWith('P28-POS-')) {
    final parts = p.split('-');
    return parts.length >= 4 ? parts[3] : '';
  }
  if (p.startsWith('P28-BALL-')) {
    final parts = p.split('-');
    if (parts.length < 4) return '';
    return switch (parts[3]) {
      'BIG' => '大',
      'SMALL' => '小',
      'ODD' => '单',
      'EVEN' => '双',
      _ => '',
    };
  }
  return switch (p) {
    'P28-BIG' => '大',
    'P28-SMALL' => '小',
    'P28-ODD' => '单',
    'P28-EVEN' => '双',
    'P28-BIG-ODD' => '大单',
    'P28-BIG-EVEN' => '大双',
    'P28-SMALL-ODD' => '小单',
    'P28-SMALL-EVEN' => '小双',
    'P28-EXT-BIG' => '极大',
    'P28-EXT-SMALL' => '极小',
    'P28-WAVE-RED' => '红波',
    'P28-WAVE-BLUE' => '蓝波',
    'P28-WAVE-GREEN' => '绿波',
    'P28-BAO' => '豹子',
    'P28-DT-D' => '龙',
    'P28-DT-T' => '虎',
    'P28-DT-TIE' => '和',
    _ => '',
  };
}

String _rankTitle(int position) {
  return switch (position) {
    1 => '冠军',
    2 => '亚军',
    3 => '第三名',
    4 => '第四名',
    5 => '第五名',
    6 => '第六名',
    7 => '第七名',
    8 => '第八名',
    9 => '第九名',
    10 => '第十名',
    _ => '第$position名',
  };
}
