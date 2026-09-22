import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../../config/theme/app_colors.dart';
import '../../../../data/repositories/providers.dart';
import '../../../../shared/widgets/app_pull_refresh.dart';
import '../../../../shared/widgets/page_app_bar.dart';
import '../../data/host_mock.dart';
import '../../widgets/host_ui.dart';
import 'player_issue_detail_page.dart';
import 'report_date_bar.dart';

/// 玩家期数报表 — 点房间报表玩家卡片进入；点期号进详情报表
class PlayerPeriodReportPage extends ConsumerStatefulWidget {
  const PlayerPeriodReportPage({
    super.key,
    required this.roomId,
    required this.accountId,
    required this.displayName,
    this.initialStart,
    this.initialEnd,
    this.initialQuickIndex = 0,
  });

  final String roomId;
  final String accountId;
  final String displayName;
  final DateTime? initialStart;
  final DateTime? initialEnd;
  final int initialQuickIndex;

  @override
  ConsumerState<PlayerPeriodReportPage> createState() => _PlayerPeriodReportPageState();
}

class _PlayerPeriodReportPageState extends ConsumerState<PlayerPeriodReportPage>
    with ReportDatePageMixin {
  static const _pageSize = 20;

  List<Map<String, dynamic>> _rows = [];
  int _pageNum = 1;
  int _total = 0;
  bool _loading = false;
  bool _loadingMore = false;
  bool _hasMore = true;
  late String _titleName;
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _titleName = widget.displayName;
    if (widget.initialStart != null && widget.initialEnd != null) {
      start = widget.initialStart!;
      end = widget.initialEnd!;
      quickIndex = widget.initialQuickIndex;
    } else if (widget.initialQuickIndex == 6) {
      quickIndex = 6;
      final r = ReportDateBar.rangeForQuick(6);
      start = r.$1;
      end = r.$2;
    }
    _scroll.addListener(_onScroll);
    Future.microtask(() => _load(reset: true));
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  @override
  void onReportQuery() => _load(reset: true);

  void _onScroll() {
    if (!_hasMore || _loadingMore || _loading) return;
    if (!_scroll.hasClients) return;
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 80) {
      _load(reset: false);
    }
  }

  Future<void> _load({required bool reset}) async {
    if (reset) {
      setState(() {
        _loading = true;
        _pageNum = 1;
        _hasMore = true;
        _rows = [];
      });
    } else {
      if (!_hasMore || _loadingMore) return;
      setState(() => _loadingMore = true);
    }

    final page = reset ? 1 : _pageNum + 1;
    try {
      final data = await ref.read(ownerRepositoryProvider).getPlayerPeriodReport(
            accountId: widget.accountId,
            startDate: apiStartDate,
            endDate: apiEndDate,
            pageNum: page,
            pageSize: _pageSize,
          );
      if (!mounted) return;
      final rows = data['rows'];
      final list = rows is List
          ? rows.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
          : <Map<String, dynamic>>[];
      final total = _asInt(data['total']) ?? list.length;
      final nick = '${data['nickname'] ?? ''}'.trim();
      setState(() {
        if (nick.isNotEmpty) _titleName = nick;
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

  int? _asInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse('$v');
  }

  String _gameName(Map<String, dynamic> r) {
    final name = '${r['gameName'] ?? r['typeName'] ?? r['label'] ?? ''}'.trim();
    if (name.isNotEmpty) return name;
    final t = '${r['gameType'] ?? r['type'] ?? ''}'.trim();
    const map = {
      'JS_SC': '极速赛车',
      'JS_FT': '极速飞艇',
      'XY_FT': '幸运飞艇',
      'AZ_XY10': '澳洲幸运10',
      'SG_FT': 'SG飞艇',
    };
    return map[t] ?? (t.isEmpty ? '—' : t);
  }

  String _timeOf(Map<String, dynamic> r) {
    final raw = '${r['betAt'] ?? r['settledAt'] ?? r['createdAt'] ?? ''}'.trim();
    if (raw.isEmpty) return '';
    final cleaned = raw.replaceFirst('T', ' ');
    final parts = cleaned.split(RegExp(r'[\s-]'));
    if (parts.length >= 5) {
      final mm = parts[1].padLeft(2, '0');
      final dd = parts[2].padLeft(2, '0');
      final hm = parts[3].length >= 5 ? parts[3].substring(0, 5) : parts[3];
      return '$mm-$dd $hm';
    }
    return raw;
  }

  /// 截图金额不带多余小数：500 而不是 500.00
  String _money(dynamic v) {
    if (v == null) return '0';
    if (v is int) return '$v';
    if (v is num) {
      if (v == v.roundToDouble()) return '${v.round()}';
      return hostNumStr(v, fraction: 2);
    }
    final n = num.tryParse('$v');
    if (n == null) return '$v';
    if (n == n.roundToDouble()) return '${n.round()}';
    return hostNumStr(n, fraction: 2);
  }

  void _openIssueDetail(Map<String, dynamic> r) {
    final issue = '${r['issueNo'] ?? ''}'.trim();
    final gameType = '${r['gameType'] ?? ''}'.trim();
    if (issue.isEmpty || gameType.isEmpty) {
      AppToast.error('缺少期号或彩种');
      return;
    }
    pushHostPage(
      context,
      PlayerIssueDetailPage(
        roomId: widget.roomId,
        accountId: widget.accountId,
        displayName: _titleName,
        issueNo: issue,
        gameType: gameType,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return HostSubPageScaffold(
      title: '$_titleName 期数报表',
      body: Column(
        children: [
          SizedBox(height: 10.h),
          ReportDateBar(
            quickIndex: quickIndex,
            start: start,
            end: end,
            onQuickTap: onQuickTap,
            onCustomTap: pickCustomRange,
          ),
          SizedBox(height: 12.h),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : AppPullRefresh(
                    onRefresh: () => _load(reset: true),
                    child: ListView(
                      controller: _scroll,
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: EdgeInsets.fromLTRB(16.w, 0, 16.w, 24.h),
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12.r),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: Column(
                            children: [
                              _TableHeader(),
                              if (_rows.isEmpty)
                                Padding(
                                  padding: EdgeInsets.symmetric(vertical: 64.h),
                                  child: Text(
                                    '暂无期数数据',
                                    style: TextStyle(
                                      fontSize: 14.sp,
                                      color: AppColors.textHint,
                                    ),
                                  ),
                                )
                              else
                                for (var i = 0; i < _rows.length; i++)
                                  _PeriodRow(
                                    issue: '${_rows[i]['issueNo'] ?? '—'}',
                                    time: _timeOf(_rows[i]),
                                    game: _gameName(_rows[i]),
                                    bet: _money(
                                      _rows[i]['betAmount'] ??
                                          _rows[i]['totalAmount'] ??
                                          _rows[i]['amount'],
                                    ),
                                    pnl: _money(
                                      _rows[i]['winLoss'] ??
                                          _rows[i]['playerResult'] ??
                                          _rows[i]['pnl'],
                                    ),
                                    showDivider: i < _rows.length - 1,
                                    onTap: () => _openIssueDetail(_rows[i]),
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
                                    : '没有更多了，共 ${_total > 0 ? _total : _rows.length} 条',
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
    );
  }
}

class _TableHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF3F5F7),
      padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 11.h),
      child: const _Cols(
        c1: _HeadCell('期号'),
        c2: _HeadCell('游戏'),
        c3: _HeadCell('下注金额', align: TextAlign.right),
        c4: _HeadCell('输赢', align: TextAlign.right),
      ),
    );
  }
}

class _PeriodRow extends StatelessWidget {
  const _PeriodRow({
    required this.issue,
    required this.time,
    required this.game,
    required this.bet,
    required this.pnl,
    required this.showDivider,
    required this.onTap,
  });

  final String issue;
  final String time;
  final String game;
  final String bet;
  final String pnl;
  final bool showDivider;
  final VoidCallback onTap;

  static const _green = Color(0xFF2E9E5B);
  static const _red = Color(0xFFE53935);

  @override
  Widget build(BuildContext context) {
    final pnlNum = double.tryParse(pnl.replaceAll(',', '')) ?? 0;
    return Material(
      color: Colors.white,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 14.h),
          decoration: BoxDecoration(
            border: showDivider
                ? const Border(bottom: BorderSide(color: Color(0xFFF0F0F0)))
                : null,
          ),
          child: _Cols(
            c1: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  issue,
                  style: TextStyle(
                    fontSize: 15.sp,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                    height: 1.2,
                  ),
                ),
                if (time.isNotEmpty) ...[
                  SizedBox(height: 4.h),
                  Text(
                    time,
                    style: TextStyle(
                      fontSize: 11.sp,
                      color: AppColors.textHint,
                      height: 1.2,
                    ),
                  ),
                ],
              ],
            ),
            c2: Text(
              game,
              style: TextStyle(
                fontSize: 14.sp,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            c3: Text(
              bet,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 15.sp,
                fontWeight: FontWeight.w600,
                color: _green,
              ),
            ),
            c4: Text(
              pnl,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 15.sp,
                fontWeight: FontWeight.w600,
                color: pnlNum < 0 ? _red : _green,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Cols extends StatelessWidget {
  const _Cols({
    required this.c1,
    required this.c2,
    required this.c3,
    required this.c4,
  });

  final Widget c1;
  final Widget c2;
  final Widget c3;
  final Widget c4;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(flex: 28, child: c1),
        Expanded(flex: 28, child: c2),
        Expanded(flex: 22, child: c3),
        Expanded(flex: 22, child: c4),
      ],
    );
  }
}

class _HeadCell extends StatelessWidget {
  const _HeadCell(this.text, {this.align = TextAlign.left});

  final String text;
  final TextAlign align;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      textAlign: align,
      style: TextStyle(
        fontSize: 13.sp,
        color: const Color(0xFF8A9199),
        fontWeight: FontWeight.w500,
      ),
    );
  }
}
