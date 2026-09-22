import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../../config/theme/app_colors.dart';
import '../../../../data/repositories/providers.dart';
import '../../../../shared/widgets/emulator_safe_text_field.dart';
import '../../../../shared/widgets/page_app_bar.dart';
import '../../data/host_mock.dart';
import '../../widgets/host_ui.dart';

/// 某个彩种的赔率编辑页；顶栏可切换其它彩种
class HostOddsEditPage extends ConsumerStatefulWidget {
  const HostOddsEditPage({
    super.key,
    required this.roomId,
    required this.gameType,
    required this.gameName,
    required this.games,
  });

  final String roomId;
  final String gameType;
  final String gameName;
  final List<({String type, String name})> games;

  @override
  ConsumerState<HostOddsEditPage> createState() => _HostOddsEditPageState();
}

class _OddsRow {
  _OddsRow({
    required this.playCode,
    required this.name,
    required this.oddsCtrl,
    required this.maxBetCtrl,
    required this.periodLimitCtrl,
  });

  final String playCode;
  final String name;
  final TextEditingController oddsCtrl;
  final TextEditingController maxBetCtrl;
  final TextEditingController periodLimitCtrl;

  void dispose() {
    oddsCtrl.dispose();
    maxBetCtrl.dispose();
    periodLimitCtrl.dispose();
  }
}

class _HostOddsEditPageState extends ConsumerState<HostOddsEditPage> {
  final List<_OddsRow> _rows = [];
  late String _gameType;
  late String _gameName;
  bool _loading = true;
  bool _saving = false;

  final _stepCtrl = TextEditingController(text: '0.01');
  final _minLimitCtrl = TextEditingController(text: '1');

  @override
  void initState() {
    super.initState();
    _gameType = widget.gameType;
    _gameName = widget.gameName;
    Future.microtask(_loadOdds);
  }

  @override
  void dispose() {
    _stepCtrl.dispose();
    _minLimitCtrl.dispose();
    _clearRows();
    super.dispose();
  }

  void _clearRows() {
    for (final r in _rows) {
      r.dispose();
    }
    _rows.clear();
  }

