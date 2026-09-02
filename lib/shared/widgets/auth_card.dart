import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../config/theme/app_colors.dart';

/// 卡片顶部梯形标签
class CardTabBanner extends StatelessWidget {
  const CardTabBanner({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 28.w, vertical: 6.h),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFF8E8DC), AppColors.bannerPeach],
        ),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(6.r),
          topRight: Radius.circular(6.r),
          bottomLeft: Radius.circular(2.r),
          bottomRight: Radius.circular(2.r),
        ),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: AppColors.bannerOrange,
          fontSize: 14.sp,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// 白色圆角卡片容器
class AuthCard extends StatelessWidget {
  const AuthCard({
    super.key,
    required this.tabText,
    required this.child,
  });

  final String tabText;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.topCenter,
      children: [
        Container(
          width: double.infinity,
          margin: EdgeInsets.only(top: 14.h),
          padding: EdgeInsets.fromLTRB(24.w, 32.h, 24.w, 24.h),
          decoration: BoxDecoration(
            color: AppColors.cardWhite,
            borderRadius: BorderRadius.circular(24.r),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: child,
        ),
        Positioned(top: 0, child: CardTabBanner(text: tabText)),
      ],
    );
  }
}
