import 'package:flutter/material.dart';

/// 原型图色值
abstract final class AppColors {
  static const primary = Color(0xFF4A89DC);
  static const primaryLight = Color(0xFF5BA4E8);
  static const primaryDark = Color(0xFF2E6BB5);
  static const accentBrown = Color(0xFFB8865D);
  static const accentBrownDark = Color(0xFFB38E6B);
  static const bannerPeach = Color(0xFFF5E1D2);
  static const bannerOrange = Color(0xFFD35400);
  static const bgGradientStart = Color(0xFFA5D6F7);
  static const bgGradientEnd = Color(0xFFF0F8FF);
  static const cardWhite = Color(0xFFFFFFFF);
  static const glassWhite = Color(0xCCFFFFFF);
  static const textPrimary = Color(0xFF333333);
  static const textSecondary = Color(0xFF8E8E93);
  static const textHint = Color(0xFFBDBDBD);
  static const divider = Color(0xFFE8E8E8);
  static const tabActive = Color(0xFF81D4D2);
  static const dialogBg = Color(0xFFEAE8F0);
  static const success = Color(0xFF4CAF50);
  static const danger = Color(0xFFE53935);
  static const warning = Color(0xFFFF5722);
  static const countdownGreen = Color(0xFF4CAF50);
  static const navBlue = Color(0xFF54A8FB);
  static const sidebarActive = Color(0xFF4A698A);
  static const sidebarInactive = Color(0xFFF0F0F0);

  /// 开奖号码方框色：截图色轻暗方案 A（×0.88）。历史表 / 开奖卡统一。
  static const ballColors = <int, Color>{
    1: Color(0xFFDEDE00),
    2: Color(0xFF007FDE),
    3: Color(0xFF3F3F3F),
    4: Color(0xFFDE6400),
    5: Color(0xFF6ADEDE),
    6: Color(0xFF452ADE),
    7: Color(0xFFC9C9C9),
    8: Color(0xFFDE2000),
    9: Color(0xFF6A0B00),
    10: Color(0xFF05A400),
  };

  /// 开奖卡顶行和分色车：与 [ballColors] 同色板。
  static const resultBallColors = <int, Color>{
    1: Color(0xFFDEDE00),
    2: Color(0xFF007FDE),
    3: Color(0xFF3F3F3F),
    4: Color(0xFFDE6400),
    5: Color(0xFF6ADEDE),
    6: Color(0xFF452ADE),
    7: Color(0xFFC9C9C9),
    8: Color(0xFFDE2000),
    9: Color(0xFF6A0B00),
    10: Color(0xFF05A400),
  };

  /// 开奖球号：统一纯白（含浅色底 1/5/7）。
  static Color ballDigitColor(int number) {
    return const Color(0xFFFFFFFF);
  }

  /// 数字轻黑描边（四向短阴影模拟描边，不糊边）。
  static List<Shadow> get ballDigitShadows => const [
        Shadow(color: Color(0xB3000000), blurRadius: 0, offset: Offset(-0.6, 0)),
        Shadow(color: Color(0xB3000000), blurRadius: 0, offset: Offset(0.6, 0)),
        Shadow(color: Color(0xB3000000), blurRadius: 0, offset: Offset(0, -0.6)),
        Shadow(color: Color(0xB3000000), blurRadius: 0, offset: Offset(0, 0.6)),
      ];

  /// 球框轻阴影 + 边缘，贴近截图立体感（不改框尺寸）。
  static List<BoxShadow> get ballBoxShadows => [
        BoxShadow(
          color: const Color(0x40000000),
          blurRadius: 1.5,
          offset: const Offset(0, 1),
        ),
      ];

  static Color ballBorderColor(Color fill) {
    return Color.lerp(fill, const Color(0xFF000000), 0.18)!;
  }

  /// 色块以选定颜色为准，只留很浅的明暗，避免白高光把框抬亮。
  static LinearGradient ballGradient(Color fill) {
    return LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        Color.lerp(fill, const Color(0xFFFFFFFF), 0.04)!,
        fill,
        Color.lerp(fill, const Color(0xFF000000), 0.06)!,
      ],
      stops: const [0.0, 0.48, 1.0],
    );
  }
}
