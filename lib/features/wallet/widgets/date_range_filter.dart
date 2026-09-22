import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../config/theme/app_colors.dart';
import '../../../shared/utils/business_day.dart';

class DateRangeQuickItem {
  const DateRangeQuickItem({
    required this.label,
    required this.start,
    required this.end,
  });

  final String label;
  final DateTime start;
  final DateTime end;
}

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
    this.quickItems,
  });

  final int quickIndex;
  final DateTime start;
  final DateTime end;
  final ValueChanged<int> onQuickTap;
  final VoidCallback onPickStart;
  final VoidCallback onPickEnd;
  final VoidCallback onQuery;
  final List<DateRangeQuickItem>? quickItems;

  static String format(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// 按业务日生成快捷项（与房间/期数报表同一套日切规则）。
  /// 「今日」= 当前业务日，「昨日」= 上一业务日（日切前当前业务日仍是日历昨日）。
  static List<DateRangeQuickItem> buildQuickItems({DateTime? now}) {
    final n = now ?? DateTime.now();
    final biz = BusinessDay.of(n);
    final items = <DateRangeQuickItem>[];

    items.add(DateRangeQuickItem(label: '今日', start: biz, end: biz));
    final y = biz.subtract(const Duration(days: 1));
    items.add(DateRangeQuickItem(label: '昨日', start: y, end: y));

    // 上周
    final monday = biz.subtract(Duration(days: biz.weekday - 1));
    final lastMonday = monday.subtract(const Duration(days: 7));
    final lastSunday = monday.subtract(const Duration(days: 1));
    items.add(DateRangeQuickItem(label: '上周', start: lastMonday, end: lastSunday));

    // 本周
    items.add(DateRangeQuickItem(label: '本周', start: monday, end: biz));

    // 上月
    final firstThis = DateTime(biz.year, biz.month, 1);
    final lastMonthEnd = firstThis.subtract(const Duration(days: 1));
    final lastMonthStart = DateTime(lastMonthEnd.year, lastMonthEnd.month, 1);
    items.add(DateRangeQuickItem(
      label: '上月',
      start: lastMonthStart,
      end: lastMonthEnd,
    ));

    // 本月
    items.add(DateRangeQuickItem(
      label: '本月',
      start: DateTime(biz.year, biz.month, 1),
      end: biz,
    ));

    return items;
  }

  /// 兼容旧调用：当前业务日下的快捷标签列表。
  static List<String> get quickLabels =>
      buildQuickItems().map((e) => e.label).toList();

  /// 根据快捷项计算起止日期（含当天）
  static (DateTime, DateTime) rangeForQuick(int index, {DateTime? now}) {
    final items = buildQuickItems(now: now);
    if (index < 0 || index >= items.length) {
      final biz = BusinessDay.of(now ?? DateTime.now());
      return (biz, biz);
    }
    return (items[index].start, items[index].end);
  }

  @override
  Widget build(BuildContext context) {
    final items = quickItems ?? buildQuickItems();
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 12.w),
      child: Column(
        children: [
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
  List<DateRangeQuickItem> quickItems = DateRangeFilter.buildQuickItems();

  @override
  void initState() {
    super.initState();
    quickItems = DateRangeFilter.buildQuickItems();
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
