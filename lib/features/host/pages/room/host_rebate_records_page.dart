import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../../config/theme/app_colors.dart';
import '../../../../data/repositories/providers.dart';
import '../../../../shared/widgets/page_app_bar.dart';
import '../../../wallet/widgets/date_range_filter.dart';
import '../../data/host_mock.dart';
import '../../widgets/host_ui.dart';

/// 彩票回水记录 — GET /owner/manage/welfare?type=COMMISSION
class HostRebateRecordsPage extends ConsumerStatefulWidget {
  const HostRebateRecordsPage({super.key, required this.roomId});

  final String roomId;

  @override
  ConsumerState<HostRebateRecordsPage> createState() => _HostRebateRecordsPageState();
}

class _HostRebateRecordsPageState extends ConsumerState<HostRebateRecordsPage>
    with DateRangePageMixin {
  List<Map<String, dynamic>> _rows = [];
  String _total = '0.00';
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
      final detail = data['detail'];
      final rows = <Map<String, dynamic>>[];
      if (detail is List) {
        for (final e in detail) {
          if (e is! Map) continue;
          final m = Map<String, dynamic>.from(e);
          // 文档：本页只要回水，看 changeType=REBATE
          final ct = '${m['changeType'] ?? ''}'.toUpperCase();
          if (ct.isNotEmpty && ct != 'REBATE' && ct != 'COMMISSION') continue;
          rows.add(m);
        }
      }
      setState(() {
        _total = hostNumStr(data['commissionRebate'], fraction: 2);
        _rows = rows;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      AppToast.error(e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return HostSubPageScaffold(
      title: '彩票回水记录',
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
          Padding(
            padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '合计 $_total',
                style: TextStyle(fontSize: 13.sp, color: AppColors.textSecondary),
              ),
            ),
          ),
          SizedBox(height: 8.h),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _rows.isEmpty
                    ? Center(
                        child: Text('暂无回水记录', style: TextStyle(fontSize: 14.sp, color: AppColors.textHint)),
                      )
                    : ListView.separated(
                        padding: EdgeInsets.fromLTRB(16.w, 0, 16.w, 16.h),
                        itemCount: _rows.length,
                        separatorBuilder: (_, _) => SizedBox(height: 8.h),
                        itemBuilder: (_, i) {
                          final r = _rows[i];
                          final who = '${r['accountId'] ?? ''}'.trim();
                          final remark = '${r['remark'] ?? ''}'.trim();
                          return HostWhiteCard(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  remark.isEmpty ? '回水' : remark,
                                  style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w700),
                                ),
                                SizedBox(height: 4.h),
                                Text(
                                  '${hostNumStr(r['amount'], fraction: 2)}   ${r['createdAt'] ?? ''}',
                                  style: TextStyle(fontSize: 12.sp, color: AppColors.textSecondary),
                                ),
                                if (who.isNotEmpty)
                                  Text(
                                    '账号 $who',
                                    style: TextStyle(fontSize: 12.sp, color: AppColors.textHint),
                                  ),
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
