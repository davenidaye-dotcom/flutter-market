import 'package:flutter/material.dart';
import '../../config/theme/app_colors.dart';

/// 全局渐变背景
class GradientBackground extends StatelessWidget {
  const GradientBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AppColors.bgGradientStart, AppColors.bgGradientEnd],
        ),
      ),
      child: child,
    );
  }
}
