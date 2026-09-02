import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../config/theme/app_colors.dart';

/// 快捷日期 + 起止日期 + 查询（上下分/福利/竞猜/代理共用）
class DateRangeFilter extends StatelessWidget {
  const DateRangeFilter({
    super.key,
    required this.quickIndex,
    required this.start,
    required this.end,
    required this.onQuickTap,
    required this.onPickStart,
    required this.onPickEnd,
    required this.onQuery,
  });

  final int quickIndex;
  final DateTime start;
  final DateTime end;
  final ValueChanged<int> onQuickTap;
  final VoidCallback onPickStart;
  final VoidCallback onPickEnd;
  final VoidCallback onQuery;

  static const quickLabels = ['今天', '昨天', '上周', '本周', '上月', '本月'];

  static String format(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// 根据快捷项计算起止日期（含当天）
  static (DateTime, DateTime) rangeForQuick(int index, {DateTime? now}) {
    final n = now ?? DateTime.now();
    final today = DateTime(n.year, n.month, n.day);
    switch (index) {
      case 1: // 昨天
        final y = today.subtract(const Duration(days: 1));
        return (y, y);
      case 2: // 上周
        final weekday = today.weekday;
        final thisMonday = today.subtract(Duration(days: weekday - 1));
        final lastMonday = thisMonday.subtract(const Duration(days: 7));
        final lastSunday = thisMonday.subtract(const Duration(days: 1));
        return (lastMonday, lastSunday);
      case 3: // 本周
        final weekday = today.weekday;
        final monday = today.subtract(Duration(days: weekday - 1));
        return (monday, today);
      case 4: // 上月
        final firstThis = DateTime(today.year, today.month, 1);
        final lastMonthEnd = firstThis.subtract(const Duration(days: 1));
        final lastMonthStart = DateTime(lastMonthEnd.year, lastMonthEnd.month, 1);
        return (lastMonthStart, lastMonthEnd);
      case 5: // 本月
        return (DateTime(today.year, today.month, 1), today);
      case 0:
      default:
        return (today, today);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 12.w),
      child: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (var i = 0; i < quickLabels.length; i++) ...[
                  if (i > 0) SizedBox(width: 8.w),
                  _Chip(
                    label: quickLabels[i],
                    active: quickIndex == i,
                    onTap: () => onQuickTap(i),
                  ),
                ],
              ],
            ),
          ),
          SizedBox(height: 10.h),
          Row(
            children: [
              Expanded(
                child: _DateBox(text: format(start), onTap: onPickStart),
              ),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 6.w),
                child: Text('至', style: TextStyle(fontSize: 13.sp, color: AppColors.textPrimary)),
              ),
              Expanded(
                child: _DateBox(text: format(end), onTap: onPickEnd),
              ),
              SizedBox(width: 8.w),
              GestureDetector(
                onTap: onQuery,
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
                  decoration: BoxDecoration(
                    color: AppColors.navBlue,
                    borderRadius: BorderRadius.circular(20.r),
                  ),
                  child: Text(
                    '查询',
                    style: TextStyle(fontSize: 14.sp, color: Colors.white, fontWeight: FontWeight.w500),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.active, required this.onTap});

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
        decoration: BoxDecoration(
          color: active ? AppColors.navBlue : Colors.white,
          borderRadius: BorderRadius.circular(16.r),
          border: Border.all(color: active ? AppColors.navBlue : const Color(0xFFD0E8F8)),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13.sp,
            color: active ? Colors.white : AppColors.navBlue,
          ),
        ),
      ),
    );
  }
}

class _DateBox extends StatelessWidget {
  const _DateBox({required this.text, required this.onTap});

  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 36.h,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8.r),
        ),
        child: Text(
          text,
          style: TextStyle(fontSize: 13.sp, color: AppColors.textPrimary),
        ),
      ),
    );
  }
}

/// 白底圆角内容区
class ReportCard extends StatelessWidget {
  const ReportCard({super.key, required this.child, this.padding});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16.r),
      ),
      clipBehavior: Clip.antiAlias,
      padding: padding,
      child: child,
    );
  }
}

mixin DateRangePageMixin<T extends StatefulWidget> on State<T> {
  int quickIndex = 0;
  late DateTime start;
  late DateTime end;

  @override
  void initState() {
    super.initState();
    final r = DateRangeFilter.rangeForQuick(0);
    start = r.$1;
    end = r.$2;
  }

  void onQuickTap(int i) {
    final r = DateRangeFilter.rangeForQuick(i);
    setState(() {
      quickIndex = i;
      start = r.$1;
      end = r.$2;
    });
    onQuery();
  }

  Future<void> pickDate({required bool isStart}) async {
    final initial = isStart ? start : end;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked == null || !mounted) return;
    setState(() {
      quickIndex = -1;
      if (isStart) {
        start = picked;
        if (end.isBefore(start)) end = start;
      } else {
        end = picked;
        if (start.isAfter(end)) start = end;
      }
    });
  }

  void onQuery();
}
