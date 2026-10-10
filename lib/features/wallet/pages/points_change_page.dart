import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../config/theme/app_colors.dart';
import '../../../data/repositories/providers.dart';
import '../../../shared/format/display_number.dart';
import '../../../shared/widgets/emulator_safe_text_field.dart';
import '../../../shared/widgets/gradient_background.dart';
import '../../../shared/widgets/page_app_bar.dart';
import '../utils/draw_snapshot_utils.dart';
import '../widgets/member_ledger_card.dart';
import '../../../shared/widgets/app_page_loading.dart';
import '../../room/cs_share_helper.dart';

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
              PageAppBar(title: '积分变更', onBack: () => appSafePop(context)),
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
                            hintText: '请输入期号',
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
                          '查询',
                          style: TextStyle(fontSize: 14.sp, color: Colors.white, fontWeight: FontWeight.w500),
                        ),
                      ),
                    ),
                  ],
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
                            padding: EdgeInsets.fromLTRB(12.w, 0, 12.w, 12.h),
                            itemCount: _rows.length,
                            separatorBuilder: (_, _) => SizedBox(height: 10.h),
                            itemBuilder: (_, i) {
                              final r = _rows[i];
                              final changeType =
                                  '${r['changeType'] ?? r['change_type'] ?? ''}';
                              final issue =
                                  '${r['issueNo'] ?? r['issue_no'] ?? ''}';
                              final balanceRaw =
                                  r['balanceAfter'] ?? r['balance_after'];
                              final fields = <(String, String)>[];
                              if (balanceRaw != null &&
                                  '$balanceRaw'.trim().isNotEmpty) {
                                fields.add(
                                  ('变动后', displayNumber(balanceRaw)),
                                );
                              }
                              if (issue.isNotEmpty) {
                                fields.add(('期号', issue));
                              }
                              final ranks = parseDrawRanks(pickDrawRanks(r));
                              final ledgerId = '${r['id'] ?? ''}';
                              return MemberLedgerCard(
                                typeLabel: ledgerChangeLabel(changeType),
                                amount: r['amount'] ?? r['points'],
                                toneKey: changeType,
                                fields: fields,
                                remark: '${r['remark'] ?? ''}',
                                time:
                                    '${r['createdAt'] ?? r['createTime'] ?? ''}',
                                ranks: ranks,
                                sumGy: pickSumGy(r),
                                onShareToCs: ledgerId.isEmpty
                                    ? null
                                    : () => shareToCustomerService(
                                          context,
                                          ref,
                                          refType: 'POINT_LEDGER',
                                          refId: ledgerId,
                                          preview:
                                              '${ledgerChangeLabel(changeType)} #$ledgerId',
                                        ),
                              );
                            },
                          ),
              ),
              Container(
                padding: EdgeInsets.fromLTRB(16.w, 10.h, 16.w, 12.h),
                child: Row(
                  children: [
                    Text(
                      '页码 $_page / $_totalPages  共 $_totalCount 条',
                      style: TextStyle(fontSize: 13.sp, color: AppColors.textPrimary),
                    ),
                    const Spacer(),
                    _pageBtn('上一页', () {
                      if (_page > 1) {
                        setState(() => _page--);
                        _load();
                      }
                    }),
                    SizedBox(width: 8.w),
                    _pageBtn('下一页', () {
                      if (_totalPages == 0 || _page >= _totalPages) {
                        AppToast.info('已是最后一页');
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
