import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../config/theme/app_colors.dart';
import '../../../data/repositories/providers.dart';
import '../../../shared/format/display_number.dart';
import '../../../shared/format/play_title.dart';
import '../../../shared/widgets/app_pull_refresh.dart';
import '../../../shared/widgets/emulator_safe_text_field.dart';
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
  bool _panelOpen = true;
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

  /// 注单期汇总下钻：`issueNo|gameType`；null = 期列表
  String? _ticketIssueKey;
  String _ticketIssueNo = '';
  String _ticketGameType = '';
  Map<String, dynamic> _ticketIssueSummary = {};
  int _page = 1;
  int _totalPages = 0;
  int _total = 0;
  int _loadGen = 0;
  /// 点过查询后才生效的期号。翻页不读输入框里还没提交的内容。
  String? _activeIssue;
  static const _pageSize = 20;
  final _issueCtrl = TextEditingController();

  static const _sourceLabels = ['全部来源', 'Web直属', '房主飞单'];
  static const _sourceKeys = ['ALL', 'WEB_DIRECT', 'OWNER_FLIGHT'];
  static const _fallbackGames = <Map<String, String>>[
    {'type': 'JS_SC', 'typeName': '极速赛车'},
    {'type': 'AZXY10', 'typeName': '澳洲幸运10'},
    {'type': 'TW_BG_Q', 'typeName': '宾果赛车(前)'},
    {'type': 'TW_BG_H', 'typeName': '宾果赛车(后)'},
    {'type': 'JS_FT', 'typeName': '极速飞艇'},
    {'type': 'CA_PC28', 'typeName': '加拿大PC28'},
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

  late final AppBackLayer _drillBack = AppBackLayer(
    () {
      if (!mounted || (_drill.isEmpty && _ticketMemberId == null)) return false;
      if (!appBackLayerActive(context)) return false;
      _popDrill();
      return true;
    },
    navigatorOf: () => mounted ? Navigator.of(context) : null,
  );

  void _syncDrillBack() {
    if (_drill.isNotEmpty || _ticketMemberId != null) {
      registerAppBackLayer(_drillBack);
    } else {
      unregisterAppBackLayer(_drillBack);
    }
  }

  @override
  void dispose() {
    unregisterAppBackLayer(_drillBack);
    _issueCtrl.dispose();
    super.dispose();
  }

  String? _issueQuery() {
    final text = _issueCtrl.text.trim();
    return text.isEmpty ? null : text;
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
      _page = 1;
    });
    _load(applyQuery: true);
  }

  void _search() {
    setState(() => _page = 1);
    _load(applyQuery: true);
  }

  void _applyPage(Map<String, dynamic> data, int rowCount) {
    final total = data['total'] is num ? (data['total'] as num).toInt() : rowCount;
    final pageSize = data['pageSize'] is num ? (data['pageSize'] as num).toInt() : _pageSize;
    _total = total;
    _totalPages = pageSize <= 0 ? 0 : ((total + pageSize - 1) ~/ pageSize);
  }

  Future<void> _load({bool fromPull = false, bool applyQuery = false}) async {
    if (applyQuery) _activeIssue = _issueQuery();
    if (_ticketMemberId != null) {
      if (_ticketIssueKey != null) {
        // 只有点查询或快捷日期才改当前期。翻页和下拉刷新保持已打开的期。
        if (applyQuery) {
          final typed = _activeIssue;
          final issueChanged = typed != null && typed != _ticketIssueNo;
          final prevGame = _ticketGameType;
          if (typed != null) _ticketIssueNo = typed;
          if (_selectedType != null) {
            _ticketGameType = _selectedType!;
          } else if (issueChanged) {
            _ticketGameType = '';
          }
          _ticketIssueKey = '$_ticketIssueNo|$_ticketGameType';
          // 期号或彩种变了就先清掉上一期的注单，失败时不能还挂着旧数据。
          if (issueChanged || _ticketGameType != prevGame) {
            _rows = [];
            _ticketIssueSummary = {};
            _total = 0;
            _totalPages = 0;
          }
        }
        await _loadTicketDetails(fromPull: fromPull);
      } else {
        await _loadTicketIssues(fromPull: fromPull);
      }
      return;
    }
    final gen = ++_loadGen;
    if (!fromPull && mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    } else if (mounted) {
      setState(() => _error = null);
    }
    try {
      final data = await ref.read(agentRepositoryProvider).getReports(
            startDate: _fmt(_start),
            endDate: _fmt(_end),
            type: _selectedType,
            source: _selectedSource,
            parentAccountId: _parentAccountId,
            issueNo: _activeIssue,
            pageNum: _page,
            pageSize: _pageSize,
          );
      if (!mounted || gen != _loadGen) return;
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
        _ticketIssueSummary = {};
        _applyPage(data, rows.length);
        _loading = false;
      });
    } catch (e) {
      if (!mounted || gen != _loadGen) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
      AppToast.error(e.toString());
    }
  }

  /// 期列表：GET /agent/reports/tickets/issues（订单级聚合，不卡）
  Future<void> _loadTicketIssues({bool fromPull = false}) async {
    final gen = ++_loadGen;
    if (!fromPull && mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    } else if (mounted) {
      setState(() => _error = null);
    }
    try {
      final data = await ref.read(agentRepositoryProvider).getReportTicketIssues(
            startDate: _fmt(_start),
            endDate: _fmt(_end),
            memberAccountId: _ticketMemberId,
            type: _selectedType,
            source: _selectedSource,
            status: 'SETTLED',
            issueNo: _activeIssue,
            pageNum: _page,
            pageSize: _pageSize,
          );
      if (!mounted || gen != _loadGen) return;
      final summary = data['summary'] is Map
          ? Map<String, dynamic>.from(data['summary'] as Map)
          : <String, dynamic>{};
      final raw = data['rows'];
      final rows = raw is List
          ? raw.whereType<Map>().map((e) {
              final m = Map<String, dynamic>.from(e);
              final issue = '${m['issueNo'] ?? ''}'.trim();
              final gt = '${m['gameType'] ?? ''}'.trim();
              m['key'] = '$issue|$gt';
              return m;
            }).toList()
          : <Map<String, dynamic>>[];
      setState(() {
        _ticketIssueSummary = summary;
        _summary = {};
        _rows = rows;
        _applyPage(data, rows.length);
        _loading = false;
      });
    } catch (e) {
      if (!mounted || gen != _loadGen) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
      AppToast.error(e.toString());
    }
  }

  /// 单期明细：一页一请求，不把后面的页拼上来。
  Future<void> _loadTicketDetails({bool fromPull = false}) async {
    if (_ticketIssueNo.isEmpty) return;
    final gen = ++_loadGen;
    if (!fromPull && mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    } else if (mounted) {
      setState(() => _error = null);
    }
    try {
      final data = await ref.read(agentRepositoryProvider).getReportTickets(
            startDate: _fmt(_start),
            endDate: _fmt(_end),
            memberAccountId: _ticketMemberId,
            issueNo: _ticketIssueNo,
            gameType: _ticketGameType.isEmpty ? null : _ticketGameType,
            source: _selectedSource,
            status: 'SETTLED',
            pageNum: _page,
            pageSize: _pageSize,
          );
      if (!mounted || gen != _loadGen) return;
      final raw = data['rows'];
      final list = raw is List
          ? raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
          : <Map<String, dynamic>>[];
      final total = data['total'] is num
          ? (data['total'] as num).toInt()
          : (data['itemCount'] is num ? (data['itemCount'] as num).toInt() : list.length);
      setState(() {
        _ticketIssueSummary = {
          'orderCount': data['itemCount'] ?? total,
          'betAmount': data['betAmount'] ?? 0,
          'result': data['playerResult'] ?? 0,
        };
        _rows = list;
        _applyPage(data, list.length);
        _loading = false;
      });
    } catch (e) {
      if (!mounted || gen != _loadGen) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
      AppToast.error(e.toString());
    }
  }

  void _openTickets(Map<String, dynamic> row) {
    final id = row['accountId'] is int
        ? row['accountId'] as int
        : int.tryParse('${row['accountId'] ?? ''}');
    if (id == null) return;
    final name = '${row['displayName'] ?? row['username'] ?? id}'.trim();
    setState(() {
      _ticketMemberId = id;
      _ticketMemberName = name;
      _ticketIssueKey = null;
      _ticketIssueNo = '';
      _ticketGameType = '';
      _ticketIssueSummary = {};
      _rows = [];
      _page = 1;
    });
    _load();
  }

  void _openTicketIssue(Map<String, dynamic> g) {
    final issue = '${g['issueNo'] ?? ''}'.trim();
    final gt = '${g['gameType'] ?? ''}'.trim();
    if (issue.isEmpty) return;
    setState(() {
      _ticketIssueKey = '${g['key'] ?? '$issue|$gt'}';
      _ticketIssueNo = issue;
      _ticketGameType = gt;
      _rows = [];
      _ticketIssueSummary = {
        'orderCount': g['orderCount'],
        'betAmount': g['betAmount'],
        'result': g['result'],
      };
      _page = 1;
    });
    _loadTicketDetails();
  }

  void _openChildren(Map<String, dynamic> row) {
    final id = row['accountId'] is int
        ? row['accountId'] as int
        : int.tryParse('${row['accountId'] ?? ''}');
    if (id == null) return;
    final name = '${row['displayName'] ?? row['username'] ?? id}'.trim();
    setState(() {
      _drill.add({'accountId': id, 'username': name});
      _ticketMemberId = null;
      _ticketIssueKey = null;
      _ticketIssueNo = '';
      _ticketGameType = '';
      _ticketIssueSummary = {};
      _page = 1;
    });
    _load();
  }

  /// 下级盈亏用接口给出的整棵下级树盈亏结果合计。旧接口没有这个字段时，仍用盈亏、盈亏结果、上级交收相减。
  num? _subordinatePnl(dynamic given, dynamic profit, dynamic result, dynamic uplink) {
    final ready = given is num ? given.toDouble() : double.tryParse('${given ?? ''}'.trim());
    if (ready != null) return ready;
    final a = profit is num ? profit.toDouble() : double.tryParse('$profit'.trim());
    final b = result is num ? result.toDouble() : double.tryParse('$result'.trim());
    final c = uplink is num ? uplink.toDouble() : double.tryParse('$uplink'.trim());
    if (a == null || b == null || c == null) return null;
    return a - b - c;
  }

  void _popDrill() {
    if (_ticketMemberId != null && _ticketIssueKey != null) {
      setState(() {
        _ticketIssueKey = null;
        _ticketIssueNo = '';
        _ticketGameType = '';
        _rows = [];
        _ticketIssueSummary = {};
        _page = 1;
      });
      _loadTicketIssues();
      return;
    }
    if (_ticketMemberId != null) {
      setState(() {
        _ticketMemberId = null;
        _ticketMemberName = '';
        _ticketIssueKey = null;
        _ticketIssueNo = '';
        _ticketGameType = '';
        _ticketIssueSummary = {};
        _page = 1;
      });
      _load();
      return;
    }
    if (_drill.isEmpty) return;
    setState(() {
      _drill.removeLast();
      _page = 1;
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    _syncDrillBack();
    final inTickets = _ticketMemberId != null;
    return AgentPageFrame(
      // 去掉「报表查询」「注单明细」标题条
      title: '',
      onRefresh: () => _load(fromPull: true),
      child: ColoredBox(
        color: const Color(0xFFF2F2F2),
        child: Column(
          children: [
            if (_drill.isNotEmpty || inTickets)
              Padding(
                padding: EdgeInsets.fromLTRB(12.w, 8.h, 12.w, 0),
                child: _crumbBar(),
              ),
            Padding(
              padding: EdgeInsets.fromLTRB(12.w, 8.h, 12.w, 0),
              child: _queryPanel(),
            ),
            Expanded(child: _scrollBody(inTickets)),
            AgentPaginationBar(
              page: _totalPages == 0 ? 0 : _page,
              totalPages: _totalPages,
              total: _total,
              onPrev: () {
                if (_page <= 1) return;
                setState(() => _page--);
                _load();
              },
              onNext: () {
                if (_page >= _totalPages) return;
                setState(() => _page++);
                _load();
              },
            ),
          ],
        ),
      ),
    );
  }

  /// 仅查询条件可展开/收起；总览与明细不在此面板内
  Widget _queryPanel() {
    final quickLabel = (_quick >= 0 && _quick < _quickItems.length) ? _quickItems[_quick].label : '';
    return _surface(
      child: Column(
        children: [
          GestureDetector(
            onTap: () => setState(() => _panelOpen = !_panelOpen),
            behavior: HitTestBehavior.opaque,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _panelOpen
                        ? '查询条件'
                        : [
                            if (quickLabel.isNotEmpty) quickLabel,
                            '${_fmt(_start)} ~ ${_fmt(_end)}',
                          ].join('  '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14.sp,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF222222),
                    ),
                  ),
                ),
                Text(
                  _panelOpen ? '收起' : '展开',
                  style: TextStyle(fontSize: 13.sp, color: const Color(0xFF4A90D9), fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          if (_panelOpen) ...[
            SizedBox(height: 10.h),
            _filterFields(),
          ],
        ],
      ),
    );
  }

  /// 总览 + 明细同一滚动区域
  Widget _scrollBody(bool inTickets) {
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
              : ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.fromLTRB(8.w, 6.h, 8.w, 16.h),
                  children: [
                    if (inTickets) ...[
                      _ticketSummaryBar(),
                      if (_rows.isEmpty)
                        Padding(
                          padding: EdgeInsets.only(top: 48.h),
                          child: Center(
                            child: Text(
                              '暂无数据',
                              style: TextStyle(fontSize: 14.sp, color: AppColors.textHint),
                            ),
                          ),
                        )
                      else if (_ticketIssueKey != null)
                        for (final row in _rows) ...[
                          SizedBox(height: 6.h),
                          _ticketCard(row),
                        ]
                      else ...[
                        for (final g in _rows) ...[
                          SizedBox(height: 6.h),
                          _ticketIssueRow(g),
                        ],
                      ],
                    ] else ...[
                      // 总览 + 明细上下连成一体，同一 ListView 滑动
                      if (_summary.isNotEmpty) _summaryBlock(),
                      if (_rows.isEmpty)
                        Padding(
                          padding: EdgeInsets.only(top: 48.h),
                          child: Center(
                            child: Text(
                              '暂无数据',
                              style: TextStyle(fontSize: 14.sp, color: AppColors.textHint),
                            ),
                          ),
                        )
                      else
                        for (var i = 0; i < _rows.length; i++)
                          _memberBlock(_rows[i], showTopBorder: _summary.isEmpty && i == 0),
                    ],
                  ],
                ),
    );
  }

  Widget _filterFields() {
    return Column(
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
        _issueField(),
        SizedBox(height: 12.h),
        Row(children: [
          Expanded(child: _dropField(_gameLabel, _pickGame)),
          SizedBox(width: 8.w),
          Expanded(child: _dropField(_sourceLabels[_sourceIndex], _pickSource)),
          SizedBox(width: 8.w),
          GestureDetector(
            onTap: _search,
            child: Container(
              height: 40.h,
              width: 56.w,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0xFF4A90D9),
                borderRadius: BorderRadius.circular(4.r),
              ),
              child: Text(
                '查询',
                style: TextStyle(fontSize: 14.sp, color: Colors.white, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ]),
      ],
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
    if (_ticketIssueKey != null) {
      final issue = _ticketIssueKey!.split('|').first;
      parts.add(issue.isEmpty ? '明细' : '期$issue');
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
        SizedBox(width: 8.w),
        TextButton(
          onPressed: _popDrill,
          style: TextButton.styleFrom(
            padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            foregroundColor: AppColors.navBlue,
            side: BorderSide(color: AgentChrome.cardBorder),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.r)),
          ),
          child: Text('返回上级', style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }

  static const _cRed = Color(0xFFE53935);
  static const _cGreen = Color(0xFF2E7D32);
  static const _cOrange = Color(0xFFE65100);
  static const _cBlack = Color(0xFF222222);
  static const _summaryBg = Color(0xFFD4E8F8);

  Widget _summaryBlock() {
    if (_summary.isEmpty) return const SizedBox.shrink();
    final pnl = _summary['pnl'] ??
        ((num.tryParse('${_summary['winLoss'] ?? 0}') ?? 0) +
            (num.tryParse('${_summary['rebate'] ?? 0}') ?? 0));
    final resultPnl = _summary['resultPnl'] ?? _summary['combinedPnl'];
    final count = _summary['orderCount'] ?? _summary['betCount'] ?? _rows.length;
    return _reportBlock(
      bg: _summaryBg,
      cells: [
        _cell('总计', null, _cRed, raw: '($count)'),
        _cell('下注金额', _summary['betAmount'], _cRed),
        _cell('输赢', _summary['winLoss'], _cRed),
        _cell('退水', _summary['rebate'], _cRed),
        _cell('盈亏', pnl, _cRed),
        _cell(
          '下级盈亏',
          _subordinatePnl(_summary['subResultPnl'], pnl, resultPnl, _summary['uplinkSettlement']),
          _cGreen,
        ),
        _cell('下级交货', _summary['downVolume'], _cGreen),
        _cell('应收下线', _summary['receivable'], _cGreen),
        _cell('占成', null, _cOrange, raw: _ratioText(_summary['shareRatio'] ?? 0)),
        _cell('实占金额', _summary['shareAmount'], _cOrange),
        _cell('实占结果', _summary['sharePnl'], _cOrange),
        _cell('实占退水', _summary['rebateNet'], _cOrange),
        _cell('赚水', _summary['earnWater'] ?? _summary['rebateGot'], _cOrange),
        _cell('盈亏结果', resultPnl, _cOrange),
        _cell('上缴货量', _summary['uplinkVolume'], _cBlack),
        _cell('上级交收', _summary['uplinkSettlement'], _cBlack),
      ],
    );
  }

  Widget _memberBlock(Map<String, dynamic> row, {bool showTopBorder = false}) {
    final user = '${row['username'] ?? ''}'.trim();
    final display = '${row['displayName'] ?? ''}'.trim();
    final lv = row['agentLevel'];
    final head = [
      user.isNotEmpty ? user : (display.isNotEmpty ? display : '${row['accountId'] ?? '—'}'),
      if (display.isNotEmpty && display != user) '($display)',
      if (lv != null) '($lv)',
    ].join(' ');
    final level = '${row['level'] ?? row['accountType'] ?? ''}'.toUpperCase();
    final id = row['accountId'] is int
        ? row['accountId'] as int
        : int.tryParse('${row['accountId'] ?? ''}');
    final isMember = level.contains('MEMBER') || row['drillable'] == false;
    final resultPnl = row['selfPnl'];
    final profit = row['memberResult'];
    // 姓名格下方：代理「查看下级」、会员「查看注单」
    final String? actionLabel = id == null
        ? null
        : (isMember ? '查看注单' : '查看下级');
    final VoidCallback? actionTap = actionLabel == null
        ? null
        : () => isMember ? _openTickets(row) : _openChildren(row);
    return _reportBlock(
      bg: Colors.white,
      showTopBorder: showTopBorder,
      cells: [
        _cell(head, null, _cRed, raw: '', actionLabel: actionLabel, onAction: actionTap),
        _cell('下注金额', row['betAmount'], _cRed),
        _cell('输赢', row['memberWin'] ?? row['memberWinLoss'], _cRed),
        _cell('退水', row['memberRebate'], _cRed),
        _cell('盈亏', profit, _cRed),
        _cell(
          '下级盈亏',
          _subordinatePnl(row['subResultPnl'], profit, resultPnl, row['uplinkSettlement']),
          _cGreen,
        ),
        _cell('下级交货', row['downVolume'], _cGreen),
        _cell('应收下线', row['receivable'], _cGreen),
        _cell('占成', null, _cOrange, raw: _ratioText(row['shareRatio'])),
        _cell('实占金额', row['shareAmount'], _cOrange),
        _cell('实占结果', row['shareResult'] ?? row['sharePnl'], _cOrange),
        _cell('实占退水', row['shareRebate'], _cOrange),
        _cell('赚水', row['earnWater'] ?? row['rebateIncome'], _cOrange),
        _cell('盈亏结果', resultPnl, _cOrange),
        _cell('上缴货量', row['uplinkVolume'], _cBlack),
        _cell('上级交收', row['uplinkSettlement'], _cBlack),
      ],
    );
  }

  ({String label, dynamic value, Color labelColor, String? raw, VoidCallback? onAction, String? actionLabel}) _cell(
    String label,
    dynamic value,
    Color labelColor, {
    String? raw,
    VoidCallback? onAction,
    String? actionLabel,
  }) =>
      (
        label: label,
        value: value,
        labelColor: labelColor,
        raw: raw,
        onAction: onAction,
        actionLabel: actionLabel,
      );

  Widget _reportBlock({
    required Color bg,
    required List<({String label, dynamic value, Color labelColor, String? raw, VoidCallback? onAction, String? actionLabel})> cells,
    bool showTopBorder = true,
  }) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(6.w, 10.h, 6.w, 10.h),
      decoration: BoxDecoration(
        color: bg,
        border: Border(
          top: showTopBorder ? const BorderSide(color: Color(0xFFB0BEC5), width: 0.5) : BorderSide.none,
          left: const BorderSide(color: Color(0xFFB0BEC5), width: 0.5),
          right: const BorderSide(color: Color(0xFFB0BEC5), width: 0.5),
          bottom: const BorderSide(color: Color(0xFFB0BEC5), width: 0.5),
        ),
      ),
      child: Column(
        children: [
          for (var i = 0; i < cells.length; i += 4) ...[
            if (i > 0) SizedBox(height: 10.h),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var j = 0; j < 4; j++) ...[
                  if (j > 0) SizedBox(width: 2.w),
                  Expanded(
                    child: i + j < cells.length
                        ? _metric(cells[i + j])
                        : const SizedBox.shrink(),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// 对齐参考图：标签/数字都是 Regular（不加粗），列内居中，上下留空
  Widget _metric(({String label, dynamic value, Color labelColor, String? raw, VoidCallback? onAction, String? actionLabel}) c) {
    // 姓名格：上方名称，下方「查看下级」或「查看注单」
    if (c.actionLabel != null && c.onAction != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            c.label,
            maxLines: 2,
            softWrap: true,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12.sp,
              height: 1.25,
              color: c.labelColor,
              fontWeight: FontWeight.w400,
            ),
          ),
          SizedBox(height: 4.h),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: c.onAction,
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 2.h, horizontal: 2.w),
              child: Text(
                c.actionLabel!,
                maxLines: 1,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13.sp,
                  height: 1.25,
                  color: const Color(0xFF1565C0),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ],
      );
    }
    if (c.onAction != null) {
      return Center(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: c.onAction,
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 6.h, horizontal: 2.w),
            child: Text(
              c.label,
              maxLines: 2,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13.sp,
                height: 1.25,
                color: c.labelColor,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      );
    }
    final text = c.raw ?? (c.value == null ? '—' : displayNumber(c.value));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          c.label,
          maxLines: 2,
          softWrap: true,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12.sp,
            height: 1.25,
            color: c.labelColor,
            fontWeight: FontWeight.w400,
          ),
        ),
        SizedBox(height: 4.h),
        // raw == '' 时占位，保证与同行数字基线对齐
        text.isEmpty
            ? SizedBox(height: 14.sp * 1.2)
            : FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.center,
                child: Text(
                  text,
                  maxLines: 1,
                  softWrap: false,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14.sp,
                    height: 1.2,
                    fontWeight: FontWeight.w400,
                    color: _cBlack,
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
    final rounded = (pct * 100).roundToDouble() / 100;
    return '${displayNumber(rounded)}%';
  }

  num _ticketSumNum(String key) {
    final v = _ticketIssueSummary[key];
    if (v is num) return v;
    return num.tryParse('$v'.trim()) ?? 0;
  }

  Widget _ticketSummaryBar() {
    if (_ticketIssueKey != null) {
      final issue = _ticketIssueNo.isNotEmpty
          ? _ticketIssueNo
          : _ticketIssueKey!.split('|').first;
      return _surface(
        padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 12.h),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$_ticketMemberName · 期$issue',
              style: TextStyle(
                fontSize: 13.sp,
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: 8.h),
            Row(
              children: [
                Text('注单 ${displayNumber(_ticketSumNum('orderCount'))}', style: _ticketLineStyle()),
                SizedBox(width: 16.w),
                Text('流水 ${displayNumber(_ticketSumNum('betAmount'))}', style: _ticketLineStyle()),
                SizedBox(width: 16.w),
                Text(
                  '结果 ${displayNumber(_ticketSumNum('result'))}',
                  style: _ticketLineStyle(color: _ticketMoneyColor(_ticketSumNum('result'), signed: true)),
                ),
              ],
            ),
          ],
        ),
      );
    }
    final issueCount = _ticketIssueSummary['issueCount'] is num
        ? (_ticketIssueSummary['issueCount'] as num).toInt()
        : _rows.length;
    final count = _ticketSumNum('orderCount');
    return _surface(
      padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 12.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$_ticketMemberName · $issueCount 期 · $count 条',
            style: TextStyle(
              fontSize: 13.sp,
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: 8.h),
          _ticketMetricGrid(
            lead: Text('合计', style: TextStyle(fontSize: 12.sp, color: AppColors.textSecondary)),
            count: count,
            turnover: _ticketSumNum('betAmount'),
            result: _ticketSumNum('result'),
          ),
        ],
      ),
    );
  }

  Widget _ticketIssueRow(Map<String, dynamic> g) {
    return GestureDetector(
      onTap: () => _openTicketIssue(g),
      child: _surface(
        child: _ticketMetricGrid(
          lead: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${g['issueNo'] ?? '—'}',
                style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600),
              ),
              SizedBox(height: 2.h),
              Text(
                '${g['gameName'] ?? g['gameType'] ?? '—'}',
                style: TextStyle(fontSize: 12.sp, color: AppColors.textSecondary),
              ),
            ],
          ),
          count: g['orderCount'],
          turnover: g['betAmount'],
          result: g['result'],
          chevron: true,
        ),
      ),
    );
  }

  /// 期列表：左列收窄，注单 / 流水 / 结果加宽并右对齐，数字与文字同字号。
  Widget _ticketMetricGrid({
    required Widget lead,
    required dynamic count,
    required dynamic turnover,
    required dynamic result,
    bool chevron = false,
  }) {
    return Row(
      children: [
        Expanded(flex: 5, child: lead),
        Expanded(flex: 3, child: _ticketCol('注单', count)),
        Expanded(
          flex: 4,
          child: Padding(
            padding: EdgeInsets.only(left: 8.w),
            child: _ticketCol('流水', turnover),
          ),
        ),
        Expanded(
          flex: 4,
          child: Padding(
            padding: EdgeInsets.only(left: 8.w),
            child: _ticketCol('结果', result, signed: true),
          ),
        ),
        if (chevron)
          Icon(Icons.chevron_right, size: 18.sp, color: AppColors.textHint)
        else
          SizedBox(width: 18.sp),
      ],
    );
  }

  Widget _ticketCol(String label, dynamic value, {bool signed = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(label, style: TextStyle(fontSize: 12.sp, color: AppColors.textSecondary)),
        SizedBox(height: 2.h),
        Text(
          displayNumber(value),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 12.sp,
            fontWeight: FontWeight.w600,
            color: _ticketMoneyColor(value, signed: signed),
          ),
        ),
      ],
    );
  }

  Widget _ticketCard(Map<String, dynamic> row) {
    final play = slipBetTitle({
      ...row,
      'title': row['title'] ?? row['contentOdds'],
    });
    final result = row['itemResult'] ?? row['selfResult'];
    final source = _ticketSourceLabel(row['source']?.toString());
    final time = _fmtTicketTime(row['betAt'] ?? row['createdAt']);
    final meta = [
      if (source.isNotEmpty) source,
      if (time.isNotEmpty) time,
    ].join(' / ');
    final fly = row['source']?.toString() == 'OWNER_FLIGHT';
    final player = _ticketPlayerLine(row, play);
    return _surface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                row['issueNo']?.toString() ?? '—',
                style: _ticketLineStyle(),
              ),
              SizedBox(width: 8.w),
              Expanded(
                child: Text(
                  play,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _ticketLineStyle(),
                ),
              ),
              SizedBox(width: 8.w),
              Text(
                _bizStatusLabel(row['status']?.toString()),
                style: TextStyle(fontSize: 13.sp, color: AppColors.textSecondary),
              ),
            ],
          ),
          SizedBox(height: 6.h),
          Row(
            children: [
              Text('金额 ${displayNumber(row['amount'])}', style: _ticketLineStyle()),
              SizedBox(width: 16.w),
              Text(
                '结果 ${displayNumber(result)}',
                style: _ticketLineStyle(color: _ticketMoneyColor(result, signed: true)),
              ),
            ],
          ),
          if (meta.isNotEmpty) ...[
            SizedBox(height: 4.h),
            Text(meta, style: TextStyle(fontSize: 12.sp, color: AppColors.textSecondary)),
          ],
          if (fly && player.isNotEmpty) ...[
            SizedBox(height: 2.h),
            Text(player, style: TextStyle(fontSize: 12.sp, color: AppColors.textSecondary)),
          ],
          if (!fly && source == 'Web直属') ...[
            SizedBox(height: 2.h),
            Text('本会员自己下的注', style: TextStyle(fontSize: 12.sp, color: AppColors.textHint)),
          ],
        ],
      ),
    );
  }

  String _ticketPlayerLine(Map<String, dynamic> row, String play) {
    final name = '${row['playerName'] ?? ''}'.trim();
    final roomOrder = row['roomOrderId'];
    final roomText = roomOrder == null ? '' : '$roomOrder'.trim();
    final playName = play.split(' @ ').first.trim();
    final parts = <String>[
      if (name.isNotEmpty) '玩家 $name',
      if (roomText.isNotEmpty && roomText != 'null') '注单 $roomText',
      if (playName.isNotEmpty && playName != '—') playName,
    ];
    if (_moneyDiffers(row['playerAmount'], row['amount'])) {
      parts.add('原注额 ${displayNumber(row['playerAmount'])}');
    }
    return parts.join(' / ');
  }

  bool _moneyDiffers(dynamic playerAmount, dynamic flyAmount) {
    if (playerAmount == null) return false;
    final a = playerAmount is num ? playerAmount.toDouble() : double.tryParse('$playerAmount');
    final b = flyAmount is num ? flyAmount.toDouble() : double.tryParse('$flyAmount');
    if (a == null || b == null) return false;
    return (a - b).abs() >= 0.0001;
  }

  String _ticketSourceLabel(String? source) {
    switch (source) {
      case 'OWNER_FLIGHT':
        return '房主飞单';
      case 'WEB_DIRECT':
        return 'Web直属';
      default:
        return '';
    }
  }

  String _fmtTicketTime(dynamic raw) {
    var s = '${raw ?? ''}'.trim();
    if (s.isEmpty || s == 'null') return '';
    s = s.replaceFirst('T', ' ');
    final dot = s.indexOf('.');
    if (dot > 0) s = s.substring(0, dot);
    if (s.length >= 19 && s[4] == '-') return s.substring(5, 19);
    return s;
  }

  TextStyle _ticketLineStyle({Color? color}) {
    return TextStyle(fontSize: 13.sp, color: color ?? const Color(0xFF333333));
  }

  Color _ticketMoneyColor(dynamic value, {bool signed = false}) {
    if (!signed) return const Color(0xFF333333);
    final text = displayNumber(value);
    final n = num.tryParse(text) ?? 0;
    if (n > 0) return AgentChrome.pnlUp;
    if (n < 0) return AppColors.danger;
    return const Color(0xFF333333);
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

  Widget _surface({required Widget child, EdgeInsetsGeometry? padding, Color? color}) {
    return Container(
      width: double.infinity,
      padding: padding ?? EdgeInsets.fromLTRB(12.w, 12.h, 12.w, 12.h),
      decoration: BoxDecoration(
        color: color ?? Colors.white,
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

  Widget _issueField() {
    return Container(
      height: 40.h,
      padding: EdgeInsets.symmetric(horizontal: 10.w),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F9FC),
        borderRadius: BorderRadius.circular(10.r),
        border: Border.all(color: const Color(0xFFE3E8EF)),
      ),
      alignment: Alignment.center,
      child: EmulatorSafeTextField(
        controller: _issueCtrl,
        style: TextStyle(fontSize: 13.sp, color: AppColors.textPrimary),
        decoration: InputDecoration(
          hintText: '期号',
          hintStyle: TextStyle(fontSize: 13.sp, color: AppColors.textHint),
          border: InputBorder.none,
          isDense: true,
          contentPadding: EdgeInsets.zero,
        ),
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

