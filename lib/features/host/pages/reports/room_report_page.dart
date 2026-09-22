import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../../config/theme/app_colors.dart';
import '../../../../data/repositories/providers.dart';
import '../../../../shared/widgets/app_pull_refresh.dart';
import '../../../../shared/widgets/page_app_bar.dart';
import '../../../../shared/widgets/user_avatar.dart';
import '../../data/host_mock.dart';
import '../../widgets/host_ui.dart';
import 'player_period_report_page.dart';
import 'report_date_bar.dart';

/// 房间报表（截图「玩家报表」）— 汇总 + 玩家列表，点进期数报表
class RoomReportPage extends ConsumerStatefulWidget {
  const RoomReportPage({super.key, required this.roomId});

  final String roomId;

  @override
  ConsumerState<RoomReportPage> createState() => _RoomReportPageState();
}

class _RoomReportPageState extends ConsumerState<RoomReportPage>
    with ReportDatePageMixin {
  static const _pageSize = 20;
  static const _valueRed = Color(0xFFE53935);

  Map<String, dynamic> _summary = {};
  List<Map<String, dynamic>> _players = [];
  int _pageNum = 1;
  int _total = 0;
  bool _loading = false;
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

  @override
  void onReportQuery() => _load(reset: true);

  void _onScroll() {
    if (!_hasMore || _loadingMore || _loading) return;
    if (!_scroll.hasClients) return;
    final pos = _scroll.position;
    if (pos.pixels >= pos.maxScrollExtent - 80) {
      _load(reset: false);
    }
  }

  Future<void> _load({required bool reset}) async {
    if (reset) {
      setState(() {
        _loading = true;
        _pageNum = 1;
        _hasMore = true;
        _players = [];
      });
    } else {
      if (!_hasMore || _loadingMore) return;
      setState(() => _loadingMore = true);
    }

    final page = reset ? 1 : _pageNum + 1;
    try {
      final data = await ref.read(ownerRepositoryProvider).getRoomPlayerReport(
            startDate: apiStartDate,
            endDate: apiEndDate,
            pageNum: page,
            pageSize: _pageSize,
          );
      if (!mounted) return;
      final summary = data['summary'];
      final rows = data['rows'];
      final list = rows is List
          ? rows.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
          : <Map<String, dynamic>>[];
      final total = _asInt(data['total']) ?? list.length;
      setState(() {
        if (summary is Map) {
          _summary = Map<String, dynamic>.from(summary);
        } else if (reset) {
          _summary = {};
        }
        _players = reset ? list : [..._players, ...list];
        _pageNum = page;
        _total = total;
        _hasMore = _players.length < total && list.isNotEmpty;
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
    return fraction == 0 ? '0' : '0';
  }

  Color _pnlColor(String text) {
    final n = double.tryParse(text.replaceAll(',', '')) ?? 0;
    if (n < 0) return _valueRed;
    return AppColors.textPrimary;
  }

  @override
  Widget build(BuildContext context) {
    final turnover = _pick(['turnover']);
    final rebate = _pick(['rebatePaid']);
    final gamePnl = _pick(['gamePnl']);
    final agentWelfare = _pick(['agentWelfare']);
    final totalPnl = _pick(['totalPnl']);

    return HostSubPageScaffold(
      title: '房间报表',
      body: Column(
        children: [
          SizedBox(height: 8.h),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.w),
            child: _SummaryCard(
              turnover: turnover,
              rebate: rebate,
              gamePnl: gamePnl,
              gamePnlColor: _pnlColor(gamePnl),
              agentWelfare: agentWelfare,
              totalPnl: totalPnl,
              totalPnlColor: _pnlColor(totalPnl),
            ),
          ),
          SizedBox(height: 10.h),
          ReportDateBar(
            quickIndex: quickIndex,
            start: start,
            end: end,
            onQuickTap: onQuickTap,
            onCustomTap: pickCustomRange,
          ),
          SizedBox(height: 10.h),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : AppPullRefresh(
                    onRefresh: () => _load(reset: true),
                    child: _players.isEmpty
                        ? ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            children: [
                              SizedBox(height: 120.h),
                              Center(
                                child: Text(
                                  '暂无玩家数据',
                                  style: TextStyle(fontSize: 14.sp, color: AppColors.textHint),
                                ),
                              ),
                            ],
                          )
                        : ListView.builder(
                            controller: _scroll,
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: EdgeInsets.fromLTRB(16.w, 0, 16.w, 16.h),
                            itemCount: _players.length + 1,
                            itemBuilder: (_, i) {
                              if (i == _players.length) {
                                return Padding(
                                  padding: EdgeInsets.only(top: 12.h, bottom: 8.h),
                                  child: Center(
                                    child: Text(
                                      _loadingMore
                                          ? '加载中…'
                                          : '没有更多了，共 ${_total > 0 ? _total : _players.length} 条',
                                      style: TextStyle(fontSize: 12.sp, color: AppColors.textHint),
                                    ),
                                  ),
                                );
                              }
                              final p = _players[i];
                              return Padding(
                                padding: EdgeInsets.only(bottom: 10.h),
                                child: _PlayerCard(
                                  row: p,
                                  onTap: () {
                                    final id = '${p['accountId'] ?? p['memberId'] ?? p['userId'] ?? ''}';
                                    final name = '${p['nickname'] ?? p['username'] ?? p['displayName'] ?? id}';
                                    if (id.isEmpty) return;
                                    pushHostPage(
                                      context,
                                      PlayerPeriodReportPage(
                                        roomId: widget.roomId,
                                        accountId: id,
                                        displayName: name,
                                        initialStart: omitDates ? null : start,
                                        initialEnd: omitDates ? null : end,
                                        initialQuickIndex: quickIndex,
                                      ),
                                    );
                                  },
                                ),
                              );
                            },
                          ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.turnover,
    required this.rebate,
    required this.gamePnl,
    required this.gamePnlColor,
    required this.agentWelfare,
    required this.totalPnl,
    required this.totalPnlColor,
  });

  final String turnover;
  final String rebate;
  final String gamePnl;
  final Color gamePnlColor;
  final String agentWelfare;
  final String totalPnl;
  final Color totalPnlColor;

  @override
  Widget build(BuildContext context) {
    return HostWhiteCard(
      padding: EdgeInsets.fromLTRB(14.w, 14.h, 10.w, 14.h),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(child: _Metric(label: '流水', value: turnover)),
                    Expanded(child: _Metric(label: '回水合计', value: rebate)),
                  ],
                ),
                SizedBox(height: 12.h),
                Row(
                  children: [
                    Expanded(
                      child: _Metric(label: '游戏盈亏', value: gamePnl, valueColor: gamePnlColor),
                    ),
                    Expanded(child: _Metric(label: '代理福利', value: agentWelfare)),
                  ],
                ),
              ],
            ),
          ),
          Container(
            width: 1,
            height: 64.h,
            margin: EdgeInsets.symmetric(horizontal: 8.w),
            color: const Color(0xFFEEEEEE),
          ),
          Expanded(
            flex: 2,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '总盈亏',
                  style: TextStyle(fontSize: 12.sp, color: AppColors.textSecondary),
                ),
                SizedBox(height: 6.h),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    totalPnl,
                    style: TextStyle(
                      fontSize: 22.sp,
                      fontWeight: FontWeight.w700,
                      color: totalPnlColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value, this.valueColor});

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 12.sp, color: AppColors.textSecondary)),
        SizedBox(height: 4.h),
        Text(
          value,
          style: TextStyle(
            fontSize: 16.sp,
            fontWeight: FontWeight.w700,
            color: valueColor ?? AppColors.textPrimary,
          ),
        ),
      ],
    );
  }
}

