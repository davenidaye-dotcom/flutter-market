import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../config/theme/app_colors.dart';
import '../../../data/repositories/providers.dart';
import '../../../shared/widgets/page_app_bar.dart';
import '../widgets/agent_ui.dart';

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
      final games = _asMapList(data['games']);
      final items = _asMapList(data['items']);
      final header = data['header'] is Map
          ? Map<String, dynamic>.from(data['header'] as Map)
          : <String, dynamic>{};
      final type = data['type']?.toString();
      var idx = _gameIndex;
      if (games.isNotEmpty && type != null && type.isNotEmpty) {
        final found = games.indexWhere((g) => g['type']?.toString() == type);
        if (found >= 0) idx = found;
      }
      setState(() {
        _games = games;
        _items = items;
        _displayId = header['displayId']?.toString() ?? _displayId;
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
                    side: const BorderSide(color: Color(0xFF333333)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(0)),
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
            child: AgentBorderBox(
              padding: EdgeInsets.zero,
              child: _loading && _items.isEmpty
                  ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                  : SingleChildScrollView(
                      child: Table(
                        border: TableBorder.all(color: const Color(0xFF333333), width: 0.8),
                        columnWidths: const {
                          0: FlexColumnWidth(2.2),
                          1: FlexColumnWidth(1.2),
                          2: FlexColumnWidth(1.4),
                          3: FlexColumnWidth(1.2),
                        },
                        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                        children: [
                          TableRow(
                            decoration: const BoxDecoration(color: Color(0xFFF0F0F0)),
                            children: [
                              _h('\u73a9\u6cd5'),
                              _h('\u8d54\u7387'),
                              _h('\u5355\u671f\u9650\u989d'),
                              _h('\u5355\u6ce8\u6700\u4f4e'),
                            ],
                          ),
                          for (final row in _items)
                            TableRow(
                              children: [
                                _c(row['playName']?.toString() ?? ''),
                                _c(_numStr(row['odds'])),
                                _c(_numStr(row['periodLimit'])),
                                _c(_numStr(row['minBet'])),
                              ],
                            ),
                        ],
                      ),
                    ),
            ),
          ),
          SizedBox(height: 8.h),
        ],
      ),
    );
  }

  Widget _h(String t) => Padding(
        padding: EdgeInsets.symmetric(vertical: 8.h, horizontal: 4.w),
        child: Text(t, textAlign: TextAlign.center, style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w600)),
      );

  Widget _c(String t) => Padding(
        padding: EdgeInsets.symmetric(vertical: 8.h, horizontal: 4.w),
        child: Text(t, textAlign: TextAlign.center, style: TextStyle(fontSize: 12.sp)),
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
  if (v is num) {
    if (v == v.roundToDouble()) return '${v.toInt()}';
    return v.toString();
  }
  return v.toString();
}
