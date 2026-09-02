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
                          _stat('\u603b\u6ce8\u5355', _n(_summary['totalOrders'])),
                          _stat('\u603b\u6ce8\u989d', _n(_summary['totalBetAmount'])),
                          _stat('\u8fd4\u70b9\u5408\u8ba1', _n(_summary['totalRebate'])),
                        ],
                      ),
                      SizedBox(height: 14.h),
                      Row(
                        children: [
                          _stat('\u7ea2\u5229\u5408\u8ba1', _n(_summary['totalBonus'])),
                          _stat('\u6e38\u620f\u603b\u7ed3\u679c', _n(_summary['gameResult'])),
                          _stat('\u73a9\u5bb6\u603b\u7ed3\u679c', _n(_summary['playerResult'])),
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
                                  final issue =
                                      '${r['issueNo'] ?? r['issue_no'] ?? ''}';
                                  final play =
                                      '${r['playName'] ?? r['play_name'] ?? r['playCode'] ?? r['play_code'] ?? r['content'] ?? ''}';
                                  final amount = _n(r['amount'] ?? r['betAmount']);
                                  final status =
                                      '${r['status'] ?? r['result'] ?? ''}';
                                  final result = betStatusLabel(status);
                                  final ranks = parseDrawRanks(
                                    pickDrawRanks(r),
                                  );
                                  final sumGy = pickSumGy(r);
                                  final isWin = status.toUpperCase() == 'WIN';
                                  final isLose = status.toUpperCase() == 'LOSE';
                                  return BetLedgerRecordTile(
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
                                    subtitle: ranks.isEmpty &&
                                            status.toUpperCase() != 'PENDING'
                                        ? Text(
                                            '待同步开奖号码',
                                            style: TextStyle(
                                              fontSize: 10.sp,
                                              color: AppColors.textHint,
                                            ),
                                          )
                                        : null,
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