class _PlayerCard extends StatelessWidget {
  const _PlayerCard({required this.row, required this.onTap});

  final Map<String, dynamic> row;
  final VoidCallback onTap;

  static const _green = Color(0xFF2E9E5B);

  String _n(List<String> keys) {
    for (final k in keys) {
      if (row[k] != null) return hostNumStr(row[k], fraction: 2);
    }
    return '0';
  }

  @override
  Widget build(BuildContext context) {
    final name = '${row['nickname'] ?? row['username'] ?? row['displayName'] ?? '—'}';
    final id = '${row['accountId'] ?? row['memberId'] ?? row['userId'] ?? ''}';
    final avatar = '${row['avatar'] ?? row['avatarUrl'] ?? ''}';
    final bet = _n(['betAmount']);
    final gameResult = _n(['gameResult']);
    final returned = _n(['rebatePaid']);
    final pending = _n(['rebatePending']);
    final playerResult = _n(['playerResult']);

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12.r),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12.r),
        child: Padding(
          padding: EdgeInsets.fromLTRB(12.w, 12.h, 8.w, 12.h),
          child: Column(
            children: [
              Row(
                children: [
                  UserAvatar(
                    codeOrUrl: avatar,
                    radius: 18.r,
                    backgroundColor: const Color(0xFFBDE0FE),
                  ),
                  SizedBox(width: 10.w),
                  Expanded(
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w700),
                          ),
                        ),
                        SizedBox(width: 8.w),
                        Text(
                          'ID: $id',
                          style: TextStyle(fontSize: 12.sp, color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right, size: 20.sp, color: AppColors.textHint),
                ],
              ),
              SizedBox(height: 12.h),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _kv('注额', bet),
                        SizedBox(height: 8.h),
                        _kv('游戏结果', gameResult),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _kv('已返', returned),
                        SizedBox(height: 8.h),
                        _kv('待返', pending),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _kv('玩家结果', playerResult),
                      ],
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

  Widget _kv(String label, String value) {
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '$label ',
            style: TextStyle(fontSize: 13.sp, color: AppColors.textPrimary),
          ),
          TextSpan(
            text: value,
            style: TextStyle(fontSize: 13.sp, color: _green, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
