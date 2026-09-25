import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../../config/theme/app_colors.dart';
import '../../../../shared/format/play_title.dart';
import '../../../../data/repositories/providers.dart';
import '../../../../shared/widgets/app_pull_refresh.dart';
import '../../../../shared/widgets/page_app_bar.dart';
import '../../data/host_mock.dart';
import '../../widgets/host_ui.dart';

/// 图3 玩法明细 — GET /owner/manage/reports/bets/items
class PlayerIssueDetailPage extends ConsumerStatefulWidget {
  const PlayerIssueDetailPage({
    super.key,
    required this.roomId,
    required this.accountId,
    required this.displayName,
    required this.issueNo,
    required this.gameType,
  });

  final String roomId;
  final String accountId;
  final String displayName;
  final String issueNo;
  final String gameType;

  @override
  ConsumerState<PlayerIssueDetailPage> createState() => _PlayerIssueDetailPageState();
}

class _PlayerIssueDetailPageState extends ConsumerState<PlayerIssueDetailPage> {
  static const _green = Color(0xFF2E9E5B);
  static const _red = Color(0xFFE53935);

  Map<String, dynamic> _summary = {};
  List<Map<String, dynamic>> _rows = [];
  late String _titleName;
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  int _pageNum = 1;
  int _total = 0;
  static const _pageSize = 20;
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _titleName = widget.displayName;
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

