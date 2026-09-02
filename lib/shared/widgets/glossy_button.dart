import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../config/theme/app_colors.dart';

/// 光泽渐变按钮 — 登录/注册等
class GlossyButton extends StatelessWidget {
  const GlossyButton({
    super.key,
    required this.text,
    required this.onPressed,
    this.colors = const [AppColors.primaryLight, AppColors.primary],
    this.height,
    this.loading = false,
  });

  final String text;
  final VoidCallback? onPressed;
  final List<Color> colors;
  final double? height;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: height ?? 48.h,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: colors),
          borderRadius: BorderRadius.circular(24.r),
          boxShadow: [
            BoxShadow(
              color: colors.last.withValues(alpha: 0.35),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: loading ? null : onPressed,
            borderRadius: BorderRadius.circular(24.r),
            child: Stack(
              children: [
                Positioned(
                  top: 4.h,
                  left: 16.w,
                  right: 16.w,
                  child: Container(
                    height: 8.h,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.white.withValues(alpha: 0.4),
                          Colors.white.withValues(alpha: 0.0),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(4.r),
                    ),
                  ),
                ),
                Center(
                  child: loading
                      ? SizedBox(
                          width: 22.w,
                          height: 22.w,
                          child: const CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          text,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16.sp,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
