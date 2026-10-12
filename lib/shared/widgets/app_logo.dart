import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../config/theme/app_colors.dart';

/// Logo + 标题（默认「乐投」；大厅可传房主昵称）
class AppLogoHeader extends StatelessWidget {
  const AppLogoHeader({
    super.key,
    this.showTitle = true,
    this.showLogo = true,
    this.title,
    this.titleColor,
  });

  final bool showTitle;
  final bool showLogo;
  /// 为空时显示「乐投」
  final String? title;
  final Color? titleColor;

  @override
  Widget build(BuildContext context) {
    final label = (title ?? '').trim().isEmpty ? '乐投' : title!.trim();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showLogo)
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
          if (showLogo) SizedBox(width: 8.w),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 160.w),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 20.sp,
                fontWeight: FontWeight.bold,
                color: titleColor ?? AppColors.primaryDark,
              ),
            ),
          ),
        ],
      ],
    );
  }
}
