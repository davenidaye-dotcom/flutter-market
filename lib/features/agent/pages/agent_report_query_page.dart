import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../config/theme/app_colors.dart';
import '../../../data/repositories/providers.dart';
import '../../../shared/widgets/page_app_bar.dart';
import '../../wallet/widgets/date_range_filter.dart';
import '../widgets/agent_ui.dart';

class AgentReportQueryPage extends ConsumerStatefulWidget {
  const AgentReportQueryPage({super.key, required this.roomId});
  final String roomId;
  @override
  ConsumerState<AgentReportQueryPage> createState() => _AgentReportQueryPageState();
}

class _AgentReportQueryPageState extends ConsumerState<AgentReportQueryPage> {
  int _quick = 0;
  int _gameIndex = 0;
  bool _showGamePicker = false;
  bool _loading = false;
  String? _error;
  DateTime _start = DateTime.now();
  DateTime _end = DateTime.now();
  Map<String, dynamic> _summary = {};
  List<Map<String, dynamic>> _rows = [];
  List<Map<String, String>> _gameOptions = [];

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

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await ref.read(agentRepositoryProvider).getReports(
            startDate: _fmt(_start),
            endDate: _fmt(_end),
            type: _selectedType,
          );
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

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      AgentPageFrame(
        title: '报表查询',
        titleOnBar: true,
        onRefresh: _load,
        child: Column(children: [
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: AgentBorderBox(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
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
                      AgentTealButton(
                        label: '查询',
                        onTap: () {
                          setState(() => _showGamePicker = false);
                          _load();
                        },
                      ),
                    ]),
                    SizedBox(height: 12.h),
                    _summaryBar(),
                    SizedBox(height: 8.h),
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(border: Border.all(color: const Color(0xFFCCCCCC))),
                        child: _loading
                            ? const Center(child: CircularProgressIndicator())
                            : _error != null
                                ? Center(
                                    child: GestureDetector(
                                      onTap: _load,
                                      child: Text(
                                        '加载失败，点击重试',
                                        style: TextStyle(fontSize: 14.sp, color: AppColors.danger),
                                      ),
                                    ),
                                  )
                                : _rows.isEmpty
                                    ? Center(
                                        child: Text(
                                          '暂无数据',
                                          style: TextStyle(fontSize: 14.sp, color: AppColors.textHint),
                                        ),
                                      )
                                    : Column(
                                        children: [
                                          _tableHeader(),
                                          Expanded(
                                            child: ListView.builder(
                                              itemCount: _rows.length,
                                              itemBuilder: (_, i) => _tableRow(_rows[i], i),
                                            ),
                                          ),
                                        ],
                                      ),
                      ),
                    ),
                  ],
                ),
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
          _summaryItem('盈亏', _summary['winLoss']),
          _summaryItem('返水', _summary['rebate']),
          _summaryItem('占成', _summary['shareAmount']),
        ],
      ),
    );
  }

  Widget _summaryItem(String label, dynamic value) {
    return Text(
      '$label: ${_numStr(value)}',
      style: TextStyle(fontSize: 12.sp, color: AppColors.textSecondary),
    );
  }

  Widget _tableHeader() {
    return Container(
      color: const Color(0xFFE8E8E8),
      padding: EdgeInsets.symmetric(vertical: 8.h),
      child: Row(
        children: [
          _headerCell('日期', flex: 3),
          _headerCell('游戏', flex: 3),
          _headerCell('下注', flex: 2),
          _headerCell('有效', flex: 2),
          _headerCell('盈亏', flex: 2),
        ],
      ),
    );
  }

  Widget _tableRow(Map<String, dynamic> row, int index) {
    final wl = (row['winLoss'] as num?)?.toDouble() ?? 0;
    return Container(
      decoration: BoxDecoration(
        color: index.isOdd ? const Color(0xFFFAFAFA) : Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
      ),
      padding: EdgeInsets.symmetric(vertical: 8.h),
      child: Row(
        children: [
          _bodyCell(row['statDate']?.toString() ?? '—', flex: 3),
          _bodyCell(row['typeName']?.toString() ?? row['type']?.toString() ?? '—', flex: 3),
          _bodyCell(_numStr(row['betAmount']), flex: 2),
          _bodyCell(_numStr(row['validAmount']), flex: 2),
          _bodyCell(
            _numStr(row['winLoss']),
            flex: 2,
            color: wl > 0 ? Colors.green : (wl < 0 ? Colors.red : null),
          ),
        ],
      ),
    );
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
