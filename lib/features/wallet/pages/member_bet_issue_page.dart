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
import '../widgets/member_page_bar.dart';
import 'member_bet_item_page.dart';
import 'member_bet_report_shared.dart';

/// 竞猜记录 L2：某彩种期号列表
class MemberBetIssuePage extends ConsumerStatefulWidget {
  const MemberBetIssuePage({
    super.key,
    required this.gameType,
    required this.gameName,
    required this.start,
    required this.end,
    this.quickIndex = 0,
  });

  final String gameType;
  final String gameName;
  final DateTime start;
  final DateTime end;
  final int quickIndex;

  @override
  ConsumerState<MemberBetIssuePage> createState() => _MemberBetIssuePageState();
}

class _MemberBetIssuePageState extends ConsumerState<MemberBetIssuePage> {
  static const _pageSize = 20;

  late List<DateRangeQuickItem> _quickItems;
  late int _quickIndex;
  late DateTime _start;
  late DateTime _end;

  List<Map<String, dynamic>> _rows = [];
  int _page = 1;
  int _totalPages = 0;
  int _total = 0;
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _quickItems = memberBetQuickItems();
    _quickIndex = widget.quickIndex;
    _start = widget.start;
    _end = widget.end;
    Future.microtask(_load);
  }

  void _onQuickTap(int i) {
    if (i < 0 || i >= _quickItems.length) return;
    final it = _quickItems[i];
    setState(() {
      _quickIndex = i;
      _start = it.start;
      _end = it.end;
      _page = 1;
      _rows = [];
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
      _page = 1;
      _rows = [];
    });
    _load();
  }

  Future<void> _load({bool fromPull = false}) async {
    final blank = _rows.isEmpty;
    setState(() {
      if (!fromPull && blank) _loading = true;
      _busy = true;
    });
    try {
      final data = await ref.read(walletRepositoryProvider).getBetIssueReport(
            gameType: widget.gameType,
            startDate: DateRangeFilter.format(_start),
            endDate: DateRangeFilter.format(_end),
            pageNum: _page,
            pageSize: _pageSize,
          );
      if (!mounted) return;
      final rows = data['rows'];
      final list = rows is List
          ? rows
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList()
          : <Map<String, dynamic>>[];
      final total = data['total'] is num ? (data['total'] as num).toInt() : list.length;
      final pageSize = data['pageSize'] is num ? (data['pageSize'] as num).toInt() : _pageSize;
      setState(() {
        _rows = list;
        _total = total;
        _totalPages = memberTotalPages(total, pageSize);
        _loading = false;
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _busy = false;
      });
      AppToast.error(e.toString());
      if (fromPull) rethrow;
    }
  }

  void _openIssue(Map<String, dynamic> row) {
    final issue = '${row['issueNo'] ?? ''}'.trim();
    if (issue.isEmpty) {
      AppToast.error('缺少期号');
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MemberBetItemPage(
          gameType: widget.gameType,
          gameName: widget.gameName,
          issueNo: issue,
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
              title: '${widget.gameName} 竞猜记录',
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
                    else
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10.r),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Column(
                          children: [
                            _header(),
                            if (_rows.isEmpty)
                              Padding(
                                padding: EdgeInsets.symmetric(vertical: 64.h),
                                child: const Center(child: AppEmptyHint()),
                              )
                            else
                              for (var i = 0; i < _rows.length; i++)
                                _IssueRow(
                                  issue: '${_rows[i]['issueNo'] ?? '—'}',
                                  bet: memberBetMoney(
                                    _rows[i]['betAmount'],
                                    trimZero: true,
                                  ),
                                  pnl: memberBetMoney(
                                    _rows[i]['winLoss'],
                                    trimZero: true,
                                  ),
                                  pnlColor:
                                      memberBetPnlColor(_rows[i]['winLoss']),
                                  stripe: i.isOdd,
                                  onTap: () => _openIssue(_rows[i]),
                                ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
            MemberPageBar(
              page: _page,
              totalPages: _totalPages,
              totalCount: _total,
              busy: _busy,
              onPrev: () {
                if (_page > 1) {
                  setState(() => _page--);
                  _load();
                }
              },
              onNext: () {
                if (_totalPages == 0 || _page >= _totalPages) {
                  AppToast.info('已是最后一页');
                  return;
                }
                setState(() => _page++);
                _load();
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    return Container(
      color: const Color(0xFFF3F5F7),
      padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 11.h),
      child: Row(
        children: [
          Expanded(
            flex: 4,
            child: Text(
              '期号',
              style: TextStyle(fontSize: 13.sp, color: AppColors.textSecondary),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              '注额',
              textAlign: TextAlign.right,
              style: TextStyle(fontSize: 13.sp, color: AppColors.textSecondary),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              '输赢',
              textAlign: TextAlign.right,
              style: TextStyle(fontSize: 13.sp, color: AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

class _IssueRow extends StatelessWidget {
  const _IssueRow({
    required this.issue,
    required this.bet,
    required this.pnl,
    required this.pnlColor,
    required this.stripe,
    required this.onTap,
  });

  final String issue;
  final String bet;
  final String pnl;
  final Color pnlColor;
  final bool stripe;
  final VoidCallback onTap;

  static const _green = Color(0xFF2E9E5B);
  static const _stripe = Color(0xFFF3F7FB);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: stripe ? _stripe : Colors.white,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 14.h),
          child: Row(
            children: [
              Expanded(
                flex: 4,
                child: Text(
                  issue,
                  style: TextStyle(
                    fontSize: 15.sp,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              Expanded(
                flex: 3,
                child: Text(
                  bet,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 15.sp,
                    fontWeight: FontWeight.w600,
                    color: _green,
                  ),
                ),
              ),
              Expanded(
                flex: 3,
                child: Text(
                  pnl,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 15.sp,
                    fontWeight: FontWeight.w600,
                    color: pnlColor,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
