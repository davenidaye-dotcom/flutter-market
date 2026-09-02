import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../config/theme/app_colors.dart';
import '../../../data/repositories/providers.dart';
import '../../../shared/widgets/page_app_bar.dart';
import '../../lottery/utils/lottery_period_ui.dart';
import '../data/agent_mock.dart';
import '../widgets/agent_ui.dart';

/// 收付统计 — 竞品「收付统计页面.png」
class AgentPaymentStatsPage extends ConsumerStatefulWidget {
  const AgentPaymentStatsPage({super.key, required this.roomId});

  final String roomId;

  @override
  ConsumerState<AgentPaymentStatsPage> createState() => _AgentPaymentStatsPageState();
}

class _AgentPaymentStatsPageState extends ConsumerState<AgentPaymentStatsPage> {
  int _gameIndex = 0;
  bool _loading = false;
  List<Map<String, dynamic>> _games = [];
  List<Map<String, dynamic>> _columns = [];
  String _issueNo = '';
  String _statusText = '';
  int _countdownSeconds = 0;
  Timer? _tickTimer;
  int _pollSeconds = 0;

  @override
  void initState() {
    super.initState();
    _load();
    _startTickTimer();
  }

  @override
  void dispose() {
    _tickTimer?.cancel();
    super.dispose();
  }

  String? get _currentType {
    if (_games.isEmpty || _gameIndex < 0 || _gameIndex >= _games.length) return null;
    final t = _games[_gameIndex]['type']?.toString();
    return (t == null || t.isEmpty) ? null : t;
  }

  List<String> get _gameNames =>
      _games.map((g) => g['typeName']?.toString() ?? g['type']?.toString() ?? '').toList();