  Future<void> _loadOdds({bool silent = false}) async {
    if (!silent && mounted) setState(() => _loading = true);
    try {
      final data =
          await ref.read(ownerRepositoryProvider).getOdds(gameType: _gameType);
      final items = hostRowsOf(data.containsKey('items') ? data['items'] : data);
      _clearRows();
      num? firstMin;
      for (final m in items) {
        final minBet = m['minBet'] is num
            ? m['minBet'] as num
            : num.tryParse('${m['minBet']}') ?? 1;
        firstMin ??= minBet;
        final maxBet = m['maxBet'] ?? m['minBet'] ?? 20000;
        final period = m['periodLimit'] ?? 0;
        final odds = m['odds'] ?? 0;
        _rows.add(
          _OddsRow(
            playCode: (m['playCode'] ?? '').toString(),
            name: (m['playName'] ?? m['playCode'] ?? '').toString(),
            oddsCtrl: TextEditingController(text: _numText(odds, keepDecimal: true)),
            maxBetCtrl: TextEditingController(text: _numText(maxBet)),
            periodLimitCtrl: TextEditingController(text: _numText(period)),
          ),
        );
      }
      final gn = (data['gameName'] ?? '').toString();
      if (gn.isNotEmpty) _gameName = gn;
      _minLimitCtrl.text = _numText(firstMin ?? 1);
      if (!mounted) return;
      setState(() => _loading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      AppToast.error(e.toString());
    }
  }

  String _numText(dynamic v, {bool keepDecimal = false}) {
    if (v == null) return '0';
    final n = v is num ? v : num.tryParse('$v');
    if (n == null) return '$v';
    if (keepDecimal) {
      if (n == n.roundToDouble()) return '${n.toInt()}';
      var s = n.toStringAsFixed(3);
      s = s.replaceFirst(RegExp(r'0+$'), '');
      s = s.replaceFirst(RegExp(r'\.$'), '');
      return s;
    }
    if (n == n.roundToDouble()) return '${n.toInt()}';
    return n.toStringAsFixed(2);
  }

  double get _step => double.tryParse(_stepCtrl.text.trim()) ?? 0.01;

  void _adjustAll(double sign) {
    final delta = _step * sign;
    setState(() {
      for (final r in _rows) {
        final cur = double.tryParse(r.oddsCtrl.text.trim()) ?? 0;
        var next = double.parse((cur + delta).toStringAsFixed(3));
        if (next < 0) next = 0;
        r.oddsCtrl.text = _numText(next, keepDecimal: true);
      }
    });
  }

  Future<void> _switchGame() async {
    final games = widget.games;
    if (games.length <= 1) return;
    final picked = await showModalBottomSheet<({String type, String name})>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(16.r)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: EdgeInsets.symmetric(vertical: 12.h),
                child: Text(
                  '切换彩种',
                  style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w700),
                ),
              ),
              for (final g in games)
                ListTile(
                  title: Text(g.name),
                  trailing: g.type == _gameType
                      ? Icon(Icons.check, color: AppColors.navBlue)
                      : null,
                  onTap: () => Navigator.pop(ctx, g),
                ),
              SizedBox(height: 8.h),
            ],
          ),
        ),
      ),
    );
    if (picked == null || picked.type == _gameType || !mounted) return;
    setState(() {
      _gameType = picked.type;
      _gameName = picked.name;
    });
    await _loadOdds();
  }

  Future<void> _save() async {
    final minLimit = num.tryParse(_minLimitCtrl.text.trim()) ?? 1;
    final items = <Map<String, dynamic>>[];
    for (final r in _rows) {
      final odds = double.tryParse(r.oddsCtrl.text.trim());
      final maxBet = num.tryParse(r.maxBetCtrl.text.trim());
      final period = num.tryParse(r.periodLimitCtrl.text.trim());
      if (odds == null || maxBet == null || period == null) {
        AppToast.error('${r.name} 请填写有效数字');
        return;
      }
      items.add({
        'playCode': r.playCode,
        'playName': r.name,
        'odds': odds,
        'minBet': minLimit,
        'maxBet': maxBet,
        'periodLimit': period,
      });
    }
    setState(() => _saving = true);
    try {
      await ref.read(ownerRepositoryProvider).updateOdds({
        'gameType': _gameType,
        'items': items,
      });
      AppToast.success('赔率设置已保存');
      await _loadOdds(silent: true);
    } catch (e) {
      AppToast.error(e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return HostSubPageScaffold(
      title: '修改$_gameName倍率',
      trailing: TextButton(
        onPressed: _saving || _loading ? null : _save,
        child: Text(
          _saving ? '...' : '保存',
          style: TextStyle(
            fontSize: 15.sp,
            color: AppColors.navBlue,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: _loading
          ? const AppPageLoading()
          : ListView(
              padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 24.h),
              children: [
                _gameCard(),
                SizedBox(height: 10.h),
                _globalCard(),
                SizedBox(height: 16.h),
                Text(
                  '$_gameName赔率',
                  style: TextStyle(
                    fontSize: 15.sp,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                SizedBox(height: 10.h),
                if (_rows.isEmpty)
                  Padding(
                    padding: EdgeInsets.symmetric(vertical: 40.h),
                    child: Center(
                      child: Text(
                        '暂无数据',
                        style: TextStyle(fontSize: 14.sp, color: AppColors.textHint),
                      ),
                    ),
                  )
                else
                  for (var i = 0; i < _rows.length; i++) ...[
                    _playCard(i, _rows[i]),
                    SizedBox(height: 10.h),
                  ],
              ],
            ),
    );
  }

  Widget _gameCard() {
    final canSwitch = widget.games.length > 1;
    return GestureDetector(
      onTap: canSwitch ? _switchGame : null,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 12.h),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12.r),
        ),
        child: Row(
          children: [
            Container(
              width: 36.w,
              height: 36.w,
              decoration: BoxDecoration(
                color: AppColors.navBlue.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8.r),
              ),
              child: Icon(Icons.bar_chart_rounded, color: AppColors.navBlue, size: 20.sp),
            ),
            SizedBox(width: 10.w),
            Expanded(
              child: Text(
                _gameName,
                style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w600),
              ),
            ),
            if (canSwitch) ...[
              Text('切换', style: TextStyle(fontSize: 13.sp, color: AppColors.navBlue)),
              SizedBox(width: 2.w),
              Icon(Icons.swap_horiz, size: 18.sp, color: AppColors.navBlue),
            ],
          ],
        ),
      ),
    );
  }

  Widget _globalCard() {
    return Container(
      padding: EdgeInsets.fromLTRB(14.w, 12.h, 14.w, 14.h),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12.r),
      ),
      child: Column(
        children: [
          _labeledRow(
            '统一调节赔率',
            child: _stepperField(
              controller: _stepCtrl,
              onMinus: () => _adjustAll(-1),
              onPlus: () => _adjustAll(1),
            ),
          ),
          SizedBox(height: 12.h),
          _labeledRow(
            '最低限额',
            child: _boxField(
              controller: _minLimitCtrl,
              keyboardType: TextInputType.number,
            ),
          ),
        ],
      ),
    );
  }

  Widget _playCard(int index, _OddsRow row) {
    final no = (index + 1).toString().padLeft(2, '0');
    return Container(
      padding: EdgeInsets.fromLTRB(12.w, 12.h, 12.w, 14.h),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12.r),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 3.h),
                decoration: BoxDecoration(
                  color: AppColors.navBlue.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(4.r),
                ),
                child: Text(
                  no,
                  style: TextStyle(
                    fontSize: 12.sp,
                    color: AppColors.navBlue,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              SizedBox(width: 8.w),
              Expanded(
                child: Text(
                  row.name,
                  style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          SizedBox(height: 12.h),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _fieldCol('赔率', row.oddsCtrl, decimal: true)),
              SizedBox(width: 8.w),
              Expanded(child: _fieldCol('单注限额', row.maxBetCtrl)),
              SizedBox(width: 8.w),
              Expanded(child: _fieldCol('单期总限额', row.periodLimitCtrl)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _fieldCol(String label, TextEditingController ctrl, {bool decimal = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 12.sp, color: AppColors.textSecondary)),
        SizedBox(height: 6.h),
        _boxField(
          controller: ctrl,
          keyboardType: decimal
              ? const TextInputType.numberWithOptions(decimal: true)
              : TextInputType.number,
        ),
      ],
    );
  }

  Widget _labeledRow(String label, {required Widget child}) {
    return Row(
      children: [
        SizedBox(
          width: 100.w,
          child: Text(label, style: TextStyle(fontSize: 14.sp)),
        ),
        Expanded(child: child),
      ],
    );
  }

  Widget _stepperField({
    required TextEditingController controller,
    required VoidCallback onMinus,
    required VoidCallback onPlus,
  }) {
    return Row(
      children: [
        _roundBtn(Icons.remove, onMinus),
        SizedBox(width: 8.w),
        Expanded(
          child: _boxField(
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textAlign: TextAlign.center,
          ),
        ),
        SizedBox(width: 8.w),
        _roundBtn(Icons.add, onPlus),
      ],
    );
  }

  Widget _roundBtn(IconData icon, VoidCallback onTap) {
    return Material(
      color: AppColors.navBlue.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(8.r),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8.r),
        child: SizedBox(
          width: 36.w,
          height: 36.w,
          child: Icon(icon, size: 18.sp, color: AppColors.navBlue),
        ),
      ),
    );
  }

  Widget _boxField({
    required TextEditingController controller,
    TextInputType? keyboardType,
    TextAlign textAlign = TextAlign.start,
  }) {
    return EmulatorSafeTextField(
      controller: controller,
      keyboardType: keyboardType,
      textAlign: textAlign,
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
      ],
      decoration: InputDecoration(
        isDense: true,
        contentPadding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 10.h),
        filled: true,
        fillColor: const Color(0xFFF7F8FA),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8.r),
          borderSide: const BorderSide(color: Color(0xFFE5E5E5)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8.r),
          borderSide: const BorderSide(color: Color(0xFFE5E5E5)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8.r),
          borderSide: BorderSide(color: AppColors.navBlue, width: 1.2),
        ),
      ),
    );
  }
}
