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

/// 玩家信息报表深链。路径不变，只加 accountId。每页 20 条，不扫全房。
class HostMemberReportPage extends ConsumerStatefulWidget {
  const HostMemberReportPage({
    super.key,
    required this.roomId,
    required this.accountId,
    required this.kind,
  });

  final String roomId;
  final String accountId;
  /// credits | updown | bets | welfare | redpacks
  final String kind;

  @override
  ConsumerState<HostMemberReportPage> createState() => _HostMemberReportPageState();
}

class _HostMemberReportPageState extends ConsumerState<HostMemberReportPage>
    with DateRangePageMixin {
  List<Map<String, dynamic>> _rows = [];
  String _summary = '';
  bool _loading = false;

  String get _title => switch (widget.kind) {
        'updown' => '上下分记录',
        'bets' => '竞猜记录',
        'welfare' => '福利报表',
        'redpacks' => '红包报表',
        _ => '积分账变',
      };

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
      final repo = ref.read(ownerRepositoryProvider);
      final start = DateRangeFilter.format(this.start);
      final end = DateRangeFilter.format(this.end);
      final id = widget.accountId;
      late final Map<String, dynamic> data;
      switch (widget.kind) {
        case 'updown':
          data = await repo.getCreditRecords(
            startDate: start,
            endDate: end,
            accountId: id,
            direction: 'ALL',
          );
        case 'bets':
          data = await repo.getManageBets(
            startDate: start,
            endDate: end,
            accountId: id,
          );
        case 'welfare':
          data = await repo.getWelfare(
            type: 'SUMMARY',
            startDate: start,
            endDate: end,
            accountId: id,
          );
        case 'redpacks':
          data = await repo.listRedpacks(accountId: id);
        default:
          data = await repo.getCreditRecords(
            startDate: start,
            endDate: end,
            accountId: id,
          );
      }
      if (!mounted) return;
      final rows = widget.kind == 'welfare'
          ? hostRowsOf({'rows': data['detail']})
          : hostRowsOf(data);
      final summary = data['summary'];
      setState(() {
        _rows = rows;
        _summary = summary is Map ? _summaryText(Map<String, dynamic>.from(summary)) : '';
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      AppToast.error(e.toString());
    }
  }

  String _summaryText(Map<String, dynamic> s) {
    if (s.isEmpty) return '';
    const order = [
      'totalUp',
      'totalDown',
      'totalBet',
      'totalTurnover',
      'totalBonus',
      'totalWinLoss',
      'totalRebate',
      'totalOrders',
      'totalBalance',
    ];
    final parts = <String>[];
    final used = <String>{};
    for (final key in order) {
      if (s[key] == null) continue;
      used.add(key);
      parts.add('${ledgerChangeLabel(key)} ${hostNumStr(s[key], fraction: 2)}');
    }
    for (final e in s.entries) {
      if (used.contains(e.key) || e.key == 'rows') continue;
      parts.add('${ledgerChangeLabel(e.key)} ${hostNumStr(e.value, fraction: 2)}');
    }
    return parts.join('  ');
  }

  @override
  Widget build(BuildContext context) {
    return HostSubPageScaffold(
      title: _title,
      body: Column(
        children: [
          SizedBox(height: 8.h),
          if (widget.kind != 'redpacks')
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
          if (_summary.isNotEmpty)
            Padding(
              padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 0),
              child: Text(
                _summary,
                style: TextStyle(fontSize: 12.sp, color: AppColors.textSecondary),
              ),
            ),
          SizedBox(height: 12.h),
          Expanded(
            child: _loading
                ? const AppPageLoading()
                : _rows.isEmpty
                    ? Center(
                        child: Text(
                          '暂无数据',
                          style: TextStyle(fontSize: 14.sp, color: AppColors.textHint),
                        ),
                      )
                    : ListView.separated(
                        padding: EdgeInsets.fromLTRB(16.w, 0, 16.w, 16.h),
                        itemCount: _rows.length,
                        separatorBuilder: (_, _) => SizedBox(height: 8.h),
                        itemBuilder: (_, i) {
                          final r = _rows[i];
                          final type = '${r['changeType'] ?? r['type'] ?? ''}';
                          final issue = '${r['issueNo'] ?? ''}'.trim();
                          final typeLabel = type.isEmpty ? '' : ledgerChangeLabel(type);
                          final title = [
                            if (issue.isNotEmpty) '$issue期',
                            if (typeLabel.isNotEmpty) typeLabel,
                          ].join(' ');
                          final amount = hostNumStr(
                            r['amount'] ?? r['totalAmount'] ?? r['winAmount'] ?? '',
                            fraction: 2,
                          );
                          final time = r['createdAt'] ?? r['settledAt'] ?? '';
                          return HostWhiteCard(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  title.isEmpty
                                      ? '${r['orderId'] ?? r['claimId'] ?? ''}'
                                      : title,
                                  style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600),
                                ),
                                SizedBox(height: 4.h),
                                Text(
                                  '$amount  $time',
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
