import 'package:flutter/material.dart';

/// 加拿大三个数字的本地属性。黄波不可下注。
abstract final class Pc28Format {
  static bool valid(List<int> ranks) =>
      ranks.length == 3 && ranks.every((n) => n >= 0 && n <= 9);

  static int sumOf(List<int> ranks) => ranks[0] + ranks[1] + ranks[2];

  static String combo(int sum) =>
      '${sum >= 14 ? '大' : '小'}${sum.isEven ? '双' : '单'}';

  static String wave(int sum) {
    const red = {3, 6, 9, 12, 15, 18, 21, 24};
    const blue = {2, 5, 8, 11, 17, 20, 23, 26};
    const green = {1, 4, 7, 10, 16, 19, 22, 25};
    if (red.contains(sum)) return '红';
    if (blue.contains(sum)) return '蓝';
    if (green.contains(sum)) return '绿';
    return '黄';
  }

  /// 球内数字对应的波色。0、13、14、27 为黄。
  static Color colorOf(int n) {
    return switch (wave(n)) {
      '红' => const Color(0xFFF0423E),
      '蓝' => const Color(0xFF3B7EF0),
      '绿' => const Color(0xFF45CE3E),
      _ => const Color(0xFFFFCC3D),
    };
  }

  /// 盘口选法对应的房间赔率档。
  static String? oddsKey(String uiKey) {
    final code = playCode(uiKey);
    if (code == null) return null;
    return switch (code) {
      'P28-BIG' || 'P28-SMALL' || 'P28-ODD' || 'P28-EVEN' => 'P28-LM',
      'P28-BIG-ODD' || 'P28-SMALL-EVEN' => 'P28-COMBO-A',
      'P28-BIG-EVEN' || 'P28-SMALL-ODD' => 'P28-COMBO-B',
      'P28-EXT-BIG' || 'P28-EXT-SMALL' => 'P28-EXT',
      'P28-WAVE-RED' || 'P28-WAVE-BLUE' || 'P28-WAVE-GREEN' => 'P28-WAVE',
      'P28-BAO' => 'P28-BAO',
      'P28-DT-D' || 'P28-DT-T' => 'P28-DT',
      'P28-DT-TIE' => 'P28-TIE',
      _ when code.startsWith('P28-BALL-') => 'P28-BALL',
      _ when code.startsWith('P28-POS-') => 'P28-POS',
      _ => null,
    };
  }

  static String extreme(int sum) {
    if (sum >= 22) return '极大';
    if (sum <= 5) return '极小';
    return '';
  }

  static bool leopard(List<int> ranks) =>
      valid(ranks) && ranks[0] == ranks[1] && ranks[1] == ranks[2];

  static String dragonTiger(List<int> ranks) {
    if (ranks[0] > ranks[2]) return '龙';
    if (ranks[0] < ranks[2]) return '虎';
    return '和';
  }

  /// 盘口选法 → 机器码。`大`、`1/0`、`1/大`。
  static String? playCode(String uiKey) {
    final key = uiKey.trim();
    const sides = {
      '大': 'P28-BIG',
      '小': 'P28-SMALL',
      '单': 'P28-ODD',
      '双': 'P28-EVEN',
      '大单': 'P28-BIG-ODD',
      '大双': 'P28-BIG-EVEN',
      '小单': 'P28-SMALL-ODD',
      '小双': 'P28-SMALL-EVEN',
      '极大': 'P28-EXT-BIG',
      '极小': 'P28-EXT-SMALL',
      '红波': 'P28-WAVE-RED',
      '蓝波': 'P28-WAVE-BLUE',
      '绿波': 'P28-WAVE-GREEN',
      '豹子': 'P28-BAO',
      '龙': 'P28-DT-D',
      '虎': 'P28-DT-T',
      '和': 'P28-DT-TIE',
    };
    final direct = sides[key];
    if (direct != null) return direct;
    final parts = key.split('/');
    if (parts.length == 2 && '123'.contains(parts[0]) && parts[1].length == 1) {
      final side = switch (parts[1]) {
        '大' => 'BIG',
        '小' => 'SMALL',
        '单' => 'ODD',
        '双' => 'EVEN',
        _ => null,
      };
      if (side != null) return 'P28-BALL-${parts[0]}-$side';
      final digit = int.tryParse(parts[1]);
      if (digit != null && digit >= 0 && digit <= 9) {
        return 'P28-POS-${parts[0]}-$digit';
      }
    }
    return null;
  }
}
