import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../config/theme/app_colors.dart';

/// 图标右上角红色数字角标
class RedCountBadge extends StatelessWidget {
  const RedCountBadge({
    super.key,
    required this.count,
    this.minSize,
  });

  final int count;
  final double? minSize;

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox.shrink();
    final size = minSize ?? 14.w;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 4.w),
      constraints: BoxConstraints(minWidth: size, minHeight: size),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.danger,
        borderRadius: BorderRadius.circular(size),
      ),
      child: Text(
        count > 99 ? '99+' : '$count',
        style: TextStyle(
          fontSize: 9.sp,
          color: Colors.white,
          height: 1.1,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// 给子组件右上角叠角标
class BadgedIcon extends StatelessWidget {
  const BadgedIcon({
    super.key,
    required this.child,
    required this.count,
    this.right = -8,
    this.top = -4,
  });

  final Widget child;
  final int count;
  final double right;
  final double top;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        if (count > 0)
          Positioned(
            right: right.w,
            top: top.h,
            child: RedCountBadge(count: count),
          ),
      ],
    );
  }
}
