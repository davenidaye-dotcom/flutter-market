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
  final Map<String, List<String>> _drawIssues = {};
  int _issueCount = 0;
  String _issueNo = '';
  String _statusText = '';
  int _countdownSeconds = 0;
  int _sealSeconds = LotteryPeriodRules.defaultSealSeconds;
  Timer? _tickTimer;
  int _pollSeconds = 0;
  int _loadGen = 0;
  bool _picking = false;
  final _clock = ValueNotifier<(int, String)>((0, ''));

  @override
  void initState() {
    super.initState();
    _load();
    _startTickTimer();
  }

  @override
  void dispose() {
    _tickTimer?.cancel();
    _clock.dispose();
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
      if (_countdownSeconds > 0) {
        _countdownSeconds--;
      }
      _statusText = _localStatusText(_countdownSeconds);
      _clock.value = (_countdownSeconds, _statusText);
      if (_picking) return;
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
    final gen = ++_loadGen;
    final requested = _currentType;
    if (!silent) {
      setState(() => _loading = true);
    }
    try {
      final data = await ref.read(agentRepositoryProvider).getLotteryInfo(
            scene: 'STATS',
            type: requested,
            issueNo: _mode == 1 ? _pickedIssue : null,
            issueFrom: _mode == 2 ? _rangeFrom : null,
            issueTo: _mode == 2 ? _rangeTo : null,
          );
      if (!mounted || gen != _loadGen) return;
      final games = agentLiveGames(_asMapList(data['games']));
      final columns = _asMapList(data['columns']);
      final recent = data['recentIssues'];
      final issues = recent is List
          ? recent.map((e) => '$e'.trim()).where((e) => e.isNotEmpty).toList()
          : <String>[];
      final type = data['type']?.toString();
      var idx = _gameIndex;
      if ((requested == null || requested.isEmpty) &&
          games.isNotEmpty &&
          type != null &&
          type.isNotEmpty) {
        final found = games.indexWhere((g) => g['type']?.toString() == type);
        if (found >= 0) idx = found;
      }
      setState(() {
        _games = games;
        _columns = columns;
        _recentIssues = _mergeIssueNos(
          issues,
          _drawIssues[type ?? ''] ?? const [],
          _plainIssue(data['issueNo']?.toString() ?? ''),
        );
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
      _clock.value = (_countdownSeconds, _statusText);
      final loadedType = _currentType;
      if (loadedType != null) {
        unawaited(_ensureDrawIssues(loadedType));
      }
    } catch (e) {
      if (!mounted || gen != _loadGen) return;
      setState(() => _loading = false);
      if (!silent) AppToast.error(e.toString());
    }
  }

  Future<void> _onGameChanged(int i) async {
    if (i == _gameIndex && _games.isNotEmpty) return;
    setState(() {
      _gameIndex = i;
      _mode = 0;
      _pickedIssue = null;
      _rangeFrom = null;
      _rangeTo = null;
    });
    _pollSeconds = 0;
    await _load();
  }

  (String, String, String, String) _partsOf(int seconds) {
    final total = seconds.clamp(0, 86400 * 7);
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
            child: ValueListenableBuilder<(int, String)>(
              valueListenable: _clock,
              builder: (_, clock, _) {
                final cd = _partsOf(clock.$1);
                final status = _mode == 2
                    ? '共 $_issueCount 期'
                    : (clock.$2.isEmpty ? '—' : clock.$2);
                return Row(
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
                            status,
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
                );
              },
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
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _onMode(i),
                child: Container(
                  alignment: Alignment.center,
                  padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 10.h),
                  decoration: BoxDecoration(
                    color: _mode == i ? AgentChrome.accent : Colors.white,
                    borderRadius: BorderRadius.circular(8.r),
                    border: Border.all(color: _mode == i ? AgentChrome.accent : AgentChrome.cardBorder),
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      labels[i],
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: 13.sp,
                        color: _mode == i ? Colors.white : AppColors.textPrimary,
                        fontWeight: _mode == i ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
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
    if (_picking) return;
    _picking = true;
    try {
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
    } finally {
      _picking = false;
    }
  }

  String _plainIssue(String raw) {
    final s = raw.trim();
    if (int.tryParse(s) == null) return '';
    return s;
  }

  List<String> _mergeIssueNos(List<String> primary, List<String> extra, String current) {
    final seen = <String>{};
    final out = <String>[];
    void add(String raw) {
      final s = raw.trim();
      if (int.tryParse(s) == null || !seen.add(s)) return;
      out.add(s);
    }

    add(current);
    for (final s in primary) {
      add(s);
    }
    for (final s in extra) {
      add(s);
    }
    out.sort((a, b) => (int.tryParse(b) ?? 0).compareTo(int.tryParse(a) ?? 0));
    return out;
  }

  Future<void> _ensureDrawIssues(String type) async {
    if ((_drawIssues[type] ?? const []).isNotEmpty) return;
    try {
      final drawn = await ref.read(agentRepositoryProvider).recentDrawIssues(type);
      if (!mounted || drawn.isEmpty) return;
      _drawIssues[type] = drawn;
      if (_currentType != type) return;
      setState(() {
        _recentIssues = _mergeIssueNos(_recentIssues, drawn, _plainIssue(_issueNo));
      });
    } catch (_) {
      // 开奖历史暂时拉不到时，选择框仍用当前期号。
    }
  }

  Future<String?> _pickIssue(String title) async {
    final type = _currentType;
    if (type != null) {
      await _ensureDrawIssues(type);
    }
    if (!mounted) return null;
    final issues = _mergeIssueNos(
      _recentIssues,
      type == null ? const [] : (_drawIssues[type] ?? const []),
      _plainIssue(_issueNo),
    );
    if (issues.isEmpty) {
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
                    itemCount: issues.length,
                    itemBuilder: (_, i) {
                      final issue = issues[i];
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
