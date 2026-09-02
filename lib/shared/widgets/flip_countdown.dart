import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../config/theme/app_colors.dart';

/// 翻页时钟倒计时 —— 统一 mm:ss（分最大 99，秒 00–59）
class FlipCountdown extends StatelessWidget {
  const FlipCountdown({
    super.key,
    required this.seconds,
    this.digitColor = AppColors.countdownGreen,
    this.compact = false,
  });

  final int seconds;
  final Color digitColor;
  /// 与「封盘中/开奖中」文字同高，避免期态切换抖动
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final safe = seconds.clamp(0, 99 * 60 + 59);
    final m = safe ~/ 60;
    final s = safe % 60; // 永远 0–59
    final digits = [m ~/ 10, m % 10, -1, s ~/ 10, s % 10];
    final rowHeight = compact ? 18.h : 26.h;

    return SizedBox(
      height: rowHeight,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          for (final d in digits)
            if (d == -1)
              Padding(
                padding: EdgeInsets.symmetric(horizontal: compact ? 1.w : 2.w),
                child: Text(
                  ':',
                  style: TextStyle(
                    fontSize: compact ? 12.sp : 16.sp,
                    color: digitColor,
                    height: 1,
                  ),
                ),
              )
            else
              _DigitBox(digit: d, color: digitColor, compact: compact),
        ],
      ),
    );
  }
}

class _DigitBox extends StatelessWidget {
  const _DigitBox({
    required this.digit,
    required this.color,
    this.compact = false,
  });

  final int digit;
  final Color color;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: compact ? 13.w : 20.w,
      height: compact ? 18.h : 26.h,
      margin: EdgeInsets.symmetric(horizontal: compact ? 0.5.w : 1.w),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(compact ? 2.r : 3.r),
      ),
      child: Text(
        '$digit',
        style: TextStyle(
          color: Colors.white,
          fontSize: compact ? 11.sp : 14.sp,
          fontWeight: FontWeight.bold,
          height: 1,
        ),
      ),
    );
  }
}
