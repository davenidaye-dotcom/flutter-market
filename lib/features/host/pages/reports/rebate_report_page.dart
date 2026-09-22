import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../../config/theme/app_colors.dart';
import '../../../../data/repositories/providers.dart';
import '../../../../shared/widgets/page_app_bar.dart';
import '../../../wallet/widgets/date_range_filter.dart';
import '../../data/host_mock.dart';
import '../../widgets/host_ui.dart';

/// Welfare report — GET /owner/manage/welfare
class RebateReportPage extends ConsumerStatefulWidget {
  const RebateReportPage({super.key, required this.roomId});
  final String roomId;

  @override
  ConsumerState<RebateReportPage> createState() => _RebateReportPageState();
}

class _RebateReportPageState extends ConsumerState<RebateReportPage>
    with DateRangePageMixin {
  Map<String, dynamic> _data = {};
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  @override
  void onQuery() => _load();

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await ref.read(ownerRepositoryProvider).getWelfare(
            type: 'SUMMARY',
            startDate: DateRangeFilter.format(start),
            endDate: DateRangeFilter.format(end),
          );
      if (!mounted) return;
      setState(() {
        _data = data;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      AppToast.error(e.toString());
    }
  }

  String _v(List<String> keys) {
    for (final k in keys) {
      if (_data[k] != null) return hostNumStr(_data[k], fraction: 2);
      final s = _data['summary'];
      if (s is Map && s[k] != null) return hostNumStr(s[k], fraction: 2);
    }
    return '0.00';
  }

  @override
  Widget build(BuildContext context) {
    final metrics = [
      ('回水入账', _v(['commissionRebate'])),
      ('红包', _v(['redpack'])),
      ('合计', _v(['total', 'totalRebate'])),
      ('个人比例', _v(['rebateRatio'])),
    ];
    return HostSubPageScaffold(
      title: '回水报表',
      body: Column(
        children: [
          SizedBox(height: 8.h),
          DateRangeFilter(
            quickIndex: quickIndex,
            start: start,
            end: end,
            onQuickTap: onQuickTap,
            onPickStart: () => pickDate(isStart: true),
            onPickEnd: () => pickDate(isStart: false),
            onQuery: onQuery,
          ),
          SizedBox(height: 12.h),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16.w),
                    child: ReportCard(
                      child: Column(
                        children: [
                          for (var i = 0; i < metrics.length; i++) ...[
                            Padding(
                              padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 16.h),
                              child: Row(
                                children: [
                                  Text(metrics[i].$1, style: TextStyle(fontSize: 15.sp)),
                                  const Spacer(),
                                  Text(
                                    metrics[i].$2,
                                    style: TextStyle(
                                      fontSize: 15.sp,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (i < metrics.length - 1)
                              const Divider(height: 1, color: AppColors.divider),
                          ],
                        ],
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
