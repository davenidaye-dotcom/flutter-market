import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../../config/theme/app_colors.dart';

/// 房间报表 / 期数报表：自定义时间范围 + 快捷芯片（含「全部」）
class ReportDateBar extends StatelessWidget {
  const ReportDateBar({
    super.key,
    required this.quickIndex,
    required this.start,
    required this.end,
    required this.onQuickTap,
    required this.onCustomTap,
  });

  /// -1 = 自定义；0..6 = 快捷项
  final int quickIndex;
  final DateTime start;
  final DateTime end;
  final ValueChanged<int> onQuickTap;
  final VoidCallback onCustomTap;

  static const quickLabels = ['今日', '昨日', '本周', '上周', '本月', '上个月', '全部'];

  static String format(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static (DateTime, DateTime) rangeForQuick(int index, {DateTime? now}) {
    final n = now ?? DateTime.now();
    final today = DateTime(n.year, n.month, n.day);
    switch (index) {
      case 1: // 昨日
        final y = today.subtract(const Duration(days: 1));
        return (y, y);
      case 2: // 本周
        final monday = today.subtract(Duration(days: today.weekday - 1));
        return (monday, today);
      case 3: // 上周
        final thisMonday = today.subtract(Duration(days: today.weekday - 1));
        final lastMonday = thisMonday.subtract(const Duration(days: 7));
        final lastSunday = thisMonday.subtract(const Duration(days: 1));
        return (lastMonday, lastSunday);
      case 4: // 本月
        return (DateTime(today.year, today.month, 1), today);
      case 5: // 上个月
        final firstThis = DateTime(today.year, today.month, 1);
        final lastMonthEnd = firstThis.subtract(const Duration(days: 1));
        final lastMonthStart = DateTime(lastMonthEnd.year, lastMonthEnd.month, 1);
        return (lastMonthStart, lastMonthEnd);
      case 6: // 全部
        return (DateTime(2020, 1, 1), today);
      case 0:
      default:
        return (today, today);
    }
  }

  String get _customLabel {
    if (quickIndex >= 0) return '自定义时间范围';
    return '${format(start)} 至 ${format(end)}';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16.w),
      child: Column(
        children: [
          Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10.r),
            child: InkWell(
              onTap: onCustomTap,
              borderRadius: BorderRadius.circular(10.r),
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 12.h),
                child: Row(
                  children: [
                    Icon(Icons.calendar_month_outlined, size: 18.sp, color: AppColors.textSecondary),
                    SizedBox(width: 8.w),
                    Expanded(
                      child: Text(
                        _customLabel,
                        style: TextStyle(fontSize: 14.sp, color: AppColors.textPrimary),
                      ),
                    ),
                    Icon(Icons.chevron_right, size: 20.sp, color: AppColors.textHint),
                  ],
                ),
              ),
            ),
          ),
          SizedBox(height: 10.h),
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
          color: active ? AppColors.navBlue : Colors.transparent,
          borderRadius: BorderRadius.circular(16.r),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13.sp,
            color: active ? Colors.white : AppColors.textPrimary,
            fontWeight: active ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

mixin ReportDatePageMixin<T extends StatefulWidget> on State<T> {
  int quickIndex = 0;
  late DateTime start;
  late DateTime end;

  /// 快捷「全部」：接口不传 startDate/endDate
  bool get omitDates => quickIndex == 6;

  String? get apiStartDate => omitDates ? null : ReportDateBar.format(start);
  String? get apiEndDate => omitDates ? null : ReportDateBar.format(end);

  @override
  void initState() {
    super.initState();
    final r = ReportDateBar.rangeForQuick(0);
    start = r.$1;
    end = r.$2;
  }

  void onQuickTap(int i) {
    final r = ReportDateBar.rangeForQuick(i);
    setState(() {
      quickIndex = i;
      start = r.$1;
      end = r.$2;
    });
    onReportQuery();
  }

  Future<void> pickCustomRange() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: DateTimeRange(start: start, end: end),
      helpText: '自定义时间范围',
      cancelText: '取消',
      confirmText: '确定',
    );
    if (range == null || !mounted) return;
    setState(() {
      quickIndex = -1;
      start = DateTime(range.start.year, range.start.month, range.start.day);
      end = DateTime(range.end.year, range.end.month, range.end.day);
    });
    onReportQuery();
  }

  void onReportQuery();
}
