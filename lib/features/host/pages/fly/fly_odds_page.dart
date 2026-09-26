import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../../config/theme/app_colors.dart';
import '../../../../data/repositories/providers.dart';
import '../../../../shared/format/display_number.dart';
import '../../../../shared/widgets/emulator_safe_text_field.dart';
import '../../../../shared/widgets/page_app_bar.dart';
import '../../data/host_mock.dart';
import '../../widgets/host_ui.dart';

/// 盘口标准赔率 H。抽佣 = (代理会员赔率 − 飞单赔率) / H。限制调节：下限平台最低，上限会员赔率。
const _playOddsCeiling = <String, double>{
  'TM': 9.995,
  'LM': 1.998,
  'GYH_DS': 2.1,
  'GYH_XS': 1.775,
  'GYH_BIG': 2.1,
  'GYH_SMALL': 1.775,
  'GYH_ODD': 1.998,
  'GYH_EVEN': 1.998,
  'GYH_3': 42,
  'GYH_5': 21,
  'GYH_7': 13,
  'GYH_9': 11,
  'GYH_11': 8.5,
  'POS': 9.995,
  'DT': 1.998,
};

class _OddsRow {
  _OddsRow({
    required this.playCode,
    required this.playName,
    required this.roomOdds,
    required this.memberOdds,
    required this.odds,
    required this.oddsMax,
    required this.oddsMin,
    required this.periodLimit,
    required this.controller,
  });

  final String playCode;
  final String playName;
  final double? roomOdds;
  final double? memberOdds;
  final double? oddsMax;
  final double? oddsMin;
  final double? periodLimit;
  double odds;
  final TextEditingController controller;

  void dispose() => controller.dispose();
}

/// 某个彩种的飞单赔率。飞单赔率可输入，抽佣比例随输入变化，保存时一次提交。
class FlyOddsPage extends ConsumerStatefulWidget {
  const FlyOddsPage({
    super.key,
    required this.roomId,
    this.gameType = 'JS_SC',
    this.gameName,
  });

  final String roomId;
  final String gameType;
  final String? gameName;

  @override
  ConsumerState<FlyOddsPage> createState() => _FlyOddsPageState();
}

class _FlyOddsPageState extends ConsumerState<FlyOddsPage> {
  bool _dirty = false;
  bool _loading = true;
  bool _saving = false;
  bool _unbound = false;
  final _step = 0.01;
  List<_OddsRow> _rows = [];

  bool get _pk10 => widget.gameType == 'JS_SC' || widget.gameType == 'AZXY10';

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  @override
  void dispose() {
    _clearRows();
    super.dispose();
  }

  void _clearRows() {
    for (final row in _rows) {
      row.dispose();
    }
    _rows = [];
  }

