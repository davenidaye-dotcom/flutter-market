import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../config/theme/app_colors.dart';

/// 开奖球视觉规范：间隔 / 圆角对齐 FlipCountdown compact（margin 0.5.w×2、radius 2.r）。
abstract final class LotteryBallStyle {
  static double gap() => 1.w;
  static double radius() => 2.r;
}

/// 开奖号码球
class LotteryBall extends StatelessWidget {
  const LotteryBall({
    super.key,
    required this.number,
    this.size,
    this.placeholder = false,
    /// 数字相对球径比例，默认 0.48；历史表可加大
    this.fontScale = 0.48,
  });

  final int number;
  final double? size;
  final bool placeholder;
  final double fontScale;

  @override
  Widget build(BuildContext context) {
    final s = size ?? 22.w;
    final radius = LotteryBallStyle.radius();
    if (placeholder) {
      return Container(
        width: s,
        height: s,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0xFF5D4037),
          borderRadius: BorderRadius.circular(radius),
          boxShadow: AppColors.ballBoxShadows,
        ),
        child: Text(
          '-',
          style: TextStyle(color: Colors.white, fontSize: s * fontScale),
        ),
      );
    }
    final color = AppColors.ballColors[number] ?? AppColors.textSecondary;
    return Container(
      width: s,
      height: s,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: AppColors.ballGradient(color),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: AppColors.ballBorderColor(color), width: 0.6),
        boxShadow: AppColors.ballBoxShadows,
      ),
      child: Text(
        '$number',
        style: TextStyle(
          color: AppColors.ballDigitColor(number),
          fontSize: s * fontScale,
          height: 1,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

/// 号码球行
class LotteryBallRow extends StatelessWidget {
  const LotteryBallRow({
    super.key,
    required this.numbers,
    this.placeholder = false,
    this.ballSize,
    this.gap,
    /// true：10 列等宽，方框居中，列间保留 [gap]（默认对齐倒计时）。
    this.expandSlots = false,
    this.fontScale = 0.48,
    /// 指定后数字用这个绝对字号，不随方框变大。
    this.digitFontSize,
    @Deprecated('勿再加大吃掉间隔，保留参数仅为兼容调用')
    this.boxBoost = 0,
  });

  final List<int> numbers;
  final bool placeholder;
  final double? ballSize;
  final double? gap;
  final bool expandSlots;
  final double fontScale;
  final double? digitFontSize;
  final double boxBoost;

  @override
  Widget build(BuildContext context) {
    if (expandSlots) {
      return LayoutBuilder(
        builder: (context, constraints) {
          final slot = constraints.maxWidth / 10;
          // 与 FlipCountdown compact 数字间隔一致：左右各 0.5.w → 合计 1.w
          final slotGap = gap ?? LotteryBallStyle.gap();
          var size = slot - slotGap;
          final maxH = constraints.maxHeight;
          if (maxH.isFinite && maxH > 0 && maxH < size) {
            size = maxH;
          }
          size = math.max(1, size);
          final scale = digitFontSize != null && digitFontSize! > 0
              ? digitFontSize! / size
              : fontScale;
          return Row(
            children: List.generate(
              10,
              (i) => Expanded(
                child: Center(
                  child: LotteryBall(
                    number: i < numbers.length ? numbers[i] : 0,
                    size: size,
                    placeholder: placeholder || i >= numbers.length,
                    fontScale: scale,
                  ),
                ),
              ),
            ),
          );
        },
      );
    }
    final spacing = gap ?? LotteryBallStyle.gap();
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(
          10,
          (i) => Padding(
            padding: EdgeInsets.only(right: i < 9 ? spacing : 0),
            child: LotteryBall(
              number: i < numbers.length ? numbers[i] : 0,
              size: ballSize,
              placeholder: placeholder || i >= numbers.length,
              fontScale: fontScale,
            ),
          ),
        ),
      ),
    );
  }
}
