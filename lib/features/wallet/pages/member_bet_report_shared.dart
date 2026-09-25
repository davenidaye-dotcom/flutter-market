import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../config/theme/app_colors.dart';
import '../../../shared/format/display_number.dart';
import '../../../shared/utils/business_day.dart';
import '../widgets/date_range_filter.dart';

/// 竞猜记录日切：今日→昨日→本周→上周→本月→上个月（对齐竞品）
List<DateRangeQuickItem> memberBetQuickItems({DateTime? now}) {
  final biz = BusinessDay.of(now ?? DateTime.now());
  final monday = biz.subtract(Duration(days: biz.weekday - 1));
  final lastMonday = monday.subtract(const Duration(days: 7));
  final lastSunday = monday.subtract(const Duration(days: 1));
  final firstThis = DateTime(biz.year, biz.month, 1);
  final lastMonthEnd = firstThis.subtract(const Duration(days: 1));
  final lastMonthStart = DateTime(lastMonthEnd.year, lastMonthEnd.month, 1);
  return [
    DateRangeQuickItem(label: '今日', start: biz, end: biz),
    DateRangeQuickItem(
      label: '昨日',
      start: biz.subtract(const Duration(days: 1)),
      end: biz.subtract(const Duration(days: 1)),
    ),
    DateRangeQuickItem(label: '本周', start: monday, end: biz),
    DateRangeQuickItem(label: '上周', start: lastMonday, end: lastSunday),
    DateRangeQuickItem(
      label: '本月',
      start: DateTime(biz.year, biz.month, 1),
      end: biz,
    ),
    DateRangeQuickItem(
      label: '上个月',
      start: lastMonthStart,
      end: lastMonthEnd,
    ),
  ];
}

/// 竞品样式：蓝色选中芯片 + 灰色日期条
class MemberBetDateBar extends StatelessWidget {
  const MemberBetDateBar({
    super.key,
    required this.quickIndex,
    required this.start,
    required this.end,
    required this.quickItems,
    required this.onQuickTap,
    this.onDateTap,
  });

  final int quickIndex;
  final DateTime start;
  final DateTime end;
  final List<DateRangeQuickItem> quickItems;
  final ValueChanged<int> onQuickTap;
  final VoidCallback? onDateTap;

  static const _chipBlue = Color(0xFF4A9DF0);
  static const _chipIdle = Color(0xFFEEF1F4);

  @override
  Widget build(BuildContext context) {
    final range =
        '${DateRangeFilter.format(start)} - ${DateRangeFilter.format(end)}';
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 12.w),
      child: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (var i = 0; i < quickItems.length; i++) ...[
                  if (i > 0) SizedBox(width: 8.w),
                  GestureDetector(
                    onTap: () => onQuickTap(i),
                    child: Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: 14.w,
                        vertical: 7.h,
                      ),
                      decoration: BoxDecoration(
                        color: quickIndex == i ? _chipBlue : _chipIdle,
                        borderRadius: BorderRadius.circular(6.r),
                      ),
                      child: Text(
                        quickItems[i].label,
                        style: TextStyle(
                          fontSize: 13.sp,
                          color: quickIndex == i
                              ? Colors.white
                              : AppColors.textPrimary,
                          fontWeight: quickIndex == i
                              ? FontWeight.w600
                              : FontWeight.w400,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          SizedBox(height: 10.h),
          GestureDetector(
            onTap: onDateTap,
            child: Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(vertical: 10.h),
              decoration: BoxDecoration(
                color: _chipIdle,
                borderRadius: BorderRadius.circular(8.r),
              ),
              alignment: Alignment.center,
              child: Text(
                range,
                style: TextStyle(
                  fontSize: 13.sp,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String memberBetMoney(dynamic v, {int fraction = 2, bool trimZero = false}) {
  if (v == null) return '0';
  if (fraction < 0 && !trimZero) return displayNumber(v);
  return displayNumber(v);
}

Color memberBetPnlColor(dynamic v) {
  final n = v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
  if (n > 0) return const Color(0xFF2E9E5B);
  if (n < 0) return const Color(0xFFE53935);
  return AppColors.textPrimary;
}

String shortIssueTail(String issue) {
  final s = issue.trim();
  if (s.length <= 6) return s;
  return s.substring(s.length - 6);
}
