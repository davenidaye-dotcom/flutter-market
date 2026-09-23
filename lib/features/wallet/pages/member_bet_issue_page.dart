import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../config/theme/app_colors.dart';
import '../../../data/repositories/providers.dart';
import '../../../shared/widgets/app_empty_hint.dart';
import '../../../shared/widgets/app_page_loading.dart';
import '../../../shared/widgets/emulator_safe_text_field.dart';
import '../../../shared/widgets/page_app_bar.dart';
import '../widgets/date_range_filter.dart';
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
  static const _pageSize = 50;

  late List<DateRangeQuickItem> _quickItems;
  late int _quickIndex;
  late DateTime _start;
  late DateTime _end;

  List<Map<String, dynamic>> _rows = [];
  int _pageNum = 1;
  int _total = 0;
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _quickItems = memberBetQuickItems();
    _quickIndex = widget.quickIndex;
    _start = widget.start;
    _end = widget.end;
    _scroll.addListener(_onScroll);
    Future.microtask(() => _load(reset: true));
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_hasMore || _loadingMore || _loading) return;
    if (!_scroll.hasClients) return;
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 80) {
      _load(reset: false);
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
    _load(reset: true);
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
    _load(reset: true);
  }

  Future<void> _load({required bool reset}) async {
    if (reset) {
      setState(() {
        _pageNum = 1;
        _hasMore = true;
        _loading = true;
      });
    } else {
      if (!_hasMore || _loadingMore) return;
      setState(() => _loadingMore = true);
    }
    final page = reset ? 1 : _pageNum + 1;
    try {
      final data = await ref.read(walletRepositoryProvider).getBetIssueReport(
            gameType: widget.gameType,
            startDate: DateRangeFilter.format(_start),
            endDate: DateRangeFilter.format(_end),
            pageNum: page,
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
      final total = data['total'] is num
          ? (data['total'] as num).toInt()
          : list.length;
      setState(() {
        _rows = reset ? list : [..._rows, ...list];
        _pageNum = page;
        _total = total;
        _hasMore = _rows.length < total && list.isNotEmpty;
        _loading = false;
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadingMore = false;
      });
      AppToast.error(e.toString());
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
              child: _loading
                  ? const AppPageLoading()
                  : RefreshIndicator(
                      onRefresh: () => _load(reset: true),
                      child: ListView(
                        controller: _scroll,
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: EdgeInsets.fromLTRB(12.w, 0, 12.w, 24.h),
                        children: [
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
                          if (_rows.isNotEmpty)
                            Padding(
                              padding: EdgeInsets.only(top: 16.h),
                              child: Center(
                                child: Text(
                                  _loadingMore
                                      ? '加载中…'
                                      : '已加载完毕，共${_total > 0 ? _total : _rows.length}条',
                                  style: TextStyle(
                                    fontSize: 12.sp,
                                    color: AppColors.textHint,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
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
