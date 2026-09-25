import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../config/theme/app_colors.dart';
import '../../../data/repositories/providers.dart';
import '../../../shared/format/display_number.dart';
import '../../../shared/widgets/app_pull_refresh.dart';
import '../../../shared/widgets/page_app_bar.dart';
import '../../wallet/widgets/date_range_filter.dart';
import '../widgets/agent_ui.dart';
import '../../../shared/widgets/app_page_loading.dart';

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
  bool _loading = false;
  String? _error;
  late DateTime _start;
  late DateTime _end;
  List<DateRangeQuickItem> _quickItems = DateRangeFilter.buildQuickItems();
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
  static const _fallbackGames = <Map<String, String>>[
    {'type': 'JS_SC', 'typeName': '极速赛车'},
    {'type': 'AZXY10', 'typeName': '澳洲幸运10'},
  ];

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
    _quickItems = DateRangeFilter.buildQuickItems();
    _quick = 0;
    _start = _quickItems[0].start;
    _end = _quickItems[0].end;
    Future.microtask(() async {
      await _loadGames();
      await _load();
    });
  }

  Future<void> _loadGames() async {
    try {
      final options = await ref.read(agentGameOptionsProvider.future);
      if (!mounted) return;
      setState(() => _gameOptions = options.isEmpty ? _fallbackGames : options);
    } catch (e) {
      if (!mounted) return;
      setState(() => _gameOptions = _fallbackGames);
      AppToast.error(e.toString());
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
    if (i < 0 || i >= _quickItems.length) return;
    final it = _quickItems[i];
    setState(() {
      _quick = i;
      _start = it.start;
      _end = it.end;
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
    return AgentPageFrame(
        title: inTickets ? '注单明细' : '报表查询',
        titleOnBar: true,
        onRefresh: () => _load(fromPull: true),
        child: ColoredBox(
          color: const Color(0xFFF4F7FB),
          child: Column(children: [
            Expanded(
              child: Padding(
                padding: EdgeInsets.fromLTRB(12.w, 10.h, 12.w, 8.h),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_drill.isNotEmpty || inTickets) ...[
                      _crumbBar(),
                      SizedBox(height: 8.h),
                    ],
                    _filterCard(),
                    SizedBox(height: 10.h),
                    if (!inTickets) _summaryCard() else _ticketSummaryBar(),
                    SizedBox(height: 10.h),
                    Expanded(child: _resultList(inTickets)),
                  ],
                ),
              ),
            ),
          ]),
        ),
    );
  }

  Widget _filterCard() {
    return _surface(
      child: Column(
        children: [
          Wrap(
            spacing: 8.w,
            runSpacing: 8.h,
            children: [
              for (var i = 0; i < _quickItems.length; i++)
                AgentReportQuickBtn(
                  label: _quickItems[i].label,
                  active: _quick == i,
                  onTap: () => _onQuick(i),
                ),
            ],
          ),
          SizedBox(height: 12.h),
          Row(children: [
            Expanded(child: _dateField(_start, () => _pickDate(isStart: true))),
            SizedBox(width: 8.w),
            Expanded(child: _dateField(_end, () => _pickDate(isStart: false))),
          ]),
          SizedBox(height: 12.h),
          Row(children: [
            Expanded(child: _dropField(_gameLabel, _pickGame)),
            SizedBox(width: 8.w),
            Expanded(child: _dropField(_sourceLabels[_sourceIndex], _pickSource)),
            SizedBox(width: 8.w),
            GestureDetector(
              onTap: _load,
              child: Container(
                height: 40.h,
                padding: EdgeInsets.symmetric(horizontal: 16.w),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xFF4E9BA3),
                  borderRadius: BorderRadius.circular(10.r),
                ),
                child: Text(
                  '查询',
                  style: TextStyle(fontSize: 14.sp, color: Colors.white, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ]),
        ],
      ),
    );
  }

  Future<void> _pickGame() async {
    if (_gameOptions.isEmpty) await _loadGames();
    if (!mounted) return;
    final labels = ['全部游戏', ..._gameOptions.map((e) => e['typeName'] ?? e['type'] ?? '')];
    final i = await _pickSheet(labels, _gameIndex);
    if (i != null) setState(() => _gameIndex = i);
  }

  Future<void> _pickSource() async {
    final i = await _pickSheet(_sourceLabels, _sourceIndex);
    if (i != null) setState(() => _sourceIndex = i);
  }

  Future<int?> _pickSheet(List<String> labels, int selected) {
    return showModalBottomSheet<int>(
      context: context,
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16.r)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(height: 8.h),
            for (var j = 0; j < labels.length; j++)
              ListTile(
                title: Text(labels[j]),
                trailing: j == selected ? Icon(Icons.check, color: AppColors.navBlue) : null,
                onTap: () => Navigator.pop(ctx, j),
              ),
          ],
        ),
      ),
    );
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

  Widget _summaryCard() {
    if (_summary.isEmpty) return const SizedBox.shrink();
    final grid = <(String, dynamic, bool)>[
      ('下注', _summary['betAmount'], false),
      ('有效', _summary['validAmount'], false),
      ('笔数', _summary['orderCount'], false),
      ('人数', _summary['peopleCount'], false),
      ('占成盈亏', _summary['sharePnl'] ?? _summary['shareAmount'], true),
      ('上交货量', _summary['uplinkVolume'], false),
    ];
    return _surface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < grid.length; i += 3) ...[
            if (i > 0) SizedBox(height: 12.h),
            Row(
              children: [
                for (var j = 0; j < 3; j++)
                  Expanded(
                    child: i + j < grid.length
                        ? AgentMetric(label: grid[i + j].$1, value: grid[i + j].$2, signed: grid[i + j].$3)
                        : const SizedBox.shrink(),
                  ),
              ],
            ),
          ],
          SizedBox(height: 8.h),
          Row(
            children: [
              Expanded(child: _pair('返水净额', _summary['rebateNet'] ?? _summary['rebate'], signed: true)),
              SizedBox(width: 8.w),
              Expanded(child: _pair('综合盈亏', _summary['combinedPnl'] ?? _summary['winLoss'], signed: true)),
            ],
          ),
          SizedBox(height: 6.h),
          Row(
            children: [
              Expanded(child: _pair('上级交收', _summary['uplinkSettlement'], signed: true)),
              SizedBox(width: 8.w),
              Expanded(child: _pair('会员输赢', _summary['winLoss'], signed: true)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _ticketSummaryBar() {
    return _surface(
      padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 12.h),
      child: Text(
        '$_ticketMemberName · ${_rows.length} 条',
        style: TextStyle(fontSize: 13.sp, color: AppColors.textSecondary, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _resultList(bool inTickets) {
    return AppPullRefresh(
      onRefresh: () => _load(fromPull: true),
      child: _loading && _rows.isEmpty
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: const [
                SizedBox(height: 80),
                AppPageLoading(),
              ],
            )
          : _error != null && _rows.isEmpty
              ? ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                    SizedBox(height: 80.h),
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
                        SizedBox(height: 80.h),
                        Center(
                          child: Text(
                            '暂无数据',
                            style: TextStyle(fontSize: 14.sp, color: AppColors.textHint),
                          ),
                        ),
                      ],
                    )
                  : ListView.separated(
                      physics: const AlwaysScrollableScrollPhysics(),
                      itemCount: _rows.length,
                      separatorBuilder: (_, _) => SizedBox(height: 8.h),
                      itemBuilder: (_, i) => inTickets ? _ticketCard(_rows[i]) : _memberCard(_rows[i]),
                    ),
    );
  }

  Widget _memberCard(Map<String, dynamic> row) {
    final name = '${row['displayName'] ?? row['username'] ?? row['accountId'] ?? '—'}';
    final level = '${row['levelName'] ?? row['level'] ?? '—'}';
    final canTap = row['drillable'] == true ||
        '${row['level'] ?? ''}'.toUpperCase().contains('MEMBER') ||
        row['accountId'] != null;
    final pnl = row['combinedPnl'] ?? row['sharePnl'] ?? row['memberWin'];
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12.r),
        onTap: canTap ? () => _openDrill(row) : null,
        child: _surface(
          padding: EdgeInsets.fromLTRB(12.w, 10.h, 12.w, 10.h),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15.sp,
                        fontWeight: FontWeight.w700,
                        color: canTap ? AppColors.navBlue : const Color(0xFF222222),
                      ),
                    ),
                  ),
                  SizedBox(width: 8.w),
                  Text(level, style: TextStyle(fontSize: 11.sp, color: AppColors.textSecondary)),
                  SizedBox(width: 8.w),
                  Text('占成 ${_ratioText(row['shareRatio'])}', style: TextStyle(fontSize: 11.sp, color: AppColors.textSecondary)),
                  SizedBox(width: 8.w),
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: Text(
                        '余额 ${row['balance'] == null ? '—' : displayNumber(row['balance'])}',
                        maxLines: 1,
                        softWrap: false,
                        style: TextStyle(fontSize: 11.sp, color: AppColors.textSecondary),
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 8.h),
              Row(
                children: [
                  Expanded(child: _pair('下注', row['betAmount'])),
                  SizedBox(width: 8.w),
                  Expanded(child: _pair('有效', row['validAmount'])),
                  SizedBox(width: 8.w),
                  Expanded(child: _pair('笔数', row['orderCount'])),
                ],
              ),
              SizedBox(height: 6.h),
              Row(
                children: [
                  Expanded(child: _pair('占成盈亏', row['sharePnl'], signed: true)),
                  SizedBox(width: 8.w),
                  Expanded(child: _pair('上交货量', row['uplinkVolume'])),
                ],
              ),
              SizedBox(height: 6.h),
              Row(
                children: [
                  Expanded(child: _pair('综合盈亏', pnl, signed: true)),
                  SizedBox(width: 8.w),
                  Expanded(child: _pair('返水净额', row['rebateNet'], signed: true)),
                ],
              ),
              SizedBox(height: 6.h),
              _pair('上级交收', row['uplinkSettlement'], signed: true),
            ],
          ),
        ),
      ),
    );
  }

  Widget _pair(String label, dynamic value, {bool signed = false}) {
    final text = value == null ? '—' : displayNumber(value);
    final n = num.tryParse(text) ?? 0;
    final color = !signed
        ? AgentChrome.ink
        : n > 0
            ? AgentChrome.pnlUp
            : n < 0
                ? AppColors.danger
                : AgentChrome.ink;
    return Row(
      children: [
        Text(
          label,
          maxLines: 1,
          softWrap: false,
          style: TextStyle(fontSize: 11.sp, color: AppColors.textSecondary),
        ),
        SizedBox(width: 4.w),
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              text,
              maxLines: 1,
              softWrap: false,
              style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w700, color: color),
            ),
          ),
        ),
      ],
    );
  }

  String _ratioText(dynamic value) {
    if (value == null) return '—';
    final n = value is num ? value.toDouble() : double.tryParse('$value'.trim());
    if (n == null) return '—';
    final pct = n.abs() <= 1 ? n * 100 : n;
    return '${displayNumber(pct)}%';
  }

  Widget _ticketCard(Map<String, dynamic> row) {
    final play = row['contentOdds']?.toString() ??
        row['playName']?.toString() ??
        row['gameName']?.toString() ??
        '—';
    return _surface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  row['issueNo']?.toString() ?? '—',
                  style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w700),
                ),
              ),
              Text(
                _bizStatusLabel(row['status']?.toString()),
                style: TextStyle(fontSize: 12.sp, color: AppColors.textSecondary),
              ),
            ],
          ),
          SizedBox(height: 6.h),
          Text(play, style: TextStyle(fontSize: 13.sp, color: const Color(0xFF333333))),
          SizedBox(height: 12.h),
          Row(
            children: [
              Expanded(child: AgentMetric(label: '金额', value: row['amount'])),
              Expanded(child: AgentMetric(label: '结果', value: row['itemResult'] ?? row['selfResult'], signed: true)),
            ],
          ),
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

  Widget _surface({required Widget child, EdgeInsetsGeometry? padding}) {
    return Container(
      width: double.infinity,
      padding: padding ?? EdgeInsets.fromLTRB(12.w, 12.h, 12.w, 12.h),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(color: const Color(0xFFE3E8EF)),
      ),
      child: child,
    );
  }

  Widget _dropField(String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 40.h,
        padding: EdgeInsets.symmetric(horizontal: 10.w),
        decoration: BoxDecoration(
          color: const Color(0xFFF7F9FC),
          borderRadius: BorderRadius.circular(10.r),
          border: Border.all(color: const Color(0xFFE3E8EF)),
        ),
        child: Row(children: [
          Expanded(
            child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13.sp)),
          ),
          Icon(Icons.keyboard_arrow_down, size: 18.sp, color: AppColors.textHint),
        ]),
      ),
    );
  }

  Widget _dateField(DateTime d, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 40.h,
        padding: EdgeInsets.symmetric(horizontal: 10.w),
        decoration: BoxDecoration(
          color: const Color(0xFFF7F9FC),
          borderRadius: BorderRadius.circular(10.r),
          border: Border.all(color: const Color(0xFFE3E8EF)),
        ),
        child: Row(children: [
          Icon(Icons.calendar_today_outlined, size: 14.sp, color: AppColors.textHint),
          SizedBox(width: 6.w),
          Text(_fmt(d), style: TextStyle(fontSize: 13.sp)),
        ]),
      ),
    );
  }
}

