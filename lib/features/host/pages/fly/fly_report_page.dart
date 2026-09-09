import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../../config/theme/app_colors.dart';
import '../../../../data/repositories/providers.dart';
import '../../../../shared/widgets/page_app_bar.dart';
import '../../../wallet/widgets/date_range_filter.dart';
import '../../data/host_mock.dart';
import '../../widgets/host_ui.dart';

/// Feipan reports
class FlyReportPage extends ConsumerStatefulWidget {
  const FlyReportPage({super.key, required this.roomId});
  final String roomId;

  @override
  ConsumerState<FlyReportPage> createState() => _FlyReportPageState();
}

class _FlyReportPageState extends ConsumerState<FlyReportPage>
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
      final data = await ref.read(ownerRepositoryProvider).getFeipanReports(
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

  String _v(String k, {int fraction = 2}) {
    final s = _data['summary'];
    if (s is Map && s[k] != null) return hostNumStr(s[k], fraction: fraction);
    return fraction == 0 ? '0' : '0.00';
  }

  @override
  Widget build(BuildContext context) {
    final metrics = [
      ('笔数', _v('orderCount', fraction: 0)),
      ('下注', _v('betAmount')),
      ('输赢', _v('winLoss')),
      ('退水', _v('rebate')),
    ];
    return HostSubPageScaffold(
      title: '\u98de\u5355\u62a5\u8868',
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
                    padding: EdgeInsets.all(16.w),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisSpacing: 10.h,
                      crossAxisSpacing: 10.w,
                      childAspectRatio: 2.2,
                    ),
                    itemCount: metrics.length,
                    itemBuilder: (_, i) => HostWhiteCard(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(metrics[i].$1, style: TextStyle(fontSize: 12.sp, color: AppColors.textSecondary)),
                          Text(metrics[i].$2, style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.w700)),
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
