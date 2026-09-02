import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../../config/theme/app_colors.dart';
import '../../../../data/repositories/providers.dart';
import '../../../../shared/widgets/emulator_safe_text_field.dart';
import '../../../../shared/widgets/page_app_bar.dart';
import '../../data/host_mock.dart';
import '../../widgets/host_ui.dart';

/// Odds settings — GET/PUT /owner/room/odds
class HostOddsLimitsPage extends ConsumerStatefulWidget {
  const HostOddsLimitsPage({super.key, required this.roomId});
  final String roomId;

  @override
  ConsumerState<HostOddsLimitsPage> createState() => _HostOddsLimitsPageState();
}

class _OddsRow {
  _OddsRow({
    required this.playCode,
    required this.name,
    required this.odds,
    required this.minBet,
    required this.periodLimit,
  });

  final String playCode;
  final String name;
  double odds;
  final num minBet;
  final num periodLimit;
}

class _HostOddsLimitsPageState extends ConsumerState<HostOddsLimitsPage> {
  List<_OddsRow> _rows = [];
  List<Map<String, dynamic>> _games = [];
  int _gameIndex = 0;
  bool _loading = true;
  bool _dirty = false;
  final _unifyCtrl = TextEditingController(text: '0.1');

  String? get _gameType {
    if (_games.isEmpty || _gameIndex >= _games.length) return 'JS_SC';
    return (_games[_gameIndex]['gameType'] ?? _games[_gameIndex]['type'] ?? 'JS_SC')
        .toString();
  }

  @override
  void initState() {
    super.initState();
    Future.microtask(_bootstrap);
  }

  @override
  void dispose() {
    _unifyCtrl.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    try {
      final games = await ref.read(ownerRepositoryProvider).getGames();
      if (!mounted) return;
      setState(() => _games = games);
    } catch (_) {}
    await _loadOdds();
  }

  Future<void> _loadOdds() async {
    setState(() => _loading = true);
    try {
      final data = await ref
          .read(ownerRepositoryProvider)
          .getOdds(gameType: _gameType ?? 'JS_SC');
      final items = hostRowsOf(data.containsKey('items') ? data['items'] : data);
      final rows = items.map((m) {
        return _OddsRow(
          playCode: (m['playCode'] ?? '').toString(),
          name: (m['playName'] ?? m['playCode'] ?? '').toString(),
          odds: (m['odds'] is num)
              ? (m['odds'] as num).toDouble()
              : double.tryParse('${m['odds']}') ?? 0,
          minBet: m['minBet'] is num ? m['minBet'] as num : num.tryParse('${m['minBet']}') ?? 1,
          periodLimit: m['periodLimit'] is num
              ? m['periodLimit'] as num
              : num.tryParse('${m['periodLimit']}') ?? 0,
        );
      }).toList();
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _dirty = false;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      AppToast.error(e.toString());
    }
  }

  double get _step => double.tryParse(_unifyCtrl.text.trim()) ?? 0.1;

  void _adjustAll(double sign) {
    final delta = _step * sign;
    setState(() {
      for (final row in _rows) {
        row.odds = double.parse((row.odds + delta).toStringAsFixed(3));
        if (row.odds < 0) row.odds = 0;
      }
      _dirty = true;
    });
  }

  Future<void> _save({num? uniformDelta}) async {
    final ok = await hostConfirm(
      context,
      title: '\u4fdd\u5b58\u53d8\u66f4',
      message: '\u786e\u8ba4\u4fdd\u5b58\u8d54\u7387\u8bbe\u7f6e\uff1f',
    );
    if (!ok || !mounted) return;
    try {
      await ref.read(ownerRepositoryProvider).updateOdds({
        'gameType': _gameType,
        if (uniformDelta != null) 'uniformDelta': uniformDelta,
        'items': _rows
            .map((r) => {
                  'playCode': r.playCode,
                  'odds': r.odds,
                  'periodLimit': r.periodLimit,
                  'minBet': r.minBet,
                })
            .toList(),
      });
      setState(() => _dirty = false);
      AppToast.success('\u8d54\u7387\u8bbe\u7f6e\u5df2\u4fdd\u5b58');
      await _loadOdds();
    } catch (e) {
      AppToast.error(e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final gameNames = _games
        .map((g) => (g['gameName'] ?? g['typeName'] ?? g['gameType'] ?? g['type'] ?? '').toString())
        .where((s) => s.isNotEmpty)
        .toList();
    return HostSubPageScaffold(
      title: '\u8d54\u7387\u8bbe\u7f6e',
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                if (gameNames.isNotEmpty)
                  SizedBox(
                    height: 40.h,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: EdgeInsets.symmetric(horizontal: 12.w),
                      itemCount: gameNames.length,
                      separatorBuilder: (_, _) => SizedBox(width: 8.w),
                      itemBuilder: (_, i) {
                        final active = i == _gameIndex;
                        return GestureDetector(
                          onTap: () async {
                            setState(() => _gameIndex = i);
                            await _loadOdds();
                          },
                          child: Container(
                            padding: EdgeInsets.symmetric(horizontal: 12.w),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: active ? AppColors.navBlue : Colors.white,
                              borderRadius: BorderRadius.circular(16.r),
                            ),
                            child: Text(
                              gameNames[i],
                              style: TextStyle(
                                fontSize: 13.sp,
                                color: active ? Colors.white : AppColors.textPrimary,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                Padding(
                  padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 0),
                  child: Row(
                    children: [
                      Text('\u7edf\u4e00\u8c03\u6574', style: TextStyle(fontSize: 13.sp)),
                      SizedBox(width: 8.w),
                      SizedBox(
                        width: 64.w,
                        child: EmulatorSafeTextField(
                          controller: _unifyCtrl,
                          textAlign: TextAlign.center,
                          decoration: const InputDecoration(
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => _adjustAll(1),
                        icon: const Icon(Icons.add_circle_outline),
                      ),
                      IconButton(
                        onPressed: () => _adjustAll(-1),
                        icon: const Icon(Icons.remove_circle_outline),
                      ),
                      const Spacer(),
                      if (_dirty)
                        Text(
                          '\u672a\u4fdd\u5b58',
                          style: TextStyle(fontSize: 12.sp, color: AppColors.danger),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: _rows.isEmpty
                      ? Center(
                          child: Text(
                            '\u6682\u65e0\u6570\u636e',
                            style: TextStyle(fontSize: 14.sp, color: AppColors.textHint),
                          ),
                        )
                      : ListView.separated(
                          padding: EdgeInsets.all(16.w),
                          itemCount: _rows.length,
                          separatorBuilder: (_, _) => SizedBox(height: 8.h),
                          itemBuilder: (_, i) {
                            final r = _rows[i];
                            return HostWhiteCard(
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(r.name, style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600)),
                                        Text(
                                          'min ${r.minBet} / period ${r.periodLimit}',
                                          style: TextStyle(fontSize: 11.sp, color: AppColors.textHint),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Text('${r.odds}', style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w700)),
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
      bottomBar: Padding(
        padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 16.h),
        child: HostPrimaryButton(
          label: '\u4fdd\u5b58',
          onPressed: () => _save(),
        ),
      ),
    );
  }
}
