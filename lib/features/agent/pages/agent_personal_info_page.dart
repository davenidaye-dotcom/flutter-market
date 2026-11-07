import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../config/theme/app_colors.dart';
import '../../../data/repositories/providers.dart';
import '../../../shared/format/display_number.dart';
import '../../../shared/format/play_odds_merge.dart';
import '../../../shared/widgets/page_app_bar.dart';
import '../widgets/agent_ui.dart';
import '../../../shared/widgets/app_page_loading.dart';

/// \u4e2a\u4eba\u4fe1\u606f \u2014 \u7ade\u54c1\u300c\u4ee3\u7406\u9996\u9875.jpg\u300d
class AgentPersonalInfoPage extends ConsumerStatefulWidget {
  const AgentPersonalInfoPage({super.key, required this.roomId});

  final String roomId;

  @override
  ConsumerState<AgentPersonalInfoPage> createState() => _AgentPersonalInfoPageState();
}

class _AgentPersonalInfoPageState extends ConsumerState<AgentPersonalInfoPage> {
  int _gameIndex = 0;
  bool _loading = false;
  int _loadGen = 0;
  bool _holdHeader = true;
  bool _releaseHeader = false;
  List<Map<String, dynamic>> _games = [];
  List<Map<String, dynamic>> _items = [];

  @override
  void initState() {
    super.initState();
    _load(releaseHeader: true);
  }

  String? get _currentType {
    if (_games.isEmpty || _gameIndex < 0 || _gameIndex >= _games.length) return null;
    final t = _games[_gameIndex]['type']?.toString();
    return (t == null || t.isEmpty) ? null : t;
  }

  List<String> get _gameNames =>
      _games.map((g) => g['typeName']?.toString() ?? g['type']?.toString() ?? '').toList();

  Future<void> _load({bool showSuccess = false, bool releaseHeader = false}) async {
    if (releaseHeader) _releaseHeader = true;
    final gen = ++_loadGen;
    setState(() => _loading = true);
    try {
      final data = await ref.read(agentRepositoryProvider).getLotteryInfo(
            scene: 'PROFILE',
            type: _currentType,
          );
      if (!mounted || gen != _loadGen) return;
      final games = agentLiveGames(_asMapList(data['games']));
      final items = _asMapList(data['items']);
      final type = data['type']?.toString();
      var idx = _gameIndex;
      if (games.isNotEmpty && type != null && type.isNotEmpty) {
        final found = games.indexWhere((g) => g['type']?.toString() == type);
        if (found >= 0) idx = found;
      }
      setState(() {
        _games = games;
        _items = items;
        _gameIndex = idx.clamp(0, games.isEmpty ? 0 : games.length - 1);
        _loading = false;
      });
      if (showSuccess) AppToast.success('列表已刷新');
    } catch (e) {
      if (!mounted || gen != _loadGen) return;
      setState(() => _loading = false);
      AppToast.error(e.toString());
    } finally {
      if (mounted && gen == _loadGen && _releaseHeader) {
        _releaseHeader = false;
        ref.invalidate(agentHeaderProvider);
        setState(() => _holdHeader = false);
      }
    }
  }

  void _refreshAll() {
    setState(() => _holdHeader = true);
    _load(showSuccess: true, releaseHeader: true);
  }

  Future<void> _onGameChanged(int i) async {
    setState(() => _gameIndex = i);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return AgentPageFrame(
      title: '',
      refreshGameList: false,
      holdHeader: _holdHeader,
      sequenceHeader: true,
      onRefresh: _refreshAll,
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
          Expanded(
            child: AgentSurface(
              padding: EdgeInsets.zero,
              child: _loading && _items.isEmpty
                  ? const AppPageLoading()
                  : _oddsTable(),
            ),
          ),
          SizedBox(height: 8.h),
        ],
      ),
    );
  }

  Widget _oddsTable() {
    final rows = mergePlayOddsRows(_items);
    final plain = <MergedPlayRow>[];
    final gyh = <MergedPlayRow>[];
    for (final row in rows) {
      if (row.name.startsWith('冠亚和')) {
        gyh.add(row);
      } else {
        plain.add(row);
      }
    }
    return ListView(
      children: [
        if (_loading) const LinearProgressIndicator(minHeight: 2),
        for (final row in plain) _oddsRow(row, row.name),
        if (gyh.isNotEmpty) _groupLabel('冠亚和'),
        for (final row in gyh) _oddsRow(row, _gyhName(row.name)),
      ],
    );
  }

  Widget _groupLabel(String text) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(12.w, 10.h, 12.w, 4.h),
      color: AgentChrome.fieldBg,
      child: Text(
        text,
        style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
      ),
    );
  }

  Widget _oddsRow(MergedPlayRow row, String name) {
    final shown = row.shown;
    final showOnly = name == '特码包三' || row.codes.any((c) => c.toUpperCase() == 'P28-BAO3');
    final maxBet = _capStr(shown['maxBet']);
    final period = _capStr(shown['userPeriodLimit'] ?? shown['periodLimit']);
    final limitLine = '${showOnly ? '只展示 · ' : ''}单注 $maxBet · 单期 $period';
    return Container(
      padding: EdgeInsets.symmetric(vertical: 10.h, horizontal: 12.w),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AgentChrome.cardBorder)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  name,
                  maxLines: 2,
                  style: TextStyle(fontSize: 13.sp, height: 1.3, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                ),
              ),
              SizedBox(width: 8.w),
              Text(
                _numStr(shown['odds']),
                style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600, color: AgentChrome.ink),
              ),
            ],
          ),
          SizedBox(height: 2.h),
          Text(
            limitLine,
            style: TextStyle(fontSize: 11.sp, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

String _gyhName(String name) {
  const prefix = '冠亚和';
  if (!name.startsWith(prefix)) return name;
  var rest = name.substring(prefix.length);
  if (rest.startsWith('-')) rest = rest.substring(1);
  return rest.isEmpty ? name : rest;
}

List<Map<String, dynamic>> _asMapList(dynamic v) {
  if (v is! List) return [];
  return [
    for (final e in v)
      if (e is Map) Map<String, dynamic>.from(e),
  ];
}

/// 赔率按接口原值展示，只去掉末尾 0，不截成两位。
String _numStr(dynamic v) {
  if (v == null) return '';
  return displayNumber(v, maxDecimals: -1);
}

/// 平台限额：0 为不封顶。
String _capStr(dynamic v) {
  if (v == null) return '';
  final n = v is num ? v : num.tryParse('$v');
  if (n != null && n <= 0) return '不封顶';
  return displayNumber(v);
}
