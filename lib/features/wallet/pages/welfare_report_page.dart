import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../config/theme/app_colors.dart';
import '../../../data/repositories/providers.dart';
import '../../../shared/format/display_number.dart';
import '../../../shared/widgets/app_empty_hint.dart';
import '../../../shared/widgets/emulator_safe_text_field.dart';
import '../../../shared/widgets/gradient_background.dart';
import '../../../shared/widgets/page_app_bar.dart';
import '../utils/draw_snapshot_utils.dart';
import '../widgets/date_range_filter.dart';
import '../widgets/member_ledger_card.dart';
import '../../../shared/widgets/app_page_loading.dart';
import '../../room/cs_share_helper.dart';
import 'member_bet_report_shared.dart';

/// Welfare — GET /member/welfare
class WelfareReportPage extends ConsumerStatefulWidget {
  const WelfareReportPage({super.key});

  @override
  ConsumerState<WelfareReportPage> createState() => _WelfareReportPageState();
}

class _WelfareReportPageState extends ConsumerState<WelfareReportPage>
    with DateRangePageMixin {
  Map<String, dynamic> _data = {};
  bool _loading = false;
  String _type = 'COMMISSION';

  static const _chips = <(String, String)>[
    ('COMMISSION', '回水'),
    ('AGENT_REBATE', '代理抽佣'),
  ];

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
      final data = await ref.read(walletRepositoryProvider).getWelfare(
            type: _type,
            startDate: DateRangeFilter.format(start),
            endDate: DateRangeFilter.format(end),
          );
      if (!mounted) return;
      setState(() => _data = data);
    } catch (e) {
      if (!mounted) return;
      AppToast.error(e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  dynamic _pick(String key) {
    final v = _data[key];
    if (v != null) return v;
    final s = _data['summary'];
    if (s is Map && s[key] != null) return s[key];
    return 0;
  }

  List<Map<String, dynamic>> get _detail {
    final raw = _data['detail'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  String _detailTypeLabel(String changeType) => ledgerChangeLabel(changeType);

  @override
  Widget build(BuildContext context) {
    final detail = _detail;
    return AppPageScaffold(
      body: GradientBackground(
        child: SafeArea(
          child: Column(
            children: [
              PageAppBar(title: '福利报表', onBack: () => appSafePop(context)),
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
              Expanded(
                child: _loading
                    ? const AppPageLoading()
                    : ListView(
                        padding: EdgeInsets.fromLTRB(12.w, 0, 12.w, 12.h),
                        children: [
                          _SummaryCard(
                            total: _pick('total'),
                            commissionRebate: _pick('commissionRebate'),
                            agentRebate: _pick('agentRebate'),
                          ),
                          SizedBox(height: 12.h),
                          Row(
                            children: [
                              for (final c in _chips) ...[
                                _TypeChip(
                                  label: c.$2,
                                  selected: _type == c.$1,
                                  onTap: () {
                                    if (_type == c.$1) return;
                                    setState(() => _type = c.$1);
                                    _load();
                                  },
                                ),
                                SizedBox(width: 8.w),
                              ],
                            ],
                          ),
                          SizedBox(height: 12.h),
                          if (detail.isEmpty)
                            Padding(
                              padding: EdgeInsets.only(top: 40.h),
                              child: const Center(child: AppEmptyHint()),
                            )
                          else
                            for (var i = 0; i < detail.length; i++) ...[
                              if (i > 0) SizedBox(height: 10.h),
                              Builder(
                                builder: (_) {
                                  final r = detail[i];
                                  final changeType =
                                      '${r['changeType'] ?? ''}';
                                  final fields = <(String, String)>[];
                                  final bal = r['balanceAfter'];
                                  if (bal != null &&
                                      '$bal'.trim().isNotEmpty) {
                                    fields.add(
                                      ('变动后', displayNumber(bal)),
                                    );
                                  }
                                  final issue = '${r['issueNo'] ?? ''}';
                                  if (issue.isNotEmpty) {
                                    fields.add(('期号', issue));
                                  }
                                  final refId = '${r['refId'] ?? ''}';
                                  if (refId.isNotEmpty) {
                                    fields.add(('单号', refId));
                                  }
                                  final accountId = '${r['accountId'] ?? ''}';
                                  final ledgerId = '${r['id'] ?? ''}';
                                  return MemberLedgerCard(
                                    typeLabel: _detailTypeLabel(changeType),
                                    amount: r['amount'],
                                    toneKey: changeType,
                                    subtitle: accountId.isEmpty
                                        ? null
                                        : 'ID $accountId',
                                    fields: fields,
                                    remark: '${r['remark'] ?? ''}',
                                    time: '${r['createdAt'] ?? ''}',
                                    onShareToCs: ledgerId.isEmpty
                                        ? null
                                        : () => shareToCustomerService(
                                              context,
                                              ref,
                                              refType: 'WELFARE_LEDGER',
                                              refId: ledgerId,
                                              preview:
                                                  '${_detailTypeLabel(changeType)} #$ledgerId',
                                            ),
                                  );
                                },
                              ),
                            ],
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.total,
    required this.commissionRebate,
    required this.agentRebate,
  });

  final dynamic total;
  final dynamic commissionRebate;
  final dynamic agentRebate;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(12.w, 16.h, 12.w, 14.h),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12.r),
      ),
      child: Row(
        children: [
          _sumCell(displayNumber(total), '总计', memberBetPnlColor(total)),
          _sumCell(
            displayNumber(commissionRebate),
            '回水',
            memberBetPnlColor(commissionRebate),
          ),
          _sumCell(
            displayNumber(agentRebate),
            '代理抽佣',
            memberBetPnlColor(agentRebate),
          ),
        ],
      ),
    );
  }

  Widget _sumCell(String value, String label, Color color) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 20.sp,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          SizedBox(height: 4.h),
          Text(
            label,
            style: TextStyle(fontSize: 12.sp, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _TypeChip extends StatelessWidget {
  const _TypeChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 8.h),
        decoration: BoxDecoration(
          color: selected ? AppColors.navBlue : Colors.white,
          borderRadius: BorderRadius.circular(20.r),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13.sp,
            fontWeight: FontWeight.w500,
            color: selected ? Colors.white : AppColors.textPrimary,
          ),
        ),
      ),
    );
  }
}
