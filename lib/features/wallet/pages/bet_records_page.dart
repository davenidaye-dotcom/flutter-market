import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../config/theme/app_colors.dart';
import '../../../data/repositories/providers.dart';
import '../../../shared/widgets/app_empty_hint.dart';
import '../../../shared/widgets/app_page_loading.dart';
import '../../../shared/widgets/app_pull_refresh.dart';
import '../../../shared/widgets/emulator_safe_text_field.dart';
import '../../../shared/widgets/page_app_bar.dart';
import '../widgets/date_range_filter.dart';
import 'member_bet_issue_page.dart';
import 'member_bet_report_shared.dart';

/// 竞猜记录 L1：按彩种汇总
class BetRecordsPage extends ConsumerStatefulWidget {
  const BetRecordsPage({super.key});

  @override
  ConsumerState<BetRecordsPage> createState() => _BetRecordsPageState();
}

class _BetRecordsPageState extends ConsumerState<BetRecordsPage> {
  late List<DateRangeQuickItem> _quickItems;
  int _quickIndex = 0;
  late DateTime _start;
  late DateTime _end;

  Map<String, dynamic> _summary = {};
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _quickItems = memberBetQuickItems();
    _start = _quickItems[0].start;
    _end = _quickItems[0].end;
    Future.microtask(_load);
  }

  Future<void> _load({bool fromPull = false}) async {
    if (!fromPull) {
      setState(() => _loading = true);
    }
    try {
      final data = await ref.read(walletRepositoryProvider).getBetGameReport(
            startDate: DateRangeFilter.format(_start),
            endDate: DateRangeFilter.format(_end),
          );
      if (!mounted) return;
      final summary = data['summary'];
      final raw = data['rows'];
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
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      AppToast.error(e.toString());
      rethrow;
    }
  }

  void _onQuickTap(int i) {
    if (i < 0 || i >= _quickItems.length) return;
    final it = _quickItems[i];
    setState(() {
      _quickIndex = i;
      _start = it.start;
      _end = it.end;
    });
    _load();
  }

  Future<void> _pickRange() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: DateTimeRange(start: _start, end: _end),
      helpText: '选择日期',
      cancelText: '取消',
      confirmText: '确定',
    );
    if (range == null || !mounted) return;
    setState(() {
      _quickIndex = -1;
      _start = DateTime(range.start.year, range.start.month, range.start.day);
      _end = DateTime(range.end.year, range.end.month, range.end.day);
    });
    _load();
  }

  void _openGame(Map<String, dynamic> row) {
    final gameType = '${row['gameType'] ?? ''}'.trim();
    final gameName = '${row['gameName'] ?? gameType}'.trim();
    if (gameType.isEmpty) {
      AppToast.error('缺少彩种');
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MemberBetIssuePage(
          gameType: gameType,
          gameName: gameName.isEmpty ? gameType : gameName,
          start: _start,
          end: _end,
          quickIndex: _quickIndex,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppPageScaffold(
      backgroundColor: const Color(0xFFF5F6F8),
      body: SafeArea(
        child: Column(
          children: [
            PageAppBar(
              title: '竞猜记录',
              onBack: () => appSafePop(context),
            ),
            SizedBox(height: 8.h),
            MemberBetDateBar(
              quickIndex: _quickIndex,
              start: _start,
              end: _end,
              quickItems: _quickItems,
              onQuickTap: _onQuickTap,
              onDateTap: _pickRange,
            ),
            SizedBox(height: 12.h),
            Expanded(
              child: AppPullRefresh(
                onRefresh: () => _load(fromPull: true),
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.fromLTRB(12.w, 0, 12.w, 24.h),
                  children: [
                    if (_loading)
                      SizedBox(
                        height: 200.h,
                        child: const AppPageLoading(),
                      )
                    else ...[
                      _SummaryCard(summary: _summary),
                      SizedBox(height: 12.h),
                      if (_rows.isEmpty)
                        Padding(
                          padding: EdgeInsets.only(top: 80.h),
                          child: const Center(child: AppEmptyHint()),
                        )
                      else ...[
                        for (final r in _rows) ...[
                          _GameCard(row: r, onTap: () => _openGame(r)),
                          SizedBox(height: 10.h),
                        ],
                        Padding(
                          padding: EdgeInsets.only(top: 8.h),
                          child: Center(
                            child: Text(
                              '已加载完毕，共${_rows.length}条',
                              style: TextStyle(
                                fontSize: 12.sp,
                                color: AppColors.textHint,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.summary});

  final Map<String, dynamic> summary;

  @override
  Widget build(BuildContext context) {
    final orders = memberBetMoney(summary['totalOrders']);
    final bet = memberBetMoney(summary['totalBetAmount']);
    final rebate = memberBetMoney(summary['totalRebate']);
    final gameResult = memberBetMoney(summary['gameResult']);
    final playerResult = memberBetMoney(summary['playerResult']);
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(12.w, 16.h, 12.w, 14.h),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12.r),
      ),
      child: Column(
        children: [
          Row(
            children: [
              _sumCell(orders, '总注单', memberBetPnlColor(summary['totalOrders'])),
              _sumCell(bet, '总注额', memberBetPnlColor(summary['totalBetAmount'])),
              _sumCell(rebate, '总返点', memberBetPnlColor(summary['totalRebate'])),
            ],
          ),
          SizedBox(height: 14.h),
          Row(
            children: [
              Expanded(
                child: _resultLine(
                  '游戏总结果',
                  gameResult,
                  memberBetPnlColor(summary['gameResult']),
                ),
              ),
              Expanded(
                child: _resultLine(
                  '玩家总结果',
                  playerResult,
                  memberBetPnlColor(summary['playerResult']),
                ),
              ),
            ],
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

  Widget _resultLine(String label, String value, Color color) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 12.sp, color: AppColors.textSecondary),
        ),
        SizedBox(width: 6.w),
        Text(
          value,
          style: TextStyle(
            fontSize: 14.sp,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }
}

class _GameCard extends StatelessWidget {
  const _GameCard({required this.row, required this.onTap});

  final Map<String, dynamic> row;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final name = '${row['gameName'] ?? row['gameType'] ?? '—'}';
    final player = memberBetMoney(row['playerResult']);
    final game = memberBetMoney(row['gameResult']);
    final orders = memberBetMoney(row['orderCount'], trimZero: true);
    final bet = memberBetMoney(row['betAmount'], trimZero: true);
    final rebate = memberBetMoney(row['rebate']);
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12.r),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12.r),
        child: Padding(
          padding: EdgeInsets.fromLTRB(14.w, 14.h, 10.w, 14.h),
          child: Column(
            children: [
              Row(
                children: [
                  Icon(Icons.sports_motorsports,
                      size: 22.sp, color: const Color(0xFF4A9DF0)),
                  SizedBox(width: 8.w),
                  Expanded(
                    child: Text(
                      name,
                      style: TextStyle(
                        fontSize: 16.sp,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  Icon(Icons.chevron_right,
                      size: 22.sp, color: AppColors.textHint),
                ],
              ),
              SizedBox(height: 12.h),
              Row(
                children: [
                  Expanded(
                    child: _kv(
                      '玩家总结果',
                      player,
                      memberBetPnlColor(row['playerResult']),
                    ),
                  ),
                  Expanded(
                    child: _kv(
                      '游戏总结果',
                      game,
                      memberBetPnlColor(row['gameResult']),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 10.h),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '注单 $orders',
                      style: TextStyle(
                        fontSize: 12.sp,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      '注额 $bet',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12.sp,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      '彩票回水 $rebate',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: 12.sp,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _kv(String label, String value, Color color) {
    return Row(
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 12.sp, color: AppColors.textSecondary),
        ),
        SizedBox(width: 6.w),
        Flexible(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 14.sp,
              fontWeight: FontWeight.w600,
              color: color,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
