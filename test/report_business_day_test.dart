import 'package:flutter_test/flutter_test.dart';
import 'package:letou_app/features/host/pages/reports/report_date_bar.dart';
import 'package:letou_app/features/wallet/widgets/date_range_filter.dart';
import 'package:letou_app/shared/utils/business_day.dart';

void main() {
  group('BusinessDay', () {
    test('before 06:00 belongs to previous calendar day', () {
      final n = DateTime(2026, 9, 23, 5, 30);
      expect(BusinessDay.of(n), DateTime(2026, 9, 22));
    });

    test('06:00–08:00 maint still previous business day', () {
      final n = DateTime(2026, 9, 23, 7, 0);
      expect(BusinessDay.of(n), DateTime(2026, 9, 22));
    });

    test('after 08:00 is new business day', () {
      final n = DateTime(2026, 9, 23, 8, 0);
      expect(BusinessDay.of(n), DateTime(2026, 9, 23));
    });
  });

  group('ReportDateBar.buildQuickItems', () {
    test('before cut: 今日 = current biz day, 昨日 = prior', () {
      final items = ReportDateBar.buildQuickItems(
        now: DateTime(2026, 9, 23, 2, 0),
      );
      expect(items.first.label, '今日');
      expect(items[0].start, DateTime(2026, 9, 22));
      expect(items[1].label, '昨日');
      expect(items[1].start, DateTime(2026, 9, 21));
    });

    test('after open: 今日 = biz today, 昨日 = prior', () {
      final items = ReportDateBar.buildQuickItems(
        now: DateTime(2026, 9, 23, 10, 0),
      );
      expect(items.first.label, '今日');
      expect(items[0].start, DateTime(2026, 9, 23));
      expect(items[1].label, '昨日');
      expect(items[1].start, DateTime(2026, 9, 22));
    });
  });

  group('DateRangeFilter.buildQuickItems', () {
    test('always shows 今日 / 昨日 with business dates', () {
      final items = DateRangeFilter.buildQuickItems(
        now: DateTime(2026, 9, 23, 2, 0),
      );
      expect(items[0].label, '今日');
      expect(items[0].start, DateTime(2026, 9, 22));
      expect(items[1].label, '昨日');
      expect(items[1].start, DateTime(2026, 9, 21));
    });
  });
}
