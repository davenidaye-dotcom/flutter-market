import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../config/theme/app_colors.dart';
import '../../../data/repositories/providers.dart';
import '../../../shared/format/display_number.dart';
import '../../../shared/widgets/page_app_bar.dart';
import '../../lottery/utils/lottery_period_ui.dart';
import '../data/agent_mock.dart';
import '../widgets/agent_ui.dart';
import '../../../shared/widgets/app_page_loading.dart';

/// 收付统计 — 竞品「收付统计页面.png」
class AgentPaymentStatsPage extends ConsumerStatefulWidget {
  const AgentPaymentStatsPage({super.key, required this.roomId});

  final String roomId;

  @override
  ConsumerState<AgentPaymentStatsPage> createState() => _AgentPaymentStatsPageState();
}

class _AgentPaymentStatsPageState extends ConsumerState<AgentPaymentStatsPage> {
  int _gameIndex = 0;
  /// 0 当期，1 指定一期，2 多期汇总
  int _mode = 0;
  String? _pickedIssue;
  String? _rangeFrom;
  String? _rangeTo;
  bool _loading = false;
  List<Map<String, dynamic>> _games = [];
  List<Map<String, dynamic>> _columns = [];
  List<String> _recentIssues = [];
  int _issueCount = 0;
  String _issueNo = '';
  String _statusText = '';
  int _countdownSeconds = 0;
  int _sealSeconds = LotteryPeriodRules.defaultSealSeconds;
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
      if (!mounted || _mode != 0) return;
      setState(() {
        if (_countdownSeconds > 0) {
          _countdownSeconds--;
        }
        _statusText = _localStatusText(_countdownSeconds);
      });
      _pollSeconds++;
      final pollEvery = _countdownSeconds <= _sealSeconds ? 2 : 5;
      if (_pollSeconds >= pollEvery) {
        _pollSeconds = 0;
        _load(silent: true);
      }
    });
  }

  String _localStatusText(int seconds) {
    if (seconds <= 0) return '开奖中';
    final seal = (_sealSeconds > 0)
        ? _sealSeconds
        : LotteryPeriodRules.defaultSealSeconds;
    if (seconds <= seal) return '封盘中';
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
            issueNo: _mode == 1 ? _pickedIssue : null,
            issueFrom: _mode == 2 ? _rangeFrom : null,
            issueTo: _mode == 2 ? _rangeTo : null,
          );
      if (!mounted) return;
      final games = agentLiveGames(_asMapList(data['games']));
      final columns = _asMapList(data['columns']);
      final recent = data['recentIssues'];
      final issues = recent is List
          ? recent.map((e) => '$e'.trim()).where((e) => e.isNotEmpty).toList()
          : <String>[];
      final type = data['type']?.toString();
      var idx = _gameIndex;
      if (games.isNotEmpty && type != null && type.isNotEmpty) {
        final found = games.indexWhere((g) => g['type']?.toString() == type);
        if (found >= 0) idx = found;
      }
      setState(() {
        _games = games;
        _columns = columns;
        _recentIssues = issues;
        _issueCount = (data['issueCount'] as num?)?.toInt() ?? 0;
        _issueNo = data['issueNo']?.toString() ?? '';
        _countdownSeconds = (data['countdownSeconds'] as num?)?.toInt() ?? 0;
        final sealRaw = data['sealSeconds'];
        final openAt = (data['openAtEpochMs'] as num?)?.toInt() ?? 0;
        final sealAt = (data['sealAtEpochMs'] as num?)?.toInt() ?? 0;
        if (openAt > sealAt && sealAt > 0) {
          _sealSeconds = ((openAt - sealAt) / 1000).round().clamp(
                1,
                LotteryPeriodRules.maxSealSeconds,
              );
        } else if (sealRaw is num && sealRaw.toInt() > 0) {
          _sealSeconds = sealRaw.toInt().clamp(1, LotteryPeriodRules.maxSealSeconds);
        }
        _statusText =
            data['statusText']?.toString() ?? _localStatusText(_countdownSeconds);
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
    setState(() {
      _gameIndex = i;
      _mode = 0;
    });
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
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_gameNames.isNotEmpty)
            AgentGameTabs(
              games: _gameNames,
              current: _gameIndex,
              onChanged: _onGameChanged,
            ),
          SizedBox(height: 8.h),
          _modeBar(),
          SizedBox(height: 8.h),
          AgentSurface(
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '期号 ${_issueNo.isEmpty ? '—' : _issueNo}',
                        style: TextStyle(fontSize: 12.sp, color: AppColors.textSecondary),
                      ),
                      SizedBox(height: 2.h),
                      Text(
                        _mode == 2
                            ? '共 $_issueCount 期'
                            : (_statusText.isEmpty ? '—' : _statusText),
                        style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600, color: AgentChrome.ink),
                      ),
                    ],
                  ),
                ),
                if (_mode == 0) ...[
                  _countdownBox(cd.$1),
                  _cdSep(':'),
                  _countdownBox(cd.$2),
                  _cdSep(':'),
                  _countdownBox(cd.$3),
                  _cdSep('-'),
                  _countdownBox(cd.$4),
                ],
              ],
            ),
          ),
          SizedBox(height: 8.h),
          Expanded(
            child: AgentSurface(
              padding: EdgeInsets.zero,
              child: _loading && _columns.isEmpty
                  ? const AppPageLoading()
                  : _columns.isEmpty
                      ? Center(
                          child: Text(
                            '暂无数据',
                            style: TextStyle(fontSize: 14.sp, color: AppColors.textHint),
                          ),
                        )
                      : LayoutBuilder(
                          builder: (context, constraints) {
                            final width = (constraints.maxWidth - 1) / 2;
                            return ListView.separated(
                              scrollDirection: Axis.horizontal,
                              itemCount: _columns.length,
                              separatorBuilder: (_, _) =>
                                  const VerticalDivider(width: 1, color: AgentChrome.cardBorder),
                              itemBuilder: (_, i) => SizedBox(width: width, child: _rankTable(_columns[i])),
                            );
                          },
                        ),
            ),
          ),
          SizedBox(height: 8.h),
        ],
      ),
    );
  }

  Widget _modeBar() {
    const labels = ['当期', '指定一期', '多期汇总'];
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 12.w),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++) ...[
            if (i > 0) SizedBox(width: 8.w),
            GestureDetector(
              onTap: () => _onMode(i),
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 6.h),
                decoration: BoxDecoration(
                  color: _mode == i ? AgentChrome.accent : Colors.white,
                  borderRadius: BorderRadius.circular(8.r),
                  border: Border.all(color: _mode == i ? AgentChrome.accent : AgentChrome.cardBorder),
                ),
                child: Text(
                  labels[i],
                  style: TextStyle(
                    fontSize: 12.sp,
                    color: _mode == i ? Colors.white : AppColors.textPrimary,
                    fontWeight: _mode == i ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _onMode(int mode) async {
    if (mode == 0) {
      setState(() => _mode = 0);
      _pollSeconds = 0;
      await _load();
      return;
    }
    if (mode == 1) {
      final picked = await _pickIssue('选择期号');
      if (picked == null || !mounted) return;
      setState(() {
        _mode = 1;
        _pickedIssue = picked;
      });
      await _load();
      return;
    }
    final from = await _pickIssue('起始期号');
    if (from == null || !mounted) return;
    final to = await _pickIssue('结束期号');
    if (to == null || !mounted) return;
    setState(() {
      _mode = 2;
      _rangeFrom = from;
      _rangeTo = to;
    });
    await _load();
  }

  Future<String?> _pickIssue(String title) async {
    if (_recentIssues.isEmpty) {
      AppToast.info('暂无可选期号');
      return null;
    }
    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16.r))),
      builder: (ctx) {
        return SafeArea(
          child: SizedBox(
            height: 360.h,
            child: Column(
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 4.h),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(title, style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w600)),
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: _recentIssues.length,
                    itemBuilder: (_, i) {
                      final issue = _recentIssues[i];
                      return ListTile(
                        title: Text(issue),
                        onTap: () => Navigator.pop(ctx, issue),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _cdSep(String mark) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 3.w),
      child: Text(mark, style: TextStyle(fontSize: 13.sp, color: AppColors.textSecondary)),
    );
  }

  Widget _countdownBox(String v) {
    return Container(
      width: 22.w,
      height: 26.h,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        border: Border.all(color: AgentChrome.cardBorder),
        borderRadius: BorderRadius.circular(4.r),
      ),
      child: Text(v, style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600, color: AgentChrome.ink)),
    );
  }

  Widget _rankTable(Map<String, dynamic> column) {
    final title = column['columnName']?.toString() ?? '';
    final cells = _asMapList(column['cells']);
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: EdgeInsets.symmetric(vertical: 8.h),
          decoration: const BoxDecoration(
            color: AgentChrome.fieldBg,
            border: Border(bottom: BorderSide(color: AgentChrome.cardBorder)),
          ),
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
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: AgentChrome.cardBorder)),
                ),
                padding: EdgeInsets.symmetric(vertical: 6.h),
                child: Row(
                  children: [
                    Expanded(
                      flex: 2,
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
                    Expanded(flex: 2, child: _amtText(cell['shareAmount'])),
                    Expanded(flex: 2, child: _amtText(cell['betAmount'])),
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
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AgentChrome.cardBorder))),
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

Widget _amtText(dynamic v) {
  return FittedBox(
    fit: BoxFit.scaleDown,
    child: Text(
      displayNumber(v),
      maxLines: 1,
      softWrap: false,
      textAlign: TextAlign.center,
      style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w600, color: AgentChrome.ink),
    ),
  );
}
