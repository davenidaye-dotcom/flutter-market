import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../config/theme/app_colors.dart';

/// 玩家查询底栏，样式对齐积分变更：页码、总条数、上一页、下一页。
class MemberPageBar extends StatelessWidget {
  const MemberPageBar({
    super.key,
    required this.page,
    required this.totalPages,
    required this.totalCount,
    required this.onPrev,
    required this.onNext,
    this.busy = false,
  });

  final int page;
  final int totalPages;
  final int totalCount;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(16.w, 10.h, 16.w, 12.h),
      color: Colors.white,
      child: Row(
        children: [
          Text(
            '页码 $page / $totalPages  共 $totalCount 条',
            style: TextStyle(fontSize: 13.sp, color: AppColors.textPrimary),
          ),
          const Spacer(),
          _btn('上一页', busy ? null : onPrev),
          SizedBox(width: 8.w),
          _btn('下一页', busy ? null : onNext),
        ],
      ),
    );
  }

  Widget _btn(String label, VoidCallback? onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 8.h),
        decoration: BoxDecoration(
          color: onTap == null ? const Color(0xFFB9D4F5) : AppColors.navBlue,
          borderRadius: BorderRadius.circular(6.r),
        ),
        child: Text(label, style: TextStyle(fontSize: 13.sp, color: Colors.white)),
      ),
    );
  }
}

int memberTotalPages(int total, int pageSize) {
  if (pageSize <= 0) return 0;
  if (total <= 0) return 0;
  return (total + pageSize - 1) ~/ pageSize;
}
