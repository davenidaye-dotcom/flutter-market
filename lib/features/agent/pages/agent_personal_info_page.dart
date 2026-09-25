import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../config/theme/app_colors.dart';
import '../../../data/repositories/providers.dart';
import '../../../shared/format/display_number.dart';
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
  String _displayId = '';
  List<Map<String, dynamic>> _games = [];
  List<Map<String, dynamic>> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  String? get _currentType {
    if (_games.isEmpty || _gameIndex < 0 || _gameIndex >= _games.length) return null;
    final t = _games[_gameIndex]['type']?.toString();
    return (t == null || t.isEmpty) ? null : t;
  }

  List<String> get _gameNames =>
      _games.map((g) => g['typeName']?.toString() ?? g['type']?.toString() ?? '').toList();

  Future<void> _load({bool showSuccess = false}) async {
    setState(() => _loading = true);
    try {
      final data = await ref.read(agentRepositoryProvider).getLotteryInfo(
            scene: 'PROFILE',
            type: _currentType,
          );
      if (!mounted) return;
      final games = agentLiveGames(_asMapList(data['games']));
      final items = _asMapList(data['items']);
      // PROFILE 响应自带 header.displayId（代理接口文档 §2）
      final lotteryHeader = data['header'] is Map
          ? Map<String, dynamic>.from(data['header'] as Map)
          : <String, dynamic>{};
      String displayId = lotteryHeader['displayId']?.toString() ?? '';
      if (displayId.isEmpty) {
        final credit = await ref.read(agentRepositoryProvider).getCreditAccount();
        final creditHeader = credit['header'] is Map
            ? Map<String, dynamic>.from(credit['header'] as Map)
            : <String, dynamic>{};
        displayId = creditHeader['displayId']?.toString() ?? '';
      }
      final type = data['type']?.toString();
      var idx = _gameIndex;
      if (games.isNotEmpty && type != null && type.isNotEmpty) {
        final found = games.indexWhere((g) => g['type']?.toString() == type);
        if (found >= 0) idx = found;
      }
      setState(() {
        _games = games;
        _items = items;
        _displayId = displayId.isNotEmpty ? displayId : _displayId;
        _gameIndex = idx.clamp(0, games.isEmpty ? 0 : games.length - 1);
        _loading = false;
      });
      if (showSuccess) AppToast.success('\u5217\u8868\u5df2\u5237\u65b0');
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      AppToast.error(e.toString());
    }
  }

  Future<void> _onGameChanged(int i) async {
    setState(() => _gameIndex = i);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final id = _displayId.isNotEmpty ? _displayId : '\u2014';

    return AgentPageFrame(
      title: '\u4e2a\u4eba\u4fe1\u606f',
      onRefresh: () => _load(showSuccess: true),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(12.w, 4.h, 12.w, 8.h),
            child: Row(
              children: [
                OutlinedButton(
                  onPressed: _loading ? null : () => _load(showSuccess: true),
                  style: OutlinedButton.styleFrom(
                    backgroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
                    side: const BorderSide(color: AgentChrome.cardBorder),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.r)),
                  ),
                  child: Text('\u5237\u65b0\u5217\u8868', style: TextStyle(fontSize: 13.sp, color: AppColors.textPrimary)),
                ),
                SizedBox(width: 12.w),
                Text('ID: $id', style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
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
                  : Column(
                      children: [
                        _oddsHeader(),
                        Expanded(
                          child: ListView.builder(
                            itemCount: _items.length,
                            itemBuilder: (_, i) => _oddsRow(_items[i]),
                          ),
                        ),
                      ],
                    ),
            ),
          ),
          SizedBox(height: 8.h),
        ],
      ),
    );
  }

  Widget _oddsHeader() {
    return Container(
      padding: EdgeInsets.symmetric(vertical: 10.h, horizontal: 8.w),
      decoration: BoxDecoration(
        color: AgentChrome.fieldBg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(12.r)),
        border: const Border(bottom: BorderSide(color: AgentChrome.cardBorder)),
      ),
      child: Row(
        children: [
          Expanded(flex: 22, child: _head('\u73a9\u6cd5', align: TextAlign.left)),
          Expanded(flex: 12, child: _head('\u8d54\u7387')),
          Expanded(flex: 14, child: _head('\u5355\u671f\u9650\u989d')),
          Expanded(flex: 12, child: _head('\u5355\u6ce8\u6700\u4f4e')),
        ],
      ),
    );
  }

  Widget _oddsRow(Map<String, dynamic> row) {
    return Container(
      padding: EdgeInsets.symmetric(vertical: 10.h, horizontal: 8.w),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AgentChrome.cardBorder)),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 22,
            child: Text(
              row['playName']?.toString() ?? '',
              maxLines: 2,
              style: TextStyle(fontSize: 12.sp, height: 1.3, color: AppColors.textPrimary),
            ),
          ),
          Expanded(flex: 12, child: _num(_numStr(row['odds']))),
          Expanded(flex: 14, child: _num(_numStr(row['periodLimit']))),
          Expanded(flex: 12, child: _num(_numStr(row['minBet']))),
        ],
      ),
    );
  }

  Widget _head(String t, {TextAlign align = TextAlign.center}) => Text(
        t,
        textAlign: align,
        maxLines: 1,
        softWrap: false,
        style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
      );

  Widget _num(String t) => FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          t,
          maxLines: 1,
          softWrap: false,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w600, color: AgentChrome.ink),
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

String _numStr(dynamic v) {
  if (v == null) return '';
  return displayNumber(v);
}