  double? _num(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse('$value');
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _unbound = false;
    });
    try {
      final repo = ref.read(ownerRepositoryProvider);
      final status = await repo.getFeipanStatus();
      if (status['bound'] != true) {
        if (!mounted) return;
        _clearRows();
        setState(() {
          _unbound = true;
          _loading = false;
        });
        return;
      }
      final data = await repo.getFeipanOdds(gameType: widget.gameType);
      final roomByCode = await _roomOddsByCode(repo);
      final items = hostRowsOf(data['items']);
      final rows = <_OddsRow>[];
      for (final m in items) {
        final code = (m['playCode'] ?? '').toString();
        final name = (m['playName'] ?? m['playCode'] ?? '').toString();
        final odds = _num(m['odds']) ?? 0;
        final ceiling = _num(m['oddsMax']) ?? _playOddsCeiling[code];
        final floor = _num(m['oddsMin']);
        final room = _num(m['roomOdds']) ?? roomByCode[code] ?? roomByCode[name];
        final memberOdds = _num(m['memberOdds']);
        rows.add(
          _OddsRow(
            playCode: code,
            playName: name,
            roomOdds: room,
            memberOdds: memberOdds,
            odds: odds,
            oddsMax: ceiling,
            oddsMin: floor,
            periodLimit: _num(m['periodLimit']),
            controller: TextEditingController(text: displayNumber(odds)),
          ),
        );
      }
      if (!mounted) {
        for (final row in rows) {
          row.dispose();
        }
        return;
      }
      _clearRows();
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

  /// 房间赔率走已有的房间赔率接口，按玩法编号、玩法名对齐。
  Future<Map<String, double>> _roomOddsByCode(dynamic repo) async {
    try {
      final data = await repo.getOdds(gameType: widget.gameType);
      final map = <String, double>{};
      for (final m in hostRowsOf(data.containsKey('items') ? data['items'] : data)) {
        final odds = _num(m['odds']);
        if (odds == null) continue;
        final code = (m['playCode'] ?? '').toString();
        final name = (m['playName'] ?? '').toString();
        if (code.isNotEmpty) map[code] = odds;
        if (name.isNotEmpty) map[name] = odds;
      }
      return map;
    } catch (_) {
      return const {};
    }
  }

  double _flyOf(_OddsRow row) {
    final text = row.controller.text.trim();
    return double.tryParse(text) ?? row.odds;
  }

  double? _rangeMax(_OddsRow row) {
    if (row.memberOdds != null && row.memberOdds! > 0) return row.memberOdds;
    return row.oddsMax;
  }

  double? _rangeMin(_OddsRow row) {
    final max = _rangeMax(row);
    final floor = row.oddsMin ??
        (row.oddsMax == null ? null : row.oddsMax! * 0.96);
    if (max == null) return floor;
    if (floor == null) return max;
    return floor > max ? max : floor;
  }

  double _clampOdds(_OddsRow row, double value) {
    var v = value;
    final min = _rangeMin(row);
    final max = _rangeMax(row);
    if (min != null && v < min) v = min;
    if (max != null && v > max) v = max;
    if (v < 0.01) v = 0.01;
    return double.parse(v.toStringAsFixed(3));
  }

  void _setRowOdds(_OddsRow row, double value) {
    row.odds = _clampOdds(row, value);
    row.controller.text = displayNumber(row.odds);
  }

  void _adjustAll(double delta) {
    setState(() {
      for (final row in _rows) {
        _setRowOdds(row, _flyOf(row) + delta);
      }
      _dirty = true;
    });
  }

  void _onOddsEdited(_OddsRow row, String text) {
    final v = double.tryParse(text.trim());
    setState(() {
      if (v != null) row.odds = v;
      _dirty = true;
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    final items = <Map<String, dynamic>>[];
    for (final row in _rows) {
      final odds = double.tryParse(row.controller.text.trim());
      if (odds == null || odds <= 0) {
        AppToast.error('${row.playName} 请填写有效赔率');
        return;
      }
      final min = _rangeMin(row);
      final max = _rangeMax(row);
      if ((min != null && odds < min) || (max != null && odds > max)) {
        AppToast.error(
          '${row.playName} 飞单赔率须在 ${displayNumber(min)}～${displayNumber(max)}',
        );
        return;
      }
      row.odds = double.parse(odds.toStringAsFixed(3));
      items.add({
        'playCode': row.playCode,
        'odds': row.odds,
      });
    }
    setState(() => _saving = true);
    try {
      await ref.read(ownerRepositoryProvider).updateFeipanOdds({
        'gameType': widget.gameType,
        'items': items,
      });
      if (!mounted) return;
      setState(() => _dirty = false);
      AppToast.success('赔率已保存');
    } catch (e) {
      AppToast.error(e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _reset() async {
    if (_saving) return;
    await _load();
  }

  Future<void> _syncPk10() async {
    if (!_pk10 || _saving) return;
    final ok = await hostConfirm(
      context,
      title: '同步 pk10',
      message: '用代理模板赔率覆盖当前彩种的飞单赔率，未保存的修改会丢掉。',
    );
    if (!ok || !mounted) return;
    setState(() => _saving = true);
    try {
      await ref.read(ownerRepositoryProvider).syncFeipanPk10Odds(
            gameType: widget.gameType,
          );
      if (!mounted) return;
      AppToast.success('已同步 pk10');
      setState(() => _saving = false);
      await _load();
    } catch (e) {
      if (mounted) setState(() => _saving = false);
      AppToast.error(e.toString());
    }
  }

  String _roomText(double? value) {
    if (value == null) return '—';
    return displayNumber(value);
  }

  String _limitText(double? value) {
    if (value == null) return '—';
    return displayNumber(value);
  }

  String _rangeText(_OddsRow row) {
    final min = _rangeMin(row);
    final max = _rangeMax(row);
    if (min == null || max == null) return '';
    return '${displayNumber(min)}～${displayNumber(max)}';
  }

  /// (代理会员赔率 − 当前飞单赔率) / 盘口上限。输入变化时重算。
  String _commissionText(_OddsRow row) {
    final h = row.oddsMax;
    final member = row.memberOdds;
    if (h == null || h <= 0 || member == null) return '—';
    final pct = ((member - _flyOf(row)) / h * 100).clamp(0, 100);
    return '${displayNumber(pct)}%';
  }

  @override
  Widget build(BuildContext context) {
    final title = (widget.gameName ?? '').trim().isEmpty
        ? '飞单赔率'
        : widget.gameName!.trim();
    return HostSubPageScaffold(
      title: title,
      body: _loading
          ? const AppPageLoading()
          : _unbound
              ? _unboundBody()
              : Column(
                  children: [
                    Padding(
                      padding: EdgeInsets.fromLTRB(12.w, 8.h, 12.w, 0),
                      child: HostWhiteCard(
                        padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                '统一调节飞单赔率',
                                style: TextStyle(fontSize: 14.sp),
                              ),
                            ),
                            _stepBtn(Icons.add, () => _adjustAll(_step)),
                            Container(
                              width: 56.w,
                              alignment: Alignment.center,
                              padding: EdgeInsets.symmetric(vertical: 6.h),
                              decoration: BoxDecoration(
                                border: Border.all(color: const Color(0xFFE6EAF0)),
                                borderRadius: BorderRadius.circular(8.r),
                              ),
                              child: Text(
                                _step.toStringAsFixed(2),
                                style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600),
                              ),
                            ),
                            _stepBtn(Icons.remove, () => _adjustAll(-_step)),
                          ],
                        ),
                      ),
                    ),
                    if (_dirty)
                      Padding(
                        padding: EdgeInsets.only(top: 6.h, right: 16.w),
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: Text(
                            '未保存',
                            style: TextStyle(fontSize: 12.sp, color: AppColors.danger),
                          ),
                        ),
                      ),
                    Expanded(
                      child: _rows.isEmpty
                          ? Center(
                              child: Text('暂无数据', style: TextStyle(color: AppColors.textHint)),
                            )
                          : ListView(
                              padding: EdgeInsets.fromLTRB(12.w, 10.h, 12.w, 16.h),
                              children: [
                                HostWhiteCard(
                                  padding: EdgeInsets.zero,
                                  child: Column(
                                    children: [
                                      _head(),
                                      for (var i = 0; i < _rows.length; i++) ...[
                                        const Divider(height: 1, color: AppColors.divider),
                                        _line(_rows[i]),
                                      ],
                                    ],
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ],
                ),
      bottomBar: _loading || _unbound
          ? null
          : Padding(
              padding: EdgeInsets.fromLTRB(12.w, 8.h, 12.w, 16.h),
              child: Row(
                children: [
                  Expanded(
                    child: HostPrimaryButton(
                      label: _saving ? '...' : '保存',
                      enabled: !_saving,
                      onPressed: _save,
                    ),
                  ),
                  SizedBox(width: 8.w),
                  Expanded(
                    child: _barBtn(
                      label: '同步pk10',
                      enabled: _pk10 && !_saving,
                      fg: const Color(0xFF333333),
                      bg: Colors.white,
                      border: const Color(0xFFE0E4EA),
                      onTap: _syncPk10,
                    ),
                  ),
                  SizedBox(width: 8.w),
                  Expanded(
                    child: _barBtn(
                      label: '重置',
                      enabled: !_saving,
                      fg: const Color(0xFFE85D6C),
                      bg: const Color(0xFFFFF1F2),
                      border: const Color(0xFFFFD0D4),
                      onTap: _reset,
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _unboundBody() {
    return Center(
      child: Text(
        '请先绑定代理会员',
        style: TextStyle(fontSize: 14.sp, color: AppColors.textHint),
      ),
    );
  }

  Widget _stepBtn(IconData icon, VoidCallback onTap) {
    return IconButton(
      onPressed: _saving ? null : onTap,
      icon: Icon(icon, size: 20.sp),
    );
  }

  Widget _barBtn({
    required String label,
    required bool enabled,
    required Color fg,
    required Color bg,
    required Color border,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        height: 44.h,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: enabled ? bg : const Color(0xFFF3F4F6),
          borderRadius: BorderRadius.circular(22.r),
          border: Border.all(color: enabled ? border : const Color(0xFFE6E8EC)),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 14.sp,
            fontWeight: FontWeight.w600,
            color: enabled ? fg : AppColors.textHint,
          ),
        ),
      ),
    );
  }

  Widget _head() {
    final style = TextStyle(fontSize: 11.sp, color: AppColors.textSecondary, height: 1.2);
    return Padding(
      padding: EdgeInsets.fromLTRB(8.w, 10.h, 8.w, 10.h),
      child: Row(
        children: [
          Expanded(flex: 24, child: Text('玩法', style: style)),
          Expanded(flex: 16, child: Text('房间赔率', textAlign: TextAlign.center, style: style)),
          Expanded(flex: 22, child: Text('飞单赔率', textAlign: TextAlign.center, style: style)),
          Expanded(flex: 22, child: Text('抽佣比例', textAlign: TextAlign.center, style: style)),
          Expanded(flex: 16, child: Text('网盘限额', textAlign: TextAlign.right, style: style)),
        ],
      ),
    );
  }

  Widget _line(_OddsRow row) {
    final range = _rangeText(row);
    return Padding(
      padding: EdgeInsets.fromLTRB(8.w, 8.h, 8.w, 8.h),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            flex: 24,
            child: Text(
              row.playName,
              style: TextStyle(fontSize: 12.sp, height: 1.25),
            ),
          ),
          Expanded(
            flex: 16,
            child: Text(
              _roomText(row.roomOdds),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.sp, color: const Color(0xFF333333)),
            ),
          ),
          Expanded(
            flex: 22,
            child: EmulatorSafeTextField(
              controller: row.controller,
              enabled: !_saving,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              textAlign: TextAlign.center,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
              style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w700),
              decoration: InputDecoration(
                isDense: true,
                contentPadding: EdgeInsets.symmetric(horizontal: 4.w, vertical: 6.h),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16.r),
                  borderSide: const BorderSide(color: Color(0xFFE6EAF0)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16.r),
                  borderSide: const BorderSide(color: Color(0xFFE6EAF0)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16.r),
                  borderSide: const BorderSide(color: AppColors.navBlue),
                ),
              ),
              onChanged: (text) => _onOddsEdited(row, text),
              onSubmitted: (_) {
                setState(() {
                  _setRowOdds(row, _flyOf(row));
                  _dirty = true;
                });
              },
            ),
          ),
          Expanded(
            flex: 22,
            child: Column(
              children: [
                Text(
                  _commissionText(row),
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w700),
                ),
                if (range.isNotEmpty) ...[
                  Text(
                    '限制调节',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 9.sp, color: AppColors.textHint),
                  ),
                  Text(
                    range,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 9.sp, color: AppColors.textHint, height: 1.2),
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            flex: 16,
            child: Text(
              _limitText(row.periodLimit),
              textAlign: TextAlign.right,
              style: TextStyle(fontSize: 12.sp, color: const Color(0xFF333333)),
            ),
          ),
        ],
      ),
    );
  }
}
