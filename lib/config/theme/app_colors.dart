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

  /// 开奖号码方框色，取自房间模板截图。
  static const ballColors = <int, Color>{
    1: Color(0xFFF9F100),
    2: Color(0xFF0C8AEB),
    3: Color(0xFF4A4A4A),
    4: Color(0xFFF1780F),
    5: Color(0xFF77F6F6),
    6: Color(0xFF5437ED),
    7: Color(0xFFE3E3E3),
    8: Color(0xFFED2D0D),
    9: Color(0xFF770D06),
    10: Color(0xFF0FB60C),
  };

  /// 1、5、7 是浅底，白字看不清，用深色；其余保持白字。
  static Color ballDigitColor(int number) {
    if (number == 1 || number == 5 || number == 7) {
      return const Color(0xFF333333);
    }
    return const Color(0xFFFFFFFF);
  }
}
