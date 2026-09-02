import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../config/theme/app_colors.dart';

/// Shared empty-list hint (same look as existing report pages).
class AppEmptyHint extends StatelessWidget {
  const AppEmptyHint({
    super.key,
    this.text = '\u6682\u65e0\u6570\u636e',
  });

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(fontSize: 14.sp, color: AppColors.textHint),
    );
  }
}
