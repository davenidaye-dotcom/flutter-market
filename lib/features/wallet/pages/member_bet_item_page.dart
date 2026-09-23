import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../config/theme/app_colors.dart';
import '../../../data/repositories/providers.dart';
import '../../../shared/widgets/app_empty_hint.dart';
import '../../../shared/widgets/app_page_loading.dart';
import '../../../shared/widgets/emulator_safe_text_field.dart';
import '../../../shared/widgets/page_app_bar.dart';
import 'member_bet_report_shared.dart';

/// 竞猜记录 L3：某期玩法明细
class MemberBetItemPage extends ConsumerStatefulWidget {
  const MemberBetItemPage({
    super.key,
    required this.gameType,
    required this.gameName,
    required this.issueNo,
  });

  final String gameType;
  final String gameName;
  final String issueNo;

  @override
  ConsumerState<MemberBetItemPage> createState() => _MemberBetItemPageState();
}

class _MemberBetItemPageState extends ConsumerState<MemberBetItemPage> {
  static const _pageSize = 50;

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
        _loading = true;
      });
    } else {
      if (!_hasMore || _loadingMore) return;
      setState(() => _loadingMore = true);
    }
    final page = reset ? 1 : _pageNum + 1;
    try {
      final data = await ref.read(walletRepositoryProvider).getBetItemReport(
            gameType: widget.gameType,
            issueNo: widget.issueNo,
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

  String _fullTime(dynamic raw) {
    final s = '$raw'.trim();
    if (s.isEmpty || s == 'null') return '';
    return s.replaceFirst('T', ' ');
  }

  @override
  Widget build(BuildContext context) {
    final short = shortIssueTail(widget.issueNo);
    return AppPageScaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            PageAppBar(
              title: '${widget.gameName} $short期',
              onBack: () => appSafePop(context),
            ),
            Expanded(
              child: _loading
                  ? const AppPageLoading()
                  : RefreshIndicator(
                      onRefresh: () => _load(reset: true),
                      child: ListView.separated(
                        controller: _scroll,
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: EdgeInsets.fromLTRB(16.w, 4.h, 16.w, 24.h),
                        itemCount: _rows.isEmpty ? 1 : _rows.length + 1,
                        separatorBuilder: (_, _) =>
                            const Divider(height: 1, color: Color(0xFFEEEEEE)),
                        itemBuilder: (_, i) {
                          if (_rows.isEmpty) {
                            return Padding(
                              padding: EdgeInsets.only(top: 80.h),
                              child: const Center(child: AppEmptyHint()),
                            );
                          }
                          if (i == _rows.length) {
                            return Padding(
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
                            );
                          }
                          return _ItemRow(
                            row: _rows[i],
                            timeLabel: _fullTime(_rows[i]['createdAt']),
                          );
                        },
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({required this.row, required this.timeLabel});

  final Map<String, dynamic> row;
  final String timeLabel;

  static const _green = Color(0xFF2E9E5B);
  static const _red = Color(0xFFE53935);

  @override
  Widget build(BuildContext context) {
    final title = '${row['title'] ?? '—'}';
    final issue = '${row['issueNo'] ?? ''}'.trim();
    final issueLabel =
        issue.isEmpty ? '' : (issue.startsWith('第') ? issue : '第$issue期');
    final display = memberBetMoney(
      row['displayAmount'] ?? row['net'] ?? 0,
      trimZero: true,
    );
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

    return Padding(
      padding: EdgeInsets.symmetric(vertical: 12.h),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 15.sp,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                SizedBox(height: 6.h),
                Text(
                  [
                    if (issueLabel.isNotEmpty) issueLabel,
                    if (timeLabel.isNotEmpty) timeLabel,
                  ].join('  '),
                  style: TextStyle(
                    fontSize: 12.sp,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: 8.w),
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
              SizedBox(height: 8.h),
              Container(
                width: 34.w,
                height: 34.w,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: badgeColor,
                  shape: BoxShape.circle,
                ),
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
        ],
      ),
    );
  }
}
