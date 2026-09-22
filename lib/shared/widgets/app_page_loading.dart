import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../config/theme/app_colors.dart';

/// 页面级加载：旋转加载图标 +「加载中」，替代居中大转圈。
class AppPageLoading extends StatefulWidget {
  const AppPageLoading({super.key, this.message = '加载中'});

  final String message;

  @override
  State<AppPageLoading> createState() => _AppPageLoadingState();
}

class _AppPageLoadingState extends State<AppPageLoading>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = 28.sp;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          RotationTransition(
            turns: _ctrl,
            child: Image.asset(
              'assets/icons/loading.png',
              width: size,
              height: size,
              filterQuality: FilterQuality.medium,
            ),
          ),
          SizedBox(height: 10.h),
          Text(
            widget.message,
            style: TextStyle(
              fontSize: 14.sp,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
