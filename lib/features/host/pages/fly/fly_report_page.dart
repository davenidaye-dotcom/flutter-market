import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../../config/theme/app_colors.dart';
import '../../../../data/repositories/providers.dart';
import '../../../../shared/format/display_number.dart';
import '../../../../shared/format/game_series.dart';
import '../../../../shared/widgets/page_app_bar.dart';
import '../../../wallet/widgets/date_range_filter.dart';
import '../../../wallet/widgets/member_page_bar.dart';
import '../../data/host_mock.dart';
import '../../widgets/host_ui.dart';
import 'fly_issue_detail_page.dart';

/// Feipan reports — 汇总 + 期号列表（对齐图7）
class FlyReportPage extends ConsumerStatefulWidget {
  const FlyReportPage({super.key, required this.roomId});
  final String roomId;

  @override
  ConsumerState<FlyReportPage> createState() => _FlyReportPageState();
}

class _FlyReportPageState extends ConsumerState<FlyReportPage>
    with DateRangePageMixin {
  Map<String, dynamic> _data = {};
  bool _loading = true;
  bool _busy = false;
  bool _unbound = false;
  String _gameType = GameSeries.filterAll;
  int _page = 1;
  int _totalCount = 0;
  int _totalPages = 0;
  int _req = 0;
  static const _pageSize = 20;

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  @override
  void onQuery() => _reload();

  void _reload() {
    setState(() {
      _page = 1;
      _data = {};
      _totalCount = 0;
      _totalPages = 0;
    });
    _load();
  }

  Future<void> _load({int? page}) async {
    final target = page ?? _page;
    final req = ++_req;
    final blank = _rows.isEmpty;
    setState(() {
      if (blank) _loading = true;
      _busy = true;
      _unbound = false;
    });
    try {
      final repo = ref.read(ownerRepositoryProvider);
      final statusFuture = repo.getFeipanStatus();
      Object? reportError;
      final reportFuture = repo.getFeipanReports(
        startDate: DateRangeFilter.format(start),
        endDate: DateRangeFilter.format(end),
        category: _gameType,
        pageNum: target,
        pageSize: _pageSize,
      ).catchError((Object e) {
        reportError = e;
        return <String, dynamic>{};
      });
      final status = await statusFuture;
      if (!mounted || req != _req) return;
      if (status['bound'] != true) {
        setState(() {
          _unbound = true;
          _data = {};
          _totalCount = 0;
          _totalPages = 0;
          _loading = false;
          _busy = false;
        });
        return;
      }
      final data = await reportFuture;
      if (reportError != null) {
        throw reportError!;
      }
      if (!mounted || req != _req) return;
      final total = data['total'] is num ? (data['total'] as num).toInt() : _rowsOf(data).length;
      setState(() {
        _page = target;
        _data = data;
        _totalCount = total;
        _totalPages = memberTotalPages(total, _pageSize);
        _loading = false;
        _busy = false;
      });
    } catch (e) {
      if (!mounted || req != _req) return;
      setState(() {
        _loading = false;
        _busy = false;
      });
      AppToast.error(e.toString());
    }
  }

  num _n(dynamic v) {
    if (v is num) return v;
    return num.tryParse('$v'.trim().replaceAll(',', '')) ?? 0;
  }

  String _v(String k, {int fraction = 2}) {
    final s = _data['summary'];
    if (s is Map && s[k] != null) return hostNumStr(s[k], fraction: fraction);
    return '0';
  }

  String _totalWinLoss() {
    final s = _data['summary'];
    if (s is! Map) return '0';
    final wl = _n(s['winLoss']);
    final rebate = _n(s['rebate']);
    return hostNumStr(wl + rebate, fraction: 2);
  }

  List<Map<String, dynamic>> get _rows => _rowsOf(_data);

  List<Map<String, dynamic>> _rowsOf(Map<String, dynamic> data) {
    final raw = data['rows'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  String _issueAt(Map<String, dynamic> r) {
    final s = '${r['issueAt'] ?? ''}'.trim();
    if (s.isEmpty) return '';
    final m = RegExp(r'(\d{4})-(\d{2})-(\d{2})[ T](\d{2}):(\d{2})').firstMatch(s);
    if (m != null) {
      return '${m.group(2)}-${m.group(3)} ${m.group(4)}:${m.group(5)}';
    }
    return s;
  }

  String _ratio(Map<String, dynamic> r) {
    final v = r['flightRatio'];
    if (v == null) return '—';
    final n = _n(v);
    if (n == 0 && '$v'.trim().isEmpty) return '—';
    final plain = n == n.roundToDouble() ? '${n.toInt()}' : '$n';
    return '$plain%';
  }

  Color _pnlColor(String text) {
    final n = num.tryParse(text.replaceAll(',', ''));
    if (n == null || n == 0) return AppColors.textPrimary;
    return n < 0 ? AppColors.danger : AppColors.textPrimary;
  }

  Widget _metric(String label, String value, {bool emphasize = false}) {
    return HostWhiteCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 12.sp, color: AppColors.textSecondary),
          ),
          SizedBox(height: 4.h),
          Text(
            value,
            style: TextStyle(
              fontSize: 16.sp,
              fontWeight: FontWeight.w700,
              color: emphasize ? _pnlColor(value) : AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bet = _v('betAmount');
    final pnl = _v('winLoss');
    final rebate = _v('rebate');
    final totalWl = _totalWinLoss();
    final rows = _rows;

    return HostSubPageScaffold(
      title: '飞单报表',
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
            gameType: _gameType,
            onGameType: (code) {
              setState(() => _gameType = code);
              _reload();
            },
          ),
          SizedBox(height: 8.h),
          Expanded(
            child: _loading && _rows.isEmpty
                ? const AppPageLoading()
                : _unbound
                    ? Center(
                        child: Text(
                          '请先绑定代理会员',
                          style: TextStyle(fontSize: 14.sp, color: AppColors.textHint),
                        ),
                      )
                    : ListView(
                        padding: EdgeInsets.fromLTRB(16.w, 0, 16.w, 16.h),
                        children: [
                          GridView.count(
                            crossAxisCount: 2,
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            mainAxisSpacing: 10.h,
                            crossAxisSpacing: 10.w,
                            childAspectRatio: 2.1,
                            children: [
                              _metric('总实飞', bet),
                              _metric('盈亏', pnl, emphasize: true),
                              _metric('彩票回水', rebate),
                              _metric('总输赢', totalWl, emphasize: true),
                            ],
                          ),
                          SizedBox(height: 12.h),
                          if (rows.isEmpty)
                            Padding(
                              padding: EdgeInsets.only(top: 40.h),
                              child: Center(
                                child: Text(
                                  '暂无数据',
                                  style: TextStyle(color: AppColors.textHint),
                                ),
                              ),
                            )
                          else ...[
                            Padding(
                              padding: EdgeInsets.symmetric(vertical: 6.h),
                              child: Row(
                                children: [
                                  _colHead('期号/日期', flex: 3),
                                  _colHead('游戏', flex: 2),
                                  _colHead('注单', flex: 1),
                                  _colHead('流水', flex: 2),
                                  _colHead('输赢', flex: 2),
                                ],
                              ),
                            ),
                            ...List.generate(rows.length, (i) {
                              final r = rows[i];
                              final issue = '${r['issueNo'] ?? r['label'] ?? '—'}';
                              final game =
                                  '${r['gameName'] ?? r['label'] ?? r['gameType'] ?? '—'}';
                              final wl = displayNumber(r['winLoss'] ?? 0);
                              final bg = i.isOdd
                                  ? const Color(0xFFF5F3FA)
                                  : Colors.white;
                              return Material(
                                color: bg,
                                child: InkWell(
                                  onTap: () => _openIssueDetail(r),
                                  child: Padding(
                                    padding: EdgeInsets.symmetric(
                                      vertical: 10.h,
                                      horizontal: 4.w,
                                    ),
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Expanded(
                                          flex: 3,
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                issue,
                                                style: TextStyle(
                                                  fontSize: 12.sp,
                                                  fontWeight: FontWeight.w600,
                                                  color: AppColors.navBlue,
                                                ),
                                              ),
                                              Text(
                                                '${_issueAt(r)} · ${_ratio(r)}',
                                                style: TextStyle(
                                                  fontSize: 11.sp,
                                                  color: AppColors.textHint,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        Expanded(
                                          flex: 2,
                                          child: Text(
                                            game,
                                            style: TextStyle(fontSize: 12.sp),
                                          ),
                                        ),
                                        Expanded(
                                          flex: 1,
                                          child: Text(
                                            displayNumber(r['orderCount'] ?? 0),
                                            style: TextStyle(fontSize: 12.sp),
                                          ),
                                        ),
                                        Expanded(
                                          flex: 2,
                                          child: Text(
                                            displayNumber(r['betAmount'] ?? 0),
                                            style: TextStyle(fontSize: 12.sp),
                                          ),
                                        ),
                                        Expanded(
                                          flex: 2,
                                          child: Text(
                                            wl,
                                            style: TextStyle(
                                              fontSize: 12.sp,
                                              color: _pnlColor(wl),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            }),
                          ],
                        ],
                      ),
          ),
          if (!_unbound)
            MemberPageBar(
              page: _page,
              totalPages: _totalPages,
              totalCount: _totalCount,
              busy: _busy,
              onPrev: () {
                if (_busy || _page <= 1) return;
                _load(page: _page - 1);
              },
              onNext: () {
                if (_busy || _totalPages == 0 || _page >= _totalPages) {
                  if (!_busy) AppToast.info('已是最后一页');
                  return;
                }
                _load(page: _page + 1);
              },
            ),
        ],
      ),
    );
  }

  void _openIssueDetail(Map<String, dynamic> r) {
    final issue = '${r['issueNo'] ?? ''}'.trim();
    final gameType = '${r['gameType'] ?? ''}'.trim();
    if (issue.isEmpty || gameType.isEmpty) {
      AppToast.error('缺少期号或彩种');
      return;
    }
    final gameName = '${r['gameName'] ?? r['label'] ?? gameType}'.trim();
    pushHostPage(
      context,
      FlyIssueDetailPage(
        roomId: widget.roomId,
        issueNo: issue,
        gameType: gameType,
        gameName: gameName,
      ),
    );
  }

  Widget _colHead(String t, {required int flex}) {
    return Expanded(
      flex: flex,
      child: Text(
        t,
        style: TextStyle(fontSize: 11.sp, color: AppColors.textSecondary),
      ),
    );
  }
}
