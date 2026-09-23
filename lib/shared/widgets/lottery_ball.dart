import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../config/theme/app_colors.dart';

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
    if (placeholder) {
      return Container(
        width: s,
        height: s,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0xFF5D4037),
          borderRadius: BorderRadius.circular(4.r),
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
        color: color,
        borderRadius: BorderRadius.circular(4.r),
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
    /// true：10 列等宽，方框铺满格子并与表头「一」～「十」对齐。
    this.expandSlots = false,
    this.fontScale = 0.48,
    /// 指定后数字用这个绝对字号，不随方框变大。
    this.digitFontSize,
  });

  final List<int> numbers;
  final bool placeholder;
  final double? ballSize;
  final double? gap;
  final bool expandSlots;
  final double fontScale;
  final double? digitFontSize;

  @override
  Widget build(BuildContext context) {
    if (expandSlots) {
      return LayoutBuilder(
        builder: (context, constraints) {
          final slot = constraints.maxWidth / 10;
          final slotGap = 1.w;
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
    final spacing = gap ?? 3.w;
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