  Future<void> _load({required bool reset}) async {
    if (reset) {
      setState(() {
        _pageNum = 1;
        _hasMore = true;
      });
    } else {
      if (!_hasMore || _loadingMore) return;
      setState(() => _loadingMore = true);
    }
    final page = reset ? 1 : _pageNum + 1;
    try {
      final data = await ref.read(ownerRepositoryProvider).getPlayerIssueBetDetail(
            accountId: widget.accountId,
            issueNo: widget.issueNo,
            gameType: widget.gameType,
            pageNum: page,
            pageSize: _pageSize,
          );
      if (!mounted) return;
      final summary = data['summary'];
      final rows = data['rows'];
      final list = rows is List
          ? rows.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
          : <Map<String, dynamic>>[];
      final total = _asInt(data['total']) ??
          _asInt(summary is Map ? summary['itemCount'] : null) ??
          list.length;
      final nick = '${data['nickname'] ?? (summary is Map ? summary['nickname'] : '')}'.trim();
      setState(() {
        if (reset && summary is Map) {
          _summary = Map<String, dynamic>.from(summary);
        }
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

  String _pick(List<String> keys, {int fraction = 2}) {
    for (final k in keys) {
      if (_summary[k] != null) return hostNumStr(_summary[k], fraction: fraction);
    }
    return fraction == 0 ? '0' : '0.00';
  }

  Color _resultColor(String text) {
    final n = double.tryParse(text.replaceAll(',', '')) ?? 0;
    if (n > 0) return _green;
    if (n < 0) return _red;
    return AppColors.textPrimary;
  }

  String _shortTime(dynamic raw) {
    final s = '$raw'.trim();
    if (s.isEmpty || s == 'null') return '';
    final cleaned = s.replaceFirst('T', ' ');
    final parts = cleaned.split(RegExp(r'[\s-]'));
    if (parts.length >= 5) {
      final mm = parts[1].padLeft(2, '0');
      final dd = parts[2].padLeft(2, '0');
      final hm = parts[3].length >= 5 ? parts[3].substring(0, 5) : parts[3];
      return '$mm-$dd $hm';
    }
    return s;
  }

  @override
  Widget build(BuildContext context) {
    final betCount = _pick(['itemCount'], fraction: 0);
    final betAmount = _pick(['betAmount']);
    final resultTotal = _pick(['playerResult']);

    return HostSubPageScaffold(
      title: '玩家$_titleName报表',
      body: AppPullRefresh(
              onRefresh: () => _load(reset: true),
              child: ListView.builder(
                controller: _scroll,
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 16.h),
                itemCount: 1 + (_rows.isEmpty ? 1 : _rows.length + 1),
                itemBuilder: (_, i) {
                  if (i == 0) {
                    return Padding(
                      padding: EdgeInsets.only(bottom: 12.h),
                      child: HostWhiteCard(
                        padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 14.h),
                        child: Row(
                          children: [
                            Expanded(child: _sumCell('注数', betCount)),
                            Expanded(child: _sumCell('下注金额(计)', betAmount)),
                            Expanded(
                              child: _sumCell(
                                '结果(总计)',
                                resultTotal,
                                valueColor: _resultColor(resultTotal),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }
                  if (_rows.isEmpty) {
                    return Padding(
                      padding: EdgeInsets.only(top: 80.h),
                      child: Center(
                        child: Text(
                          '暂无注单明细',
                          style: TextStyle(fontSize: 14.sp, color: AppColors.textHint),
                        ),
                      ),
                    );
                  }
                  if (i == _rows.length + 1) {
                    return Padding(
                      padding: EdgeInsets.only(top: 12.h),
                      child: Center(
                        child: Text(
                          _loadingMore
                              ? '加载中…'
                              : '没有更多了，共 ${_total > 0 ? _total : _rows.length} 条',
                          style: TextStyle(fontSize: 12.sp, color: AppColors.textHint),
                        ),
                      ),
                    );
                  }
                  final r = _rows[i - 1];
                  return Padding(
                    padding: EdgeInsets.only(bottom: 10.h),
                    child: _BetLineCard(
                      row: r,
                      timeLabel: _shortTime(r['createdAt']),
                    ),
                  );
                },
              ),
            ),
    );
  }

  Widget _sumCell(String label, String value, {Color? valueColor}) {
    return Column(
      children: [
        Text(label, style: TextStyle(fontSize: 12.sp, color: AppColors.textSecondary)),
        SizedBox(height: 6.h),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            value,
            style: TextStyle(
              fontSize: 18.sp,
              fontWeight: FontWeight.w700,
              color: valueColor ?? AppColors.textPrimary,
            ),
          ),
        ),
      ],
    );
  }
}

class _BetLineCard extends StatelessWidget {
  const _BetLineCard({required this.row, required this.timeLabel});

  final Map<String, dynamic> row;
  final String timeLabel;

  static const _green = Color(0xFF2E9E5B);
  static const _red = Color(0xFFE53935);

  @override
  Widget build(BuildContext context) {
    final title = rankBetTitle(row);
    final issue = '${row['issueNo'] ?? ''}'.trim();
    final issueLabel = issue.isEmpty
        ? ''
        : (issue.startsWith('第') ? issue : '第$issue期');
    final display = hostNumStr(row['displayAmount'] ?? row['net'] ?? 0, fraction: 2);
    final outcome = '${row['outcome'] ?? ''}'.toUpperCase();
    final displayNum = double.tryParse(display.replaceAll(',', '')) ?? 0;
    final win = outcome == 'WIN' || (outcome.isEmpty && displayNum > 0);
    final lose = outcome == 'LOSE' || (outcome.isEmpty && displayNum < 0);
    final pending = outcome == 'PENDING';
    final badgeColor = win
        ? _green
        : (lose ? _red : (pending ? AppColors.textHint : AppColors.textHint));
    final badgeText = win ? '赢' : (lose ? '输' : (pending ? '待' : '和'));
    final amountColor = win ? _green : (lose ? _red : AppColors.textPrimary);

    return HostWhiteCard(
      padding: EdgeInsets.fromLTRB(14.w, 12.h, 12.w, 12.h),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w600),
                ),
                SizedBox(height: 6.h),
                Text(
                  issueLabel,
                  style: TextStyle(fontSize: 12.sp, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                display,
                style: TextStyle(
                  fontSize: 16.sp,
                  fontWeight: FontWeight.w700,
                  color: amountColor,
                ),
              ),
              SizedBox(height: 6.h),
              Text(
                timeLabel,
                style: TextStyle(fontSize: 12.sp, color: AppColors.textHint),
              ),
            ],
          ),
          SizedBox(width: 10.w),
          Container(
            width: 36.w,
            height: 36.w,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: badgeColor, shape: BoxShape.circle),
            child: Text(
              badgeText,
              style: TextStyle(
                fontSize: 13.sp,
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
