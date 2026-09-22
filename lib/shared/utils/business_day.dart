/// 与后端 [BusinessDay] 对齐（默认日切 06:00，维护 06:00–08:00）。
/// 业务日 = 当日维护结束(08:00) → 次日日切(06:00)。
abstract final class BusinessDay {
  static const int dayCutHour = 6;
  static const int maintEndHour = 8;

  /// 当前时刻所属业务日（纯日期，无时分）。
  static DateTime of(DateTime n) {
    final cal = DateTime(n.year, n.month, n.day);
    final minutes = n.hour * 60 + n.minute;
    final dayCut = dayCutHour * 60;
    final maintStart = dayCutHour * 60;
    final maintEnd = maintEndHour * 60;
    final inMaint = minutes >= maintStart && minutes < maintEnd;
    if (minutes < dayCut || inMaint) {
      return cal.subtract(const Duration(days: 1));
    }
    return cal;
  }

  /// 是否已进入「日历今日」对应的新业务日（过维护结束后才为 true）。
  /// 报表芯片始终展示「今日」= [of]；此方法仅供需要区分日历日的场景。
  static bool showTodayChip(DateTime n) {
    final biz = of(n);
    final cal = DateTime(n.year, n.month, n.day);
    return biz.year == cal.year && biz.month == cal.month && biz.day == cal.day;
  }
}