  void _startTickTimer() {
    _tickTimer?.cancel();
    _tickTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        if (_countdownSeconds > 0) {
          _countdownSeconds--;
        }
        _statusText = _localStatusText(_countdownSeconds);
      });
      _pollSeconds++;
      final pollEvery = _countdownSeconds <= LotteryPeriodRules.sealWarnSeconds ? 2 : 5;
      if (_pollSeconds >= pollEvery) {
        _pollSeconds = 0;
        _load(silent: true);
      }
    });
  }

  String _localStatusText(int seconds) {
    if (seconds <= 0) return '开奖中';
    if (seconds <= LotteryPeriodRules.sealWarnSeconds) return '封盘中';
    return '投注中';
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() => _loading = true);
    }
    try {
      final data = await ref.read(agentRepositoryProvider).getLotteryInfo(
            scene: 'STATS',
            type: _currentType,
          );
      if (!mounted) return;
      final games = _asMapList(data['games']);
      final columns = _asMapList(data['columns']);
      final type = data['type']?.toString();
      var idx = _gameIndex;
      if (games.isNotEmpty && type != null && type.isNotEmpty) {
        final found = games.indexWhere((g) => g['type']?.toString() == type);
        if (found >= 0) idx = found;
      }
      setState(() {
        _games = games;
        _columns = columns;
        _issueNo = data['issueNo']?.toString() ?? '';
        _statusText = data['statusText']?.toString() ?? _localStatusText(_countdownSeconds);
        _countdownSeconds = (data['countdownSeconds'] as num?)?.toInt() ?? 0;
        _gameIndex = idx.clamp(0, games.isEmpty ? 0 : games.length - 1);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      if (!silent) AppToast.error(e.toString());
    }
  }

  Future<void> _onGameChanged(int i) async {
    setState(() => _gameIndex = i);
    _pollSeconds = 0;
    await _load();
  }

  (String, String, String, String) get _cdParts {
    final total = _countdownSeconds.clamp(0, 86400 * 7);
    final h = total ~/ 3600;
    final m = (total % 3600) ~/ 60;
    final s = total % 60;
    return (
      '$h',
      '$m',
      '${s ~/ 10}',
      '${s % 10}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final cd = _cdParts;
    return AgentPageFrame(
      title: '收付统计',
      onRefresh: () => _load(),
      child: Column(
        children: [
          if (_gameNames.isNotEmpty)
            AgentGameTabs(
              games: _gameNames,
              current: _gameIndex,
              style: AgentGameTabStyle.payment,
              onChanged: _onGameChanged,
            ),
          SizedBox(height: 8.h),
          AgentBorderBox(
            child: Row(
              children: [
                Text(
                  '期号 ${_issueNo.isEmpty ? '—' : _issueNo}',
                  style: TextStyle(fontSize: 13.sp),
                ),
                SizedBox(width: 16.w),
                Text(
                  _statusText.isEmpty ? '—' : _statusText,
                  style: TextStyle(fontSize: 13.sp, color: Colors.red, fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                _countdownBox(cd.$1),
                Text(' : ', style: TextStyle(fontSize: 13.sp, color: Colors.red)),
                _countdownBox(cd.$2),
                Text(' : ', style: TextStyle(fontSize: 13.sp, color: Colors.red)),
                _countdownBox(cd.$3),
                Text(' - ', style: TextStyle(fontSize: 13.sp, color: Colors.red)),
                _countdownBox(cd.$4),
              ],
            ),
          ),
          SizedBox(height: 8.h),
          Expanded(
            child: AgentBorderBox(
              padding: EdgeInsets.zero,
              child: _loading && _columns.isEmpty
                  ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                  : _columns.isEmpty
                      ? Center(
                          child: Text(
                            '暂无数据',
                            style: TextStyle(fontSize: 14.sp, color: AppColors.textHint),
                          ),
                        )
                      : Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (var i = 0; i < _columns.length; i++) ...[
                              if (i > 0) Container(width: 1, color: const Color(0xFF333333)),
                              Expanded(child: _rankTable(_columns[i])),
                            ],
                          ],
                        ),
            ),
          ),
          SizedBox(height: 8.h),
        ],
      ),
    );
  }

  Widget _countdownBox(String v) {
    return Container(
      width: 18.w,
      height: 22.h,
      alignment: Alignment.center,
      decoration: BoxDecoration(border: Border.all(color: Colors.red)),
      child: Text(v, style: TextStyle(fontSize: 12.sp, color: Colors.red)),
    );
  }

  Widget _rankTable(Map<String, dynamic> column) {
    final title = column['columnName']?.toString() ?? '';
    final cells = _asMapList(column['cells']);
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: EdgeInsets.symmetric(vertical: 6.h),
          color: const Color(0xFFE8E8E8),
          child: Text(title, textAlign: TextAlign.center, style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600)),
        ),
        Row(
          children: [
            _th('玩法', flex: 2),
            _th('占成金额', flex: 2),
            _th('下注金额', flex: 2),
          ],
        ),
        Expanded(
          child: ListView.builder(
            itemCount: cells.length,
            itemBuilder: (_, i) {
              final cell = cells[i];
              final label = cell['playName']?.toString() ?? '';
              final numVal = int.tryParse(label);
              final isNum = numVal != null && numVal >= 1 && numVal <= 10;
              return Container(
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
                  color: i.isOdd ? const Color(0xFFF9F9F9) : Colors.white,
                ),
                child: Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 4.h),
                        child: isNum
                            ? Center(
                                child: Container(
                                  width: 22.w,
                                  height: 22.w,
                                  alignment: Alignment.center,
                                  color: Color(AgentMock.ballColors[numVal - 1]),
                                  child: Text(label, style: TextStyle(fontSize: 11.sp, color: Colors.white)),
                                ),
                              )
                            : Text(label, textAlign: TextAlign.center, style: TextStyle(fontSize: 12.sp)),
                      ),
                    ),
                    Expanded(flex: 2, child: AgentStatCell(value: _amt(cell['shareAmount']))),
                    Expanded(flex: 2, child: AgentStatCell(value: _amt(cell['betAmount']))),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _th(String t, {required int flex}) => Expanded(
        flex: flex,
        child: Container(
          padding: EdgeInsets.symmetric(vertical: 6.h),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.grey.shade400))),
          child: Text(t, textAlign: TextAlign.center, style: TextStyle(fontSize: 11.sp, color: AppColors.textSecondary)),
        ),
      );
}

List<Map<String, dynamic>> _asMapList(dynamic v) {
  if (v is! List) return [];
  return [
    for (final e in v)
      if (e is Map) Map<String, dynamic>.from(e),
  ];
}

String _amt(dynamic v) {
  if (v == null) return '0';
  if (v is num) {
    if (v == v.roundToDouble()) return '${v.toInt()}';
    return v.toString();
  }
  return v.toString();
}
