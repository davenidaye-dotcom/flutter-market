import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../config/theme/app_colors.dart';
import '../../../data/repositories/providers.dart';
import '../../../shared/widgets/app_pull_refresh.dart';
import '../../../shared/widgets/page_app_bar.dart';
import '../../wallet/widgets/date_range_filter.dart';
import '../widgets/agent_ui.dart';

/// 交收下钻 — GET /agent/reports；会员明细 — GET /agent/reports/tickets
class AgentReportQueryPage extends ConsumerStatefulWidget {
  const AgentReportQueryPage({super.key, required this.roomId});
  final String roomId;
  @override
  ConsumerState<AgentReportQueryPage> createState() => _AgentReportQueryPageState();
}

class _AgentReportQueryPageState extends ConsumerState<AgentReportQueryPage> {
  int _quick = 0;
  int _gameIndex = 0;
  int _sourceIndex = 0;
  bool _showGamePicker = false;
  bool _loading = false;
  String? _error;
  DateTime _start = DateTime.now();
  DateTime _end = DateTime.now();
  Map<String, dynamic> _summary = {};
  List<Map<String, dynamic>> _rows = [];
  List<Map<String, String>> _gameOptions = [];

  /// 下钻栈：null = 本级；每层存 {accountId, username}
  final List<Map<String, dynamic>> _drill = [];

  /// 非空 = 当前在看该会员的 tickets
  int? _ticketMemberId;
  String _ticketMemberName = '';

  static const _sourceLabels = ['全部来源', 'Web直属', '房主飞单'];
  static const _sourceKeys = ['ALL', 'WEB_DIRECT', 'OWNER_FLIGHT'];

  String get _gameLabel => _gameIndex == 0
      ? '全部游戏'
      : (_gameIndex - 1 < _gameOptions.length
          ? (_gameOptions[_gameIndex - 1]['typeName'] ?? '全部游戏')
          : '全部游戏');

  String? get _selectedType {
    if (_gameIndex <= 0 || _gameIndex - 1 >= _gameOptions.length) return null;
    final t = _gameOptions[_gameIndex - 1]['type'];
    return (t == null || t.isEmpty) ? null : t;
  }

  String get _selectedSource => _sourceKeys[_sourceIndex];

  int? get _parentAccountId {
    if (_drill.isEmpty) return null;
    final id = _drill.last['accountId'];
    if (id is int) return id;
    return int.tryParse('$id');
  }

  String _fmt(DateTime d) => DateRangeFilter.format(d);

  @override
  void initState() {
    super.initState();
    final range = DateRangeFilter.rangeForQuick(0);
    _start = range.$1;
    _end = range.$2;
    Future.microtask(() async {
      await _loadGames();
      await _load();
    });
  }

  Future<void> _loadGames() async {
    try {
      final options = await ref.read(agentGameOptionsProvider.future);
      if (mounted) setState(() => _gameOptions = options);
    } catch (_) {
      if (mounted) setState(() => _gameOptions = const []);
    }
  }

