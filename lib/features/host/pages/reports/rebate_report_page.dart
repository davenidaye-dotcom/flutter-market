import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../../config/theme/app_colors.dart';
import '../../../../data/repositories/providers.dart';
import '../../../../shared/widgets/app_pull_refresh.dart';
import '../../../../shared/widgets/page_app_bar.dart';
import '../../../wallet/widgets/date_range_filter.dart';
import '../../data/host_mock.dart';
import '../../widgets/host_ui.dart';

/// 彩票回水报表，或代理抽佣报表。房级合计 + data.members[]。
class RebateReportPage extends ConsumerStatefulWidget {
  const RebateReportPage({
    super.key,
    required this.roomId,
    this.commission = false,
  });
  final String roomId;
  final bool commission;

  @override
  ConsumerState<RebateReportPage> createState() => _RebateReportPageState();
}

class _RebateReportPageState extends ConsumerState<RebateReportPage>
    with DateRangePageMixin {
  Map<String, dynamic> _data = {};
  bool _loading = false;
  bool _summaryOpen = true;

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  @override
  void onQuery() => _load();

  Future<void> _load({bool silent = false}) async {
    if (!silent && mounted) setState(() => _loading = true);
    try {
      final repo = ref.read(ownerRepositoryProvider);
      final data = widget.commission
          ? await repo.getCommissionReport(
              startDate: DateRangeFilter.format(start),
              endDate: DateRangeFilter.format(end),
            )
          : await repo.getRebateReport(
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

  List<Map<String, dynamic>> get _members {
    final raw = _data['members'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  /// 列表名称优先 username（文档字段）
  String _memberName(Map<String, dynamic> m) {
    final user = '${m['username'] ?? ''}'.trim();
    if (user.isNotEmpty) return user;
    final nick = '${m['nickname'] ?? ''}'.trim();
    if (nick.isNotEmpty) return nick;
    return '${m['accountId'] ?? ''}';
  }

  @override
  Widget build(BuildContext context) {
    final members = _members;
    return HostSubPageScaffold(
      title: widget.commission ? '代理抽佣报表' : '彩票回水报表',
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
          SizedBox(height: 8.h),
          Expanded(
            child: _loading && _data.isEmpty
                ? const AppPageLoading()
                : AppPullRefresh(
                    onRefresh: () => _load(silent: true),
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: EdgeInsets.fromLTRB(16.w, 0, 16.w, 16.h),
                      children: [
                        HostWhiteCard(
                          padding: EdgeInsets.fromLTRB(12.w, 10.h, 12.w, 10.h),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () =>
                                    setState(() => _summaryOpen = !_summaryOpen),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        '房级合计',
                                        style: TextStyle(
                                          fontSize: 15.sp,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                    Text(
                                      _summaryOpen ? '收起' : '展开',
                                      style: TextStyle(
                                        fontSize: 13.sp,
                                        color: const Color(0xFF4A90D9),
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (!_summaryOpen) ...[
                                SizedBox(height: 8.h),
                                _metricRow(
                                  '待领取',
                                  _data['pending'],
                                  valueColor: const Color(0xFF2E7D32),
                                  compact: true,
                                ),
                              ] else ...[
                                SizedBox(height: 10.h),
                                _metricRow(
                                  widget.commission ? '应抽佣' : '应回水',
                                  _data['accrued'],
                                  compact: true,
                                ),
                                _metricRow('已发放', _data['paid'], compact: true),
                                _metricRow(
                                  '待领取',
                                  _data['pending'],
                                  valueColor: const Color(0xFF2E7D32),
                                  compact: true,
                                ),
                                _metricRow(
                                  widget.commission ? '未发笔数' : '未回笔数',
                                  _data['unpaidCount'],
                                  compact: true,
                                ),
                                _metricRow(
                                  widget.commission ? '未发流水' : '未回流水',
                                  _data['unpaidTurnover'],
                                  compact: true,
                                ),
                                _metricRow('有效流水', _data['turnover'], compact: true),
                                Divider(height: 16.h, color: AppColors.divider),
                                _metricRow('自行领取', _data['selfPaid'], compact: true),
                                _metricRow('房主一键', _data['ownerPaid'], compact: true),
                                _metricRow('系统自动', _data['systemPaid'], compact: true),
                              ],
                            ],
                          ),
                        ),
                        SizedBox(height: 10.h),
                        if (members.isEmpty)
                          Padding(
                            padding: EdgeInsets.only(top: 24.h),
                            child: Center(
                              child: Text(
                                widget.commission ? '暂无抽佣明细' : '暂无按人明细',
                                style: TextStyle(
                                  fontSize: 14.sp,
                                  color: AppColors.textHint,
                                ),
                              ),
                            ),
                          )
                        else ...[
                          for (final m in members) ...[
                            _MemberRebateCard(
                              name: _memberName(m),
                              commission: widget.commission,
                              paid: hostNumStr(m['paid'], fraction: 2),
                              accrued: hostNumStr(m['accrued'], fraction: 2),
                              pending: hostNumStr(m['pending'], fraction: 2),
                              ratio: '${hostNumStr(m['ratio'], fraction: 2)}%',
                              turnover: hostNumStr(m['turnover'], fraction: 2),
                              orderCount: hostNumStr(m['orderCount'], fraction: 0),
                              unpaidCount: hostNumStr(m['unpaidCount'], fraction: 0),
                              unpaidTurnover:
                                  hostNumStr(m['unpaidTurnover'], fraction: 2),
                            ),
                            SizedBox(height: 6.h),
                          ],
                          Padding(
                            padding: EdgeInsets.only(top: 4.h, bottom: 8.h),
                            child: Center(
                              child: Text(
                                '没有更多了，共 ${members.length} 条',
                                style: TextStyle(
                                  fontSize: 12.sp,
                                  color: AppColors.textHint,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _metricRow(
    String label,
    dynamic value, {
    Color? valueColor,
    bool compact = false,
  }) {
    return Padding(
      padding: EdgeInsets.only(bottom: compact ? 5.h : 8.h),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 13.sp, color: AppColors.textSecondary),
          ),
          const Spacer(),
          Text(
            hostNumStr(value, fraction: 2),
            style: TextStyle(
              fontSize: 13.sp,
              fontWeight: FontWeight.w600,
              color: valueColor ?? const Color(0xFF222222),
            ),
          ),
        ],
      ),
    );
  }
}

class _MemberRebateCard extends StatelessWidget {
  const _MemberRebateCard({
    required this.name,
    required this.commission,
    required this.paid,
    required this.accrued,
    required this.pending,
    required this.ratio,
    required this.turnover,
    required this.orderCount,
    required this.unpaidCount,
    required this.unpaidTurnover,
  });

  final String name;
  final bool commission;
  final String paid;
  final String accrued;
  final String pending;
  final String ratio;
  final String turnover;
  final String orderCount;
  final String unpaidCount;
  final String unpaidTurnover;

  @override
  Widget build(BuildContext context) {
    return HostWhiteCard(
      padding: EdgeInsets.fromLTRB(10.w, 8.h, 10.w, 8.h),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  name,
                  style: TextStyle(
                    fontSize: 14.sp,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF222222),
                  ),
                ),
              ),
              Text(
                '待领 $pending · ${commission ? '应抽' : '应回'} $accrued',
                style: TextStyle(
                  fontSize: 12.sp,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF2E7D32),
                ),
              ),
            ],
          ),
          SizedBox(height: 8.h),
          Row(
            children: [
              Expanded(child: _col('比例', ratio)),
              Expanded(child: _col('总流水', turnover)),
              Expanded(child: _col('注单', orderCount)),
              Expanded(child: _col(commission ? '未发笔数' : '未回笔数', unpaidCount)),
            ],
          ),
          SizedBox(height: 6.h),
          Row(
            children: [
              Expanded(child: _col(commission ? '未发流水' : '未回流水', unpaidTurnover)),
              Expanded(child: _col('已发放', paid)),
              Expanded(child: _col('待领取', pending)),
              Expanded(child: _col(commission ? '应抽佣' : '应回水', accrued)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _col(String label, String value) {
    return Column(
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 11.sp, color: AppColors.textSecondary),
        ),
        SizedBox(height: 2.h),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 13.sp,
            fontWeight: FontWeight.w700,
            color: const Color(0xFF222222),
          ),
        ),
      ],
    );
  }
}
