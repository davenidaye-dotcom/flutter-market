import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// 试玩号红标，和房主玩家信息页一致。
class TrialAccountTag extends StatelessWidget {
  const TrialAccountTag({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 2.h),
      decoration: BoxDecoration(
        color: const Color(0xFFE53935),
        borderRadius: BorderRadius.circular(4.r),
      ),
      child: Text(
        '试玩号',
        style: TextStyle(fontSize: 10.sp, color: Colors.white, height: 1.2),
      ),
    );
  }
}
