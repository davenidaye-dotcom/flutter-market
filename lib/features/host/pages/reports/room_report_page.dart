import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../../config/theme/app_colors.dart';
import '../../../../data/repositories/providers.dart';
import '../../../../shared/widgets/page_app_bar.dart';
import '../../../wallet/widgets/date_range_filter.dart';
import '../../data/host_mock.dart';
import '../../widgets/host_ui.dart';

/// Owner bet report
class RoomReportPage extends ConsumerStatefulWidget {
  const RoomReportPage({super.key, required this.roomId});

  final String roomId;

  @override
  ConsumerState<RoomReportPage> createState() => _RoomReportPageState();
}

class _RoomReportPageState extends ConsumerState<RoomReportPage> with DateRangePageMixin {
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
      final data = await ref.read(ownerRepositoryProvider).getBetReports(
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
      if (_data.containsKey(k) && _data[k] != null) return hostNumStr(_data[k], fraction: 2);
      final summary = _data['summary'];
      if (summary is Map && summary[k] != null) {
        return hostNumStr(summary[k], fraction: 2);
      }
    }
    return '0.00';
  }

  @override
  Widget build(BuildContext context) {
    final metrics = [
      ('\u6ce8\u5355\u6570', _v(['orderCount', 'totalOrders', 'betCount'])),
      ('\u6709\u6548\u6d41\u6c34', _v(['validTurnover', 'turnover', 'totalBetAmount'])),
      ('\u9ed8\u8ba4\u53cd\u6c34', _v(['defaultRebate', 'rebate', 'totalRebate'])),
      ('\u7279\u6b8a\u53cd\u6c34', _v(['specialRebate'])),
      ('\u7528\u6237\u8f93\u8d62', _v(['playerResult', 'userWinLoss'])),
      ('\u623f\u4e3b\u76c8\u4e8f', _v(['ownerProfitLoss', 'gameResult', 'profitLoss'])),
    ];
    return HostSubPageScaffold(
      title: '\u623f\u95f4\u62a5\u8868',
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
                : GridView.builder(
                    padding: EdgeInsets.symmetric(horizontal: 16.w),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisSpacing: 10.h,
                      crossAxisSpacing: 10.w,
                      childAspectRatio: 2.2,
                    ),
                    itemCount: metrics.length,
                    itemBuilder: (_, i) {
                      final m = metrics[i];
                      return HostWhiteCard(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(m.$1, style: TextStyle(fontSize: 12.sp, color: AppColors.textSecondary)),
                            SizedBox(height: 6.h),
                            Text(m.$2, style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.w700)),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
