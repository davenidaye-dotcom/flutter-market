import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../config/theme/app_colors.dart';
import '../../../data/repositories/providers.dart';
import '../../../shared/widgets/app_empty_hint.dart';
import '../../../shared/widgets/emulator_safe_text_field.dart';
import '../../../shared/widgets/gradient_background.dart';
import '../../../shared/widgets/page_app_bar.dart';
import '../widgets/date_range_filter.dart';
import '../utils/draw_snapshot_utils.dart';
import '../widgets/compact_draw_snapshot_row.dart';

/// \u7ade\u731c\u8bb0\u5f55
class BetRecordsPage extends ConsumerStatefulWidget {
  const BetRecordsPage({super.key});

  @override
  ConsumerState<BetRecordsPage> createState() => _BetRecordsPageState();
}

class _BetRecordsPageState extends ConsumerState<BetRecordsPage>
    with DateRangePageMixin {
  Map<String, dynamic> _summary = {};
  List<Map<String, dynamic>> _rows = [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  @override
  void onQuery() {
    _load();
  }

  String _n(dynamic v) {
    if (v == null) return '0.0';
    if (v is num) return v.toStringAsFixed(1);
    return double.tryParse('$v')?.toStringAsFixed(1) ?? '$v';
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await ref.read(walletRepositoryProvider).getBets(
            startDate: DateRangeFilter.format(start),
            endDate: DateRangeFilter.format(end),
          );
      final summary = data['summary'];
      final raw = data['rows'];
      if (!mounted) return;
      setState(() {
        _summary = summary is Map
            ? Map<String, dynamic>.from(summary)
            : <String, dynamic>{};
        _rows = raw is List
            ? raw
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList()
            : [];
      });
    } catch (e) {
      if (!mounted) return;
      AppToast.error(e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _openIssueDetail(String issue) {
    final same = _rows.where((r) => '${r['issueNo'] ?? ''}' == issue).toList();
    // 展开每单 items[]；无 items 时保留订单摘要行
    final lines = <Map<String, dynamic>>[];
    for (final r in same) {
      final items = r['items'];
      if (items is List && items.isNotEmpty) {
        for (final raw in items) {
          if (raw is! Map) continue;
          lines.add({
            'playName': raw['playName'] ?? raw['playCode'] ?? '',
            'amount': raw['amount'] ?? raw['winAmount'],
            'status': raw['status'] ?? r['status'],
            'orderId': r['orderId'],
          });
        }
      } else {
        lines.add({
          'playName': r['playName'] ?? r['playCode'] ?? '注单${r['itemCount'] ?? ''}',
          'amount': r['totalAmount'] ?? r['amount'],
          'status': r['status'],
          'orderId': r['orderId'],
        });
      }
    }
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 16.h),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '第$issue期注单',
                  style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w700),
                ),
                SizedBox(height: 8.h),
                Text(
                  '共 ${same.length} 笔 / ${lines.length} 条玩法',
                  style: TextStyle(fontSize: 12.sp, color: AppColors.textSecondary),
                ),
                SizedBox(height: 8.h),
                SizedBox(
                  height: lines.length > 8 ? 360.h : null,
                  child: ListView.separated(
                    shrinkWrap: lines.length <= 8,
                    itemCount: lines.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final r = lines[i];
                      final play = '${r['playName'] ?? ''}';
                      final status = '${r['status'] ?? ''}';
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(play.isEmpty ? '注单' : play),
                        subtitle: Text('金额 ${_n(r['amount'])}'),
                        trailing: Text(
                          betStatusLabel(status),
                          style: TextStyle(
                            color: status.toUpperCase() == 'WIN'
                                ? const Color(0xFFE53935)
                                : AppColors.textSecondary,
                          ),
                        ),
                        onTap: () async {
                          final oid = '${r['orderId'] ?? ''}';
                          if (oid.isEmpty) return;
                          try {
                            final detail = await ref
                                .read(walletRepositoryProvider)
                                .getBetDetail(oid);
                            if (!ctx.mounted) return;
                            final its = detail['items'];
                            final detailLines = its is List
                                ? its
                                    .whereType<Map>()
                                    .map((e) =>
                                        '${e['playName'] ?? e['playCode']}  ${e['amount']}  ${betStatusLabel('${e['status'] ?? ''}')}')
                                    .join('\n')
                                : '';
                            await showDialog<void>(
                              context: ctx,
                              builder: (dctx) => AlertDialog(
                                title: Text('注单 $oid'),
                                content: Text(
                                  detailLines.isEmpty
                                      ? '金额 ${_n(detail['totalAmount'])}  状态 ${betStatusLabel('${detail['status'] ?? ''}')}'
                                      : detailLines,
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(dctx),
                                    child: const Text('关闭'),
                                  ),
                                ],
                              ),
                            );
                          } catch (e) {
                            AppToast.error(e.toString());
                          }
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppPageScaffold(
      body: GradientBackground(
        child: SafeArea(
          child: Column(
            children: [
              PageAppBar(
                title: '\u7ade\u731c\u8bb0\u5f55',
                onBack: () => appSafePop(context),
              ),
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
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 12.w),
                child: ReportCard(
                  padding: EdgeInsets.symmetric(vertical: 16.h, horizontal: 8.w),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          _stat('总注单', _n(_summary['totalOrders'])),
                          _stat('总注额', _n(_summary['totalBetAmount'])),
                          _stat('返点合计', _n(_summary['totalRebate'])),
                        ],
                      ),
                      SizedBox(height: 14.h),
                      Row(
                        children: [
                          _stat('派彩合计', _n(_summary['totalBonus'])),
                          // 文档 2.2：当前实现主要填 totalOrders / totalBetAmount
                          _stat('已结输赢', _n(_summary['totalWinLoss'] ?? _summary['winLoss'])),
                          _stat('笔数', _n(_summary['totalOrders'])),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(height: 12.h),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12.w),
                  child: ReportCard(
                    child: _loading
                        ? const Center(child: CircularProgressIndicator())
                        : _rows.isEmpty
                            ? const Center(child: AppEmptyHint())
                            : ListView.separated(
                                padding: EdgeInsets.symmetric(
                                  horizontal: 12.w,
                                  vertical: 8.h,
                                ),
                                itemCount: _rows.length,
                                separatorBuilder: (_, _) =>
                                    const Divider(height: 1, color: AppColors.divider),
                                itemBuilder: (_, i) {
                                  final r = _rows[i];
                                  final issue = '${r['issueNo'] ?? ''}';
                                  final play =
                                      '${r['playName'] ?? r['playCode'] ?? ''}';
                                  final amount = _n(r['amount']);
                                  final status = '${r['status'] ?? ''}';
                                  final result = betStatusLabel(status);
                                  final flight = '${r['flightStatus'] ?? ''}';
                                  final flightLabel = switch (flight.toUpperCase()) {
                                    'SUCCESS' => '飞单成功',
                                    'FAILED' => '飞单失败',
                                    'NONE' => '',
                                    '' => '',
                                    _ => flight,
                                  };
                                  final ranks = parseDrawRanks(
                                    pickDrawRanks(r),
                                  );
                                  final sumGy = pickSumGy(r);
                                  final isWin = status.toUpperCase() == 'WIN';
                                  final isLose = status.toUpperCase() == 'LOSE';
                                  return BetLedgerRecordTile(
                                    onTap: () => _openIssueDetail(issue),
                                    drawRanks: ranks,
                                    sumGy: sumGy,
                                    topLine: Row(
                                      children: [
                                        SizedBox(
                                          width: 44.w,
                                          child: Text(
                                            issueTail(issue),
                                            style: TextStyle(
                                              fontSize: 12.sp,
                                              color: AppColors.textPrimary,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                        Expanded(
                                          child: Text(
                                            play,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 12.sp,
                                              color: AppColors.textPrimary,
                                            ),
                                          ),
                                        ),
                                        Text(
                                          amount,
                                          style: TextStyle(
                                            fontSize: 12.sp,
                                            color: AppColors.textPrimary,
                                          ),
                                        ),
                                        SizedBox(width: 8.w),
                                        SizedBox(
                                          width: 36.w,
                                          child: Text(
                                            result,
                                            textAlign: TextAlign.right,
                                            style: TextStyle(
                                              fontSize: 11.sp,
                                              fontWeight: FontWeight.w600,
                                              color: isWin
                                                  ? const Color(0xFFE53935)
                                                  : isLose
                                                      ? AppColors.textSecondary
                                                      : AppColors.textHint,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    subtitle: () {
                                      final parts = <String>[
                                        if (flightLabel.isNotEmpty) flightLabel,
                                        if (ranks.isEmpty &&
                                            status.toUpperCase() != 'PENDING')
                                          '待同步开奖号码',
                                      ];
                                      if (parts.isEmpty) return null;
                                      return Text(
                                        parts.join(' · '),
                                        style: TextStyle(
                                          fontSize: 10.sp,
                                          color: flight.toUpperCase() == 'FAILED'
                                              ? AppColors.textHint
                                              : AppColors.textSecondary,
                                        ),
                                      );
                                    }(),
                                  );
                                },
                              ),
                  ),
                ),
              ),
              SizedBox(height: 12.h),
            ],
          ),
        ),
      ),
    );
  }

  Widget _stat(String label, String value) {
    return Expanded(
      child: Column(
        children: [
          Text(label, style: TextStyle(fontSize: 12.sp, color: AppColors.textSecondary)),
          SizedBox(height: 6.h),
          Text(
            value,
            style: TextStyle(
              fontSize: 15.sp,
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
