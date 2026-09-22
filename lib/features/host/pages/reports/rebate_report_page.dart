import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../../data/repositories/providers.dart';
import '../../../../shared/widgets/page_app_bar.dart';
import '../../../wallet/widgets/date_range_filter.dart';
import '../../data/host_mock.dart';
import '../../widgets/host_ui.dart';

/// 彩票回水报表 — GET /owner/manage/welfare?type=COMMISSION
/// 主指标：commissionRebate（历史字段名，当回水入账合计）
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
            type: 'COMMISSION',
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

  String _rebateTotal() {
    final v = _data['commissionRebate'] ?? _data['total'];
    return hostNumStr(v, fraction: 2);
  }

  @override
  Widget build(BuildContext context) {
    return HostSubPageScaffold(
      title: '彩票回水报表',
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
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 16.h),
                        child: Row(
                          children: [
                            Text('回水入账合计', style: TextStyle(fontSize: 15.sp)),
                            const Spacer(),
                            Text(
                              _rebateTotal(),
                              style: TextStyle(
                                fontSize: 15.sp,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
