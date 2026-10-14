import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../config/theme/app_colors.dart';

/// Logo + 标题（默认「瑞丰」品牌图；大厅可传房主昵称）
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
  /// 为空时显示品牌图「瑞丰」
  final String? title;
  final Color? titleColor;

  @override
  Widget build(BuildContext context) {
    final custom = (title ?? '').trim();
    // 默认品牌：图6 已含图标+「瑞丰」文案
    if (custom.isEmpty) {
      return Image.asset(
        'assets/brand/logo.png',
        height: 112.h,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showLogo)
          Image.asset(
            'assets/brand/app_icon.png',
            width: 36.w,
            height: 36.w,
            fit: BoxFit.cover,
            filterQuality: FilterQuality.high,
          ),
        if (showTitle) ...[
          if (showLogo) SizedBox(width: 8.w),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 160.w),
            child: Text(
              custom,
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
