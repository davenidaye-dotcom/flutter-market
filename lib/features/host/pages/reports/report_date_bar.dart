import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../../config/theme/app_colors.dart';
import '../../../../shared/utils/business_day.dart';

class ReportQuickItem {
  const ReportQuickItem({
    required this.label,
    required this.start,
    required this.end,
    this.omitDates = false,
  });

  final String label;
  final DateTime start;
  final DateTime end;
  final bool omitDates;
}

/// 房间报表 / 期数报表：自定义时间范围 + 快捷芯片（含「全部」）
class ReportDateBar extends StatelessWidget {
  const ReportDateBar({
    super.key,
    required this.quickIndex,
    required this.start,
    required this.end,
    required this.onQuickTap,
    required this.onCustomTap,
    this.quickItems,
  });

  /// -1 = 自定义；>=0 = [quickItems] 下标
  final int quickIndex;
  final DateTime start;
  final DateTime end;
  final ValueChanged<int> onQuickTap;
  final VoidCallback onCustomTap;
  final List<ReportQuickItem>? quickItems;

  static String format(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// 按业务日生成快捷项。
  /// 「今日」= 当前业务日，「昨日」= 上一业务日（日切前当前业务日仍是日历昨日）。
  static List<ReportQuickItem> buildQuickItems({DateTime? now}) {
    final n = now ?? DateTime.now();
    final biz = BusinessDay.of(n);
    final items = <ReportQuickItem>[];

    items.add(ReportQuickItem(label: '今日', start: biz, end: biz));
    final y = biz.subtract(const Duration(days: 1));
    items.add(ReportQuickItem(label: '昨日', start: y, end: y));

    // 本周（业务日所在自然周周一 → 业务日）
    final monday = biz.subtract(Duration(days: biz.weekday - 1));
    items.add(ReportQuickItem(label: '本周', start: monday, end: biz));

    // 上周
    final thisMonday = monday;
    final lastMonday = thisMonday.subtract(const Duration(days: 7));
    final lastSunday = thisMonday.subtract(const Duration(days: 1));
    items.add(ReportQuickItem(label: '上周', start: lastMonday, end: lastSunday));

    // 本月
    items.add(ReportQuickItem(
      label: '本月',
      start: DateTime(biz.year, biz.month, 1),
      end: biz,
    ));

    // 上个月
    final firstThis = DateTime(biz.year, biz.month, 1);
    final lastMonthEnd = firstThis.subtract(const Duration(days: 1));
    final lastMonthStart = DateTime(lastMonthEnd.year, lastMonthEnd.month, 1);
    items.add(ReportQuickItem(
      label: '上个月',
      start: lastMonthStart,
      end: lastMonthEnd,
    ));

    items.add(ReportQuickItem(
      label: '全部',
      start: DateTime(2020, 1, 1),
      end: biz,
      omitDates: true,
    ));
    return items;
  }

  @Deprecated('Use buildQuickItems')
  static (DateTime, DateTime) rangeForQuick(int index, {DateTime? now}) {
    final items = buildQuickItems(now: now);
    if (index < 0 || index >= items.length) {
      final biz = BusinessDay.of(now ?? DateTime.now());
      return (biz, biz);
    }
    final it = items[index];
    return (it.start, it.end);
  }

  String get _customLabel {
    if (quickIndex >= 0) return '自定义时间范围';
    return '${format(start)} 至 ${format(end)}';
  }

  @override
  Widget build(BuildContext context) {
    final items = quickItems ?? buildQuickItems();
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
                    Icon(Icons.calendar_month_outlined,
                        size: 18.sp, color: AppColors.textSecondary),
                    SizedBox(width: 8.w),
                    Expanded(
                      child: Text(
                        _customLabel,
                        style: TextStyle(
                            fontSize: 14.sp, color: AppColors.textPrimary),
                      ),
                    ),
                    Icon(Icons.chevron_right,
                        size: 20.sp, color: AppColors.textHint),
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
                for (var i = 0; i < items.length; i++) ...[
                  if (i > 0) SizedBox(width: 8.w),
                  _Chip(
                    label: items[i].label,
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
  List<ReportQuickItem> quickItems = ReportDateBar.buildQuickItems();

  bool get omitDates =>
      quickIndex >= 0 &&
      quickIndex < quickItems.length &&
      quickItems[quickIndex].omitDates;

  String? get apiStartDate => omitDates ? null : ReportDateBar.format(start);
  String? get apiEndDate => omitDates ? null : ReportDateBar.format(end);

  @override
  void initState() {
    super.initState();
    _applyDefaultQuick();
  }

  void _applyDefaultQuick() {
    quickItems = ReportDateBar.buildQuickItems();
    quickIndex = 0;
    start = quickItems[0].start;
    end = quickItems[0].end;
  }

  void onQuickTap(int i) {
    if (i < 0 || i >= quickItems.length) return;
    final it = quickItems[i];
    setState(() {
      quickIndex = i;
      start = it.start;
      end = it.end;
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
