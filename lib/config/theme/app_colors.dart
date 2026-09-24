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

  /// 开奖号码方框色，对齐 ar198 号码盘截图采样。
  static const ballColors = <int, Color>{
    1: Color(0xFFE3DB08),
    2: Color(0xFF0491DA),
    3: Color(0xFF494949),
    4: Color(0xFFFA7505),
    5: Color(0xFF1AE0E3),
    6: Color(0xFF5334F9),
    7: Color(0xFFBEBEBE),
    8: Color(0xFFF82805),
    9: Color(0xFF750A04),
    10: Color(0xFF0BBA08),
  };

  /// 开奖球号统一白字（彩种列表 / 下注页对齐）。
  static Color ballDigitColor(int number) {
    return const Color(0xFFFFFFFF);
  }

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

  /// 轻微垂直渐变，模拟截图里的按钮高光。
  static LinearGradient ballGradient(Color fill) {
    return LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        Color.lerp(fill, const Color(0xFFFFFFFF), 0.14)!,
        fill,
        Color.lerp(fill, const Color(0xFF000000), 0.10)!,
      ],
      stops: const [0.0, 0.48, 1.0],
    );
  }
}
