import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../../config/theme/app_colors.dart';
import '../../../../data/repositories/providers.dart';
import '../../../../shared/format/game_series.dart';
import '../../../../shared/widgets/emulator_safe_text_field.dart';
import '../../../../shared/widgets/page_app_bar.dart';
import '../../data/host_mock.dart';
import '../../widgets/host_ui.dart';

/// 某个彩种的赔率编辑页；顶栏可切换其它彩种；系列模式保存时同步同类型
class HostOddsEditPage extends ConsumerStatefulWidget {
  const HostOddsEditPage({
    super.key,
    required this.roomId,
    required this.gameType,
    required this.gameName,
    required this.games,
    this.seriesMode = false,
  });

  final String roomId;
  final String gameType;
  final String gameName;
  final List<({String type, String name})> games;
  /// true：按赛车系列编辑，保存默认同步同类型
  final bool seriesMode;

  @override
  ConsumerState<HostOddsEditPage> createState() => _HostOddsEditPageState();
}

class _OddsPlay {
  const _OddsPlay(this.code, this.storedName);

  final String code;
  final String storedName;
}

class _OddsRow {
  _OddsRow({
    required this.plays,
    required this.name,
    required this.oddsCtrl,
    required this.maxBetCtrl,
    required this.periodLimitCtrl,
  });

  final List<_OddsPlay> plays;
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

class _ParsedOdd {
  _ParsedOdd({
    required this.code,
    required this.storedName,
    required this.odds,
    required this.maxBet,
    required this.period,
  });

  final String code;
  final String storedName;
  final dynamic odds;
  final dynamic maxBet;
  final dynamic period;
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
      final parsed = <_ParsedOdd>[];
      for (final m in items) {
        final minBet = m['minBet'] is num
            ? m['minBet'] as num
            : num.tryParse('${m['minBet']}') ?? 1;
        firstMin ??= minBet;
        parsed.add(_ParsedOdd(
          code: (m['playCode'] ?? '').toString(),
          storedName: (m['playName'] ?? m['playCode'] ?? '').toString(),
          odds: m['odds'] ?? 0,
          maxBet: m['maxBet'] ?? m['minBet'] ?? 20000,
          period: m['periodLimit'] ?? 0,
        ));
      }
      for (final row in _mergeOdds(parsed)) {
        _rows.add(row);
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
    return hostNumStr(keepDecimal ? v : v);
  }

  List<_OddsRow> _mergeOdds(List<_ParsedOdd> items) {
    _ParsedOdd? pick(String code) {
      for (final it in items) {
        if (it.code.toUpperCase() == code) return it;
      }
      return null;
    }

    bool used(String code) =>
        code.toUpperCase() == 'TM' ||
        code.toUpperCase() == 'POS' ||
        code.toUpperCase() == 'LM' ||
        code.toUpperCase() == 'DT';

    final rows = <_OddsRow>[];
    final tm = pick('TM');
    final pos = pick('POS');
    if (tm != null || pos != null) {
      rows.add(_pairRow('特码', tm ?? pos!, [tm, pos]));
    }
    final lm = pick('LM');
    final dt = pick('DT');
    if (lm != null || dt != null) {
      rows.add(_pairRow('两面-龙虎', lm ?? dt!, [lm, dt]));
    }
    final rest = items.where((it) => !used(it.code)).toList()
      ..sort((a, b) => _oddsRank(a.code).compareTo(_oddsRank(b.code)));
    for (final it in rest) {
      rows.add(_pairRow(it.storedName, it, [it]));
    }
    return rows;
  }

  _OddsRow _pairRow(String name, _ParsedOdd shown, List<_ParsedOdd?> members) {
    final plays = <_OddsPlay>[];
    for (final m in members) {
      if (m == null) continue;
      plays.add(_OddsPlay(m.code, m.storedName));
    }
    return _OddsRow(
      plays: plays,
      name: name,
      oddsCtrl: TextEditingController(text: _numText(shown.odds, keepDecimal: true)),
      maxBetCtrl: TextEditingController(text: _numText(shown.maxBet)),
      periodLimitCtrl: TextEditingController(text: _numText(shown.period)),
    );
  }

