import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../config/theme/app_colors.dart';

/// 乐投 Logo + 品牌名
class AppLogoHeader extends StatelessWidget {
  const AppLogoHeader({super.key, this.showTitle = true});

  final bool showTitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 36.w,
          height: 36.w,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [AppColors.primaryLight, AppColors.primary],
            ),
            borderRadius: BorderRadius.circular(8.r),
          ),
          child: Icon(Icons.bolt, color: Colors.white, size: 22.sp),
        ),
        if (showTitle) ...[
          SizedBox(width: 8.w),
          Text(
            '乐投',
            style: TextStyle(
              fontSize: 22.sp,
              fontWeight: FontWeight.bold,
              color: AppColors.primaryDark,
            ),
          ),
        ],
      ],
    );
  }
}
