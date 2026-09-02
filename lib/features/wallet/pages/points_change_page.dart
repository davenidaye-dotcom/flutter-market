import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../config/theme/app_colors.dart';
import '../../../data/repositories/providers.dart';
import '../../../shared/widgets/emulator_safe_text_field.dart';
import '../../../shared/widgets/gradient_background.dart';
import '../../../shared/widgets/page_app_bar.dart';
import '../widgets/date_range_filter.dart';
import '../utils/draw_snapshot_utils.dart';
import '../widgets/compact_draw_snapshot_row.dart';

/// Points change records
class PointsChangePage extends ConsumerStatefulWidget {
  const PointsChangePage({super.key});

  @override
  ConsumerState<PointsChangePage> createState() => _PointsChangePageState();
}

class _PointsChangePageState extends ConsumerState<PointsChangePage> {
  final _issueCtrl = TextEditingController();
  int _page = 1;
  int _totalPages = 0;
  int _totalCount = 0;
  bool _loading = false;
  List<Map<String, dynamic>> _rows = [];

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  @override
  void dispose() {
    _issueCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await ref.read(walletRepositoryProvider).getPointsChanges(
            issueNo: _issueCtrl.text.trim(),
            pageNum: _page,
            pageSize: 20,
          );
      final raw = data['rows'];
      final list = raw is List
          ? raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
          : <Map<String, dynamic>>[];
      final total = data['total'] is num ? (data['total'] as num).toInt() : list.length;
      final pageSize = data['pageSize'] is num ? (data['pageSize'] as num).toInt() : 20;
      if (!mounted) return;
      setState(() {
        _rows = list;
        _totalCount = total;
        _totalPages = pageSize <= 0 ? 0 : ((total + pageSize - 1) ~/ pageSize);
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
              PageAppBar(title: '\u79ef\u5206\u53d8\u66f4', onBack: () => appSafePop(context)),
              SizedBox(height: 8.h),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 12.w),
                child: Row(
                  children: [
                    Expanded(
                      child: Container(
                        height: 40.h,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8.r),
                        ),
                        child: EmulatorSafeTextField(
                          controller: _issueCtrl,
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 14.sp, color: AppColors.textPrimary),
                          decoration: InputDecoration(
                            hintText: '\u8bf7\u8f93\u5165\u671f\u53f7',
                            hintStyle: TextStyle(fontSize: 14.sp, color: AppColors.textHint),
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(horizontal: 12.w),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(width: 10.w),
                    GestureDetector(
                      onTap: () {
                        _page = 1;
                        _load();
                      },
                      child: Container(
                        padding: EdgeInsets.symmetric(horizontal: 18.w, vertical: 10.h),
                        decoration: BoxDecoration(
                          color: AppColors.navBlue,
                          borderRadius: BorderRadius.circular(20.r),
                        ),
                        child: Text(
                          '\u67e5\u8be2',
                          style: TextStyle(fontSize: 14.sp, color: Colors.white, fontWeight: FontWeight.w500),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: 12.h),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12.w),
                  child: ReportCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: EdgeInsets.fromLTRB(16.w, 14.h, 16.w, 10.h),
                          child: Text(
                            '\u5168\u90e8\u8bb0\u5f55',
                            style: TextStyle(fontSize: 14.sp, color: AppColors.textPrimary),
                          ),
                        ),
                        const Divider(height: 1, color: AppColors.divider),
                        Expanded(
                          child: _loading
                              ? const Center(child: CircularProgressIndicator())
                              : _rows.isEmpty
                                  ? Center(
                                      child: Text(
                                        '\u6682\u65e0\u6570\u636e',
                                        style: TextStyle(fontSize: 14.sp, color: AppColors.textHint),
                                      ),
                                    )
                                  : ListView.separated(
                                      itemCount: _rows.length,
                                      separatorBuilder: (_, _) =>
                                          const Divider(height: 1, color: AppColors.divider),
                                      itemBuilder: (_, i) {
                                        final r = _rows[i];
                                        final changeType =
                                            '${r['changeType'] ?? r['change_type'] ?? ''}';
                                        final label = ledgerChangeLabel(changeType);
                                        final amount = r['amount'] ?? r['points'];
                                        final amountNum = amount is num
                                            ? amount.toDouble()
                                            : double.tryParse('$amount') ?? 0;
                                        final amountText = amountNum >= 0
                                            ? '+${amountNum.toStringAsFixed(1)}'
                                            : amountNum.toStringAsFixed(1);
                                        final issue =
                                            '${r['issueNo'] ?? r['issue_no'] ?? ''}';
                                        final time =
                                            '${r['createdAt'] ?? r['createTime'] ?? ''}';
                                        final balance =
                                            '${r['balanceAfter'] ?? r['balance_after'] ?? ''}';
                                        final ranks = parseDrawRanks(
                                          pickDrawRanks(r),
                                        );
                                        final sumGy = pickSumGy(r);
                                        final amountColor = amountNum >= 0
                                            ? const Color(0xFFE53935)
                                            : AppColors.textPrimary;
                                        return BetLedgerRecordTile(
                                          drawRanks: ranks,
                                          sumGy: sumGy,
                                          topLine: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  Text(
                                                    label,
                                                    style: TextStyle(
                                                      fontSize: 13.sp,
                                                      fontWeight: FontWeight.w600,
                                                      color: AppColors.textPrimary,
                                                    ),
                                                  ),
                                                  const Spacer(),
                                                  Text(
                                                    amountText,
                                                    style: TextStyle(
                                                      fontSize: 14.sp,
                                                      fontWeight: FontWeight.w600,
                                                      color: amountColor,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              SizedBox(height: 4.h),
                                              Row(
                                                children: [
                                                  if (issue.isNotEmpty)
                                                    Text(
                                                      '第${issueTail(issue)}期',
                                                      style: TextStyle(
                                                        fontSize: 11.sp,
                                                        color: AppColors.textHint,
                                                      ),
                                                    ),
                                                  if (issue.isNotEmpty &&
                                                      time.isNotEmpty)
                                                    Text(
                                                      ' · ',
                                                      style: TextStyle(
                                                        fontSize: 11.sp,
                                                        color: AppColors.textHint,
                                                      ),
                                                    ),
                                                  if (time.isNotEmpty)
                                                    Expanded(
                                                      child: Text(
                                                        time,
                                                        maxLines: 1,
                                                        overflow:
                                                            TextOverflow.ellipsis,
                                                        style: TextStyle(
                                                          fontSize: 11.sp,
                                                          color:
                                                              AppColors.textHint,
                                                        ),
                                                      ),
                                                    ),
                                                  if (balance.isNotEmpty)
                                                    Text(
                                                      '余$balance',
                                                      style: TextStyle(
                                                        fontSize: 11.sp,
                                                        color:
                                                            AppColors.textSecondary,
                                                      ),
                                                    ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        );
                                      },
                                    ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Container(
                padding: EdgeInsets.fromLTRB(16.w, 10.h, 16.w, 12.h),
                child: Row(
                  children: [
                    Text(
                      '\u9875\u7801 $_page / $_totalPages  \u5171 $_totalCount \u6761',
                      style: TextStyle(fontSize: 13.sp, color: AppColors.textPrimary),
                    ),
                    const Spacer(),
                    _pageBtn('\u4e0a\u4e00\u9875', () {
                      if (_page > 1) {
                        setState(() => _page--);
                        _load();
                      }
                    }),
                    SizedBox(width: 8.w),
                    _pageBtn('\u4e0b\u4e00\u9875', () {
                      if (_totalPages == 0 || _page >= _totalPages) {
                        AppToast.info('\u5df2\u662f\u6700\u540e\u4e00\u9875');
                        return;
                      }
                      setState(() => _page++);
                      _load();
                    }),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _pageBtn(String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 8.h),
        decoration: BoxDecoration(
          color: AppColors.navBlue,
          borderRadius: BorderRadius.circular(6.r),
        ),
        child: Text(label, style: TextStyle(fontSize: 13.sp, color: Colors.white)),
      ),
    );
  }
}
