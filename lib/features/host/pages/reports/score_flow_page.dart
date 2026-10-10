import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../../config/theme/app_colors.dart';
import '../../../../data/repositories/providers.dart';
import '../../../../shared/widgets/page_app_bar.dart';
import '../../../wallet/widgets/date_range_filter.dart';
import '../../../wallet/utils/draw_snapshot_utils.dart';
import '../../data/host_mock.dart';
import '../../widgets/host_ui.dart';

/// 玩家申请的上分、下分。不含进房、下注、派彩。
class ScoreFlowPage extends ConsumerStatefulWidget {
  const ScoreFlowPage({super.key, required this.roomId});
  final String roomId;

  @override
  ConsumerState<ScoreFlowPage> createState() => _ScoreFlowPageState();
}

class _ScoreFlowPageState extends ConsumerState<ScoreFlowPage>
    with DateRangePageMixin {
  List<Map<String, dynamic>> _rows = [];
  String _summary = '';
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
      final rows = await ref.read(ownerRepositoryProvider).getUpDownApplications(
            startDate: DateRangeFilter.format(start),
            endDate: DateRangeFilter.format(end),
          );
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _summary = _summaryText(rows);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      AppToast.error(e.toString());
    }
  }

  String _summaryText(List<Map<String, dynamic>> rows) {
    double approved(String type) {
      var sum = 0.0;
      for (final row in rows) {
        if ('${row['changeType']}'.toUpperCase() != type) continue;
        if ('${row['status']}'.toUpperCase() != 'APPROVED') continue;
        final n = row['amount'];
        final v = n is num ? n.toDouble() : double.tryParse('$n') ?? 0;
        sum += v.abs();
      }
      return sum;
    }

    return '总上分 ${hostNumStr(approved('UP'), fraction: 2)}  总下分 ${hostNumStr(approved('DOWN'), fraction: 2)}';
  }

  @override
  Widget build(BuildContext context) {
    return HostSubPageScaffold(
      title: '\u4e0a\u4e0b\u5206\u8bb0\u5f55',
      body: Column(
        children: [
          SizedBox(height: 8.h),
          DateRangeFilter(
            quickIndex: quickIndex,
            start: start,
            end: end,
            quickItems: quickItems,
            onQuickTap: onQuickTap,
            onPickStart: () => pickDate(isStart: true),
            onPickEnd: () => pickDate(isStart: false),
            onQuery: onQuery,
          ),
          SizedBox(height: 12.h),
          if (_summary.isNotEmpty)
            Padding(
              padding: EdgeInsets.fromLTRB(16.w, 0, 16.w, 8.h),
              child: Text(
                _summary,
                style: TextStyle(fontSize: 12.sp, color: AppColors.textSecondary),
              ),
            ),
          Expanded(
            child: _loading
                ? const AppPageLoading()
                : _rows.isEmpty
                    ? Center(
                        child: Text(
                          '\u6682\u65e0\u6570\u636e',
                          style: TextStyle(fontSize: 14.sp, color: AppColors.textHint),
                        ),
                      )
                    : ListView.separated(
                        padding: EdgeInsets.symmetric(horizontal: 16.w),
                        itemCount: _rows.length,
                        separatorBuilder: (_, _) => SizedBox(height: 8.h),
                        itemBuilder: (_, i) {
                          final r = _rows[i];
                          final type = '${r['changeType'] ?? ''}';
                          final who = '${r['nickname'] ?? r['username'] ?? ''}'.trim();
                          final label = type.isEmpty ? '' : ledgerChangeLabel(type);
                          final title = [if (who.isNotEmpty) who, if (label.isNotEmpty) label].join(' ');
                          final status = '${r['status'] ?? ''}'.trim();
                          final signed = HostSignedPnl.of(r['amount']);
                          return HostWhiteCard(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  title.isEmpty ? '上下分' : title,
                                  style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600),
                                ),
                                SizedBox(height: 4.h),
                                Text(
                                  [
                                    if (status.isNotEmpty) applyStatusLabel(status),
                                    signed.text,
                                    '${r['createdAt'] ?? ''}',
                                  ].where((s) => s.trim().isNotEmpty).join('  '),
                                  style: TextStyle(fontSize: 12.sp, color: AppColors.textSecondary),
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
