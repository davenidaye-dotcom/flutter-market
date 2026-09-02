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
  });

  final int number;
  final double? size;
  final bool placeholder;

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
        child: Text('-', style: TextStyle(color: Colors.white, fontSize: 10.sp)),
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
          color: Colors.white,
          fontSize: (s * 0.5).sp,
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
  });

  final List<int> numbers;
  final bool placeholder;
  final double? ballSize;
  final double? gap;

  @override
  Widget build(BuildContext context) {
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
            ),
          ),
        ),
      ),
    );
  }
}
