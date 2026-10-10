/// 彩种系列：同系列可「同步同类型」。
class GameSeries {
  GameSeries._();

  static const pk10 = 'PK10';
  static const pk10Name = '赛车系列';
  static const pk10Members = ['JS_SC', 'AZXY10', 'TW_BG_Q', 'TW_BG_H'];

  static const Map<String, String> gameNames = {
    'JS_SC': '极速赛车',
    'AZXY10': '澳洲幸运10',
    'TW_BG_Q': '宾果赛车(前)',
    'TW_BG_H': '宾果赛车(后)',
  };

  static bool isPk10(String? gameType) {
    final gt = (gameType ?? '').trim().toUpperCase();
    return pk10Members.contains(gt);
  }

  static String seriesNameOf(String? gameType) {
    return isPk10(gameType) ? pk10Name : (gameType ?? '');
  }

  /// 同系列其它彩种（不含自身）。
  static List<String> peersOf(String? gameType) {
    final gt = (gameType ?? '').trim().toUpperCase();
    if (!isPk10(gt)) return const [];
    return [for (final m in pk10Members) if (m != gt) m];
  }

  /// 已知彩种用目录名；否则去掉历史前缀「台湾」再展示。
  static String displayName(String gameType, [String? apiOrDbName]) {
    final gt = gameType.trim().toUpperCase();
    final catalog = gameNames[gt];
    if (catalog != null) return catalog;
    final raw = (apiOrDbName ?? gameType).trim();
    if (raw.startsWith('台湾')) return raw.substring(2);
    return raw.isEmpty ? gameType : raw;
  }

  static String peerNamesHint(String? gameType) {
    final peers = peersOf(gameType);
    if (peers.isEmpty) return '';
    return peers.map(displayName).join('、');
  }
}