  int _oddsRank(String code) {
    const order = [
      'GYH_DS',
      'GYH_BIG',
      'GYH_EVEN',
      'GYH_XS',
      'GYH_SMALL',
      'GYH_ODD',
      'GYH_3',
      'GYH_5',
      'GYH_7',
      'GYH_9',
      'GYH_11',
    ];
    final i = order.indexOf(code.toUpperCase());
    if (i >= 0) return i;
    if (code.toUpperCase().startsWith('GYH')) return 50;
    return 80;
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

  Future<void> _save({bool syncSameSeries = false}) async {
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
      for (final play in r.plays) {
        items.add({
          'playCode': play.code,
          'playName': play.storedName,
          'odds': odds,
          'minBet': minLimit,
          'maxBet': maxBet,
          'periodLimit': period,
        });
      }
    }
    final doSync = syncSameSeries || widget.seriesMode;
    if (doSync && GameSeries.peersOf(_gameType).isNotEmpty) {
      final peers = GameSeries.peerNamesHint(_gameType);
      final ok = await hostConfirm(
        context,
        title: '同步同类型游戏',
        message: '将把当前赔率同步到：$peers。各彩种原值将被覆盖。',
      );
      if (!ok || !mounted) return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(ownerRepositoryProvider).updateOdds({
        'gameType': _gameType,
        'items': items,
        'syncSameSeries': doSync,
      });
      AppToast.success(doSync ? '已保存并同步同类型' : '赔率设置已保存');
      await _loadOdds(silent: true);
    } catch (e) {
      AppToast.error(e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _onMore() async {
    if (_saving || _loading) return;
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('保存'),
              onTap: () => Navigator.pop(ctx, 'save'),
            ),
            if (GameSeries.isPk10(_gameType))
              ListTile(
                title: const Text('同步同类型游戏'),
                subtitle: Text('覆盖 ${GameSeries.peerNamesHint(_gameType)}'),
                onTap: () => Navigator.pop(ctx, 'sync'),
              ),
            ListTile(
              title: const Text('取消'),
              onTap: () => Navigator.pop(ctx),
            ),
          ],
        ),
      ),
    );
    if (action == 'save') await _save();
    if (action == 'sync') await _save(syncSameSeries: true);
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.seriesMode
        ? '修改${GameSeries.seriesNameOf(_gameType)}倍率'
        : '修改$_gameName倍率';
    return HostSubPageScaffold(
      title: title,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (GameSeries.isPk10(_gameType))
            IconButton(
              onPressed: _saving || _loading ? null : _onMore,
              icon: Icon(Icons.more_horiz, color: AppColors.navBlue, size: 22.sp),
            ),
          TextButton(
            onPressed: _saving || _loading
                ? null
                : () => _save(syncSameSeries: widget.seriesMode),
            child: Text(
              _saving ? '...' : (widget.seriesMode ? '同步保存' : '保存'),
              style: TextStyle(
                fontSize: 15.sp,
                color: AppColors.navBlue,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
      body: _loading
          ? const AppPageLoading()
          : ListView(
              padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 24.h),
              children: [
                if (widget.seriesMode || GameSeries.isPk10(_gameType)) ...[
                  Container(
                    width: double.infinity,
                    padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8F0FF),
                      borderRadius: BorderRadius.circular(8.r),
                      border: Border.all(color: const Color(0xFFB8D0FF)),
                    ),
                    child: Text(
                      widget.seriesMode
                          ? '保存后同步到：${GameSeries.pk10Members.map(GameSeries.displayName).join('、')}。若各彩种原赔率不同，将被当前值覆盖。'
                          : '可将当前设置「同步同类型」到 ${GameSeries.peerNamesHint(_gameType)}',
                      style: TextStyle(fontSize: 12.sp, color: const Color(0xFF1A4BAA), height: 1.4),
                    ),
                  ),
                  SizedBox(height: 10.h),
                ],
                _gameCard(),
                SizedBox(height: 10.h),
                _globalCard(),
                SizedBox(height: 16.h),
                Text(
                  widget.seriesMode ? '${GameSeries.seriesNameOf(_gameType)}赔率' : '$_gameName赔率',
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
    final canSwitch = !widget.seriesMode && widget.games.length > 1;
    final label = widget.seriesMode ? GameSeries.seriesNameOf(_gameType) : _gameName;
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w600),
                  ),
                  if (widget.seriesMode)
                    Text(
                      '底稿：$_gameName',
                      style: TextStyle(fontSize: 11.sp, color: AppColors.textHint),
                    ),
                ],
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