  Future<void> _pickDate({required bool isStart}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isStart ? _start : _end,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _quick = -1;
      if (isStart) {
        _start = picked;
        if (_end.isBefore(_start)) _end = _start;
      } else {
        _end = picked;
        if (_start.isAfter(_end)) _start = _end;
      }
    });
  }

  void _onQuick(int i) {
    final range = DateRangeFilter.rangeForQuick(i);
    setState(() {
      _quick = i;
      _start = range.$1;
      _end = range.$2;
    });
    _load();
  }

  Future<void> _load({bool fromPull = false}) async {
    if (!fromPull && mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    } else if (mounted) {
      setState(() => _error = null);
    }
    try {
      final repo = ref.read(agentRepositoryProvider);
      final Map<String, dynamic> data;
      if (_ticketMemberId != null) {
        data = await repo.getReportTickets(
          startDate: _fmt(_start),
          endDate: _fmt(_end),
          memberAccountId: _ticketMemberId,
          type: _selectedType,
          source: _selectedSource,
          status: 'ALL',
        );
      } else {
        data = await repo.getReports(
          startDate: _fmt(_start),
          endDate: _fmt(_end),
          type: _selectedType,
          source: _selectedSource,
          parentAccountId: _parentAccountId,
        );
      }
      if (!mounted) return;
      final summary = data['summary'] is Map
          ? Map<String, dynamic>.from(data['summary'] as Map)
          : <String, dynamic>{};
      final raw = data['rows'];
      final rows = raw is List
          ? raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
          : <Map<String, dynamic>>[];
      setState(() {
        _summary = summary;
        _rows = rows;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
      AppToast.error(e.toString());
    }
  }

  void _openDrill(Map<String, dynamic> row) {
    final level = '${row['level'] ?? row['accountType'] ?? ''}'.toUpperCase();
    final id = row['accountId'] is int
        ? row['accountId'] as int
        : int.tryParse('${row['accountId'] ?? ''}');
    if (id == null) return;
    final name = '${row['displayName'] ?? row['username'] ?? id}'.trim();
    final isMember = level.contains('MEMBER') || row['drillable'] == false;
    if (isMember) {
      setState(() {
        _ticketMemberId = id;
        _ticketMemberName = name;
      });
      _load();
      return;
    }
    setState(() {
      _drill.add({'accountId': id, 'username': name});
      _ticketMemberId = null;
    });
    _load();
  }

  void _popDrill() {
    if (_ticketMemberId != null) {
      setState(() {
        _ticketMemberId = null;
        _ticketMemberName = '';
      });
      _load();
      return;
    }
    if (_drill.isEmpty) return;
    setState(() => _drill.removeLast());
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final inTickets = _ticketMemberId != null;
    return Stack(children: [
      AgentPageFrame(
        title: inTickets ? '注单明细' : '报表查询',
        titleOnBar: true,
        onRefresh: () => _load(fromPull: true),
        child: Column(children: [
          Expanded(
            child: AgentBorderBox(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_drill.isNotEmpty || inTickets) ...[
                    _crumbBar(),
                    SizedBox(height: 8.h),
                  ],
                  Wrap(
                    spacing: 6.w,
                    runSpacing: 6.h,
                    children: [
                      for (var i = 0; i < DateRangeFilter.quickLabels.length; i++)
                        AgentReportQuickBtn(
                          label: DateRangeFilter.quickLabels[i],
                          active: _quick == i,
                          onTap: () => _onQuick(i),
                        ),
                    ],
                  ),
                  SizedBox(height: 10.h),
                  Row(children: [
                    Expanded(child: _dateField(_start, () => _pickDate(isStart: true))),
                    SizedBox(width: 8.w),
                    Expanded(child: _dateField(_end, () => _pickDate(isStart: false))),
                  ]),
                  SizedBox(height: 10.h),
                  Row(children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => _showGamePicker = true),
                        child: Container(
                          height: 36.h,
                          padding: EdgeInsets.symmetric(horizontal: 10.w),
                          decoration: BoxDecoration(border: Border.all(color: const Color(0xFFAAAAAA))),
                          child: Row(children: [
                            Expanded(child: Text(_gameLabel, style: TextStyle(fontSize: 13.sp))),
                            Icon(Icons.arrow_drop_down, size: 20.sp),
                          ]),
                        ),
                      ),
                    ),
                    SizedBox(width: 8.w),
                    Expanded(
                      child: GestureDetector(
                        onTap: () async {
                          final i = await showModalBottomSheet<int>(
                            context: context,
                            backgroundColor: Colors.white,
                            builder: (ctx) => SafeArea(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  for (var j = 0; j < _sourceLabels.length; j++)
                                    ListTile(
                                      title: Text(_sourceLabels[j]),
                                      onTap: () => Navigator.pop(ctx, j),
                                    ),
                                ],
                              ),
                            ),
                          );
                          if (i != null) setState(() => _sourceIndex = i);
                        },
                        child: Container(
                          height: 36.h,
                          padding: EdgeInsets.symmetric(horizontal: 10.w),
                          decoration: BoxDecoration(border: Border.all(color: const Color(0xFFAAAAAA))),
                          child: Row(children: [
                            Expanded(
                              child: Text(_sourceLabels[_sourceIndex], style: TextStyle(fontSize: 13.sp)),
                            ),
                            Icon(Icons.arrow_drop_down, size: 20.sp),
                          ]),
                        ),
                      ),
                    ),
                    SizedBox(width: 8.w),
                    AgentTealButton(
                      label: '查询',
                      onTap: () {
                        setState(() => _showGamePicker = false);
                        _load();
                      },
                    ),
                  ]),
                  SizedBox(height: 12.h),
                  inTickets ? _ticketSummaryBar() : _summaryBar(),
                  SizedBox(height: 8.h),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(border: Border.all(color: const Color(0xFFCCCCCC))),
                      child: AppPullRefresh(
                        onRefresh: () => _load(fromPull: true),
                        child: _loading && _rows.isEmpty
                            ? ListView(
                                physics: const AlwaysScrollableScrollPhysics(),
                                children: const [
                                  SizedBox(height: 120),
                                  Center(child: CircularProgressIndicator()),
                                ],
                              )
                            : _error != null && _rows.isEmpty
                                ? ListView(
                                    physics: const AlwaysScrollableScrollPhysics(),
                                    children: [
                                      SizedBox(height: 120.h),
                                      Center(
                                        child: GestureDetector(
                                          onTap: _load,
                                          child: Text(
                                            '加载失败，点击重试',
                                            style: TextStyle(fontSize: 14.sp, color: AppColors.danger),
                                          ),
                                        ),
                                      ),
                                    ],
                                  )
                                : _rows.isEmpty
                                    ? ListView(
                                        physics: const AlwaysScrollableScrollPhysics(),
                                        children: [
                                          SizedBox(height: 120.h),
                                          Center(
                                            child: Text(
                                              '暂无数据',
                                              style: TextStyle(fontSize: 14.sp, color: AppColors.textHint),
                                            ),
                                          ),
                                        ],
                                      )
                                    : CustomScrollView(
                                        physics: const AlwaysScrollableScrollPhysics(),
                                        slivers: [
                                          SliverToBoxAdapter(
                                            child: inTickets ? _ticketHeader() : _drillHeader(),
                                          ),
                                          SliverList(
                                            delegate: SliverChildBuilderDelegate(
                                              (_, i) => inTickets
                                                  ? _ticketRow(_rows[i], i)
                                                  : _drillRow(_rows[i], i),
                                              childCount: _rows.length,
                                            ),
                                          ),
                                        ],
                                      ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SizedBox(height: 8.h),
        ]),
      ),
      if (_showGamePicker)
        Positioned.fill(
          child: AgentGamePickerOverlay(
            games: ['全部游戏', ..._gameOptions.map((e) => e['typeName'] ?? e['type'] ?? '')],
            selectedIndex: _gameIndex,
            onSelect: (i) => setState(() {
              _gameIndex = i;
              _showGamePicker = false;
            }),
            onDismiss: () => setState(() => _showGamePicker = false),
          ),
        ),
    ]);
  }

  Widget _crumbBar() {
    final parts = <String>['本级'];
    for (final d in _drill) {
      parts.add('${d['username'] ?? d['accountId']}');
    }
    if (_ticketMemberId != null) {
      parts.add(_ticketMemberName.isEmpty ? '$_ticketMemberId' : _ticketMemberName);
    }
    return Row(
      children: [
        GestureDetector(
          onTap: _popDrill,
          child: Icon(Icons.arrow_back_ios, size: 14.sp, color: AppColors.navBlue),
        ),
        SizedBox(width: 4.w),
        Expanded(
          child: Text(
            parts.join(' / '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12.sp, color: AppColors.textSecondary),
          ),
        ),
      ],
    );
  }

  Widget _summaryBar() {
    if (_summary.isEmpty) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 8.h),
      color: const Color(0xFFF5F5F5),
      child: Wrap(
        spacing: 12.w,
        runSpacing: 4.h,
        children: [
          _summaryItem('下注', _summary['betAmount']),
          _summaryItem('有效', _summary['validAmount']),
          _summaryItem('笔数', _summary['orderCount']),
          _summaryItem('人数', _summary['peopleCount']),
          _summaryItem('占成盈亏', _summary['sharePnl'] ?? _summary['shareAmount']),
          _summaryItem('返水净额', _summary['rebateNet'] ?? _summary['rebate']),
          _summaryItem('综合盈亏', _summary['combinedPnl'] ?? _summary['winLoss']),
          _summaryItem('上交货量', _summary['uplinkVolume']),
          _summaryItem('上级交收', _summary['uplinkSettlement']),
        ],
      ),
    );
  }

  Widget _ticketSummaryBar() {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 8.h),
      color: const Color(0xFFF5F5F5),
      child: Text(
        '$_ticketMemberName · ${_rows.length} 条',
        style: TextStyle(fontSize: 12.sp, color: AppColors.textSecondary),
      ),
    );
  }

  Widget _summaryItem(String label, dynamic value) {
    return Text(
      '$label: ${_numStr(value)}',
      style: TextStyle(fontSize: 12.sp, color: AppColors.textSecondary),
    );
  }

  Widget _drillHeader() {
    return Container(
      color: const Color(0xFFE8E8E8),
      padding: EdgeInsets.symmetric(vertical: 8.h),
      child: Row(
        children: [
          _headerCell('账号', flex: 3),
          _headerCell('层级', flex: 2),
          _headerCell('下注', flex: 2),
          _headerCell('有效', flex: 2),
          _headerCell('综合盈亏', flex: 2),
        ],
      ),
    );
  }

  Widget _drillRow(Map<String, dynamic> row, int index) {
    final name = '${row['displayName'] ?? row['username'] ?? row['accountId'] ?? '—'}';
    final level = '${row['levelName'] ?? row['level'] ?? '—'}';
    final canTap = row['drillable'] == true ||
        '${row['level'] ?? ''}'.toUpperCase().contains('MEMBER') ||
        row['accountId'] != null;
    return InkWell(
      onTap: canTap ? () => _openDrill(row) : null,
      child: Container(
        decoration: BoxDecoration(
          color: index.isOdd ? const Color(0xFFFAFAFA) : Colors.white,
          border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
        ),
        padding: EdgeInsets.symmetric(vertical: 8.h),
        child: Row(
          children: [
            _bodyCell(name, flex: 3, color: canTap ? AppColors.navBlue : null),
            _bodyCell(level, flex: 2),
            _bodyCell(_numStr(row['betAmount']), flex: 2),
            _bodyCell(_numStr(row['validAmount']), flex: 2),
            _bodyCell(
              _numStr(row['combinedPnl'] ?? row['sharePnl'] ?? row['memberWin']),
              flex: 2,
            ),
          ],
        ),
      ),
    );
  }

  Widget _ticketHeader() {
    return Container(
      color: const Color(0xFFE8E8E8),
      padding: EdgeInsets.symmetric(vertical: 8.h),
      child: Row(
        children: [
          _headerCell('期号', flex: 2),
          _headerCell('玩法', flex: 3),
          _headerCell('金额', flex: 2),
          _headerCell('结果', flex: 2),
          _headerCell('状态', flex: 2),
        ],
      ),
    );
  }

  Widget _ticketRow(Map<String, dynamic> row, int index) {
    return Container(
      decoration: BoxDecoration(
        color: index.isOdd ? const Color(0xFFFAFAFA) : Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
      ),
      padding: EdgeInsets.symmetric(vertical: 8.h),
      child: Row(
        children: [
          _bodyCell(row['issueNo']?.toString() ?? '—', flex: 2),
          _bodyCell(
            row['contentOdds']?.toString() ??
                row['playName']?.toString() ??
                row['gameName']?.toString() ??
                '—',
            flex: 3,
          ),
          _bodyCell(_numStr(row['amount']), flex: 2),
          _bodyCell(_numStr(row['itemResult'] ?? row['selfResult']), flex: 2),
          _bodyCell(_bizStatusLabel(row['status']?.toString()), flex: 2),
        ],
      ),
    );
  }

  String _bizStatusLabel(String? s) {
    switch (s?.toUpperCase()) {
      case 'PENDING':
        return '未结';
      case 'SETTLED':
        return '已结';
      case 'CANCELLED':
        return '取消';
      default:
        return s?.isNotEmpty == true ? s! : '—';
    }
  }

  Widget _headerCell(String text, {required int flex}) => Expanded(
        flex: flex,
        child: Text(text, textAlign: TextAlign.center, style: TextStyle(fontSize: 11.sp, fontWeight: FontWeight.w600)),
      );

  Widget _bodyCell(String text, {required int flex, Color? color}) => Expanded(
        flex: flex,
        child: Text(
          text,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 11.sp, color: color ?? AppColors.textPrimary),
        ),
      );

  Widget _dateField(DateTime d, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 36.h,
        padding: EdgeInsets.symmetric(horizontal: 8.w),
        decoration: BoxDecoration(border: Border.all(color: const Color(0xFFAAAAAA))),
        child: Row(children: [
          Icon(Icons.access_time, size: 16.sp, color: AppColors.textHint),
          SizedBox(width: 6.w),
          Text(_fmt(d), style: TextStyle(fontSize: 13.sp)),
        ]),
      ),
    );
  }
}

String _numStr(dynamic v) {
  if (v == null) return '0';
  if (v is num) {
    if (v == v.roundToDouble()) return '${v.toInt()}';
    return v.toStringAsFixed(2);
  }
  return v.toString();
}
