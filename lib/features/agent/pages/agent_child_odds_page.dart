import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../config/theme/app_colors.dart';
import '../../../data/repositories/providers.dart';
import '../../../shared/format/display_number.dart';
import '../../../shared/format/play_odds_merge.dart';
import '../../../shared/widgets/app_page_loading.dart';
import '../../../shared/widgets/emulator_safe_text_field.dart';
import '../../../shared/widgets/page_app_bar.dart';
import '../widgets/agent_ui.dart';

class _OddsPlay {
  const _OddsPlay(this.code, this.storedName);

  final String code;
  final String storedName;
}

class _OddsRow {
  _OddsRow({
    required this.plays,
    required this.name,
    required this.rangeText,
    required this.oddsCtrl,
    required this.maxBetCtrl,
    required this.periodLimitCtrl,
    required this.minBetCtrl,
    required this.gameType,
  });

  final List<_OddsPlay> plays;
  final String name;
  final String rangeText;
  final String gameType;
  final TextEditingController oddsCtrl;
  final TextEditingController maxBetCtrl;
  final TextEditingController periodLimitCtrl;
  final TextEditingController minBetCtrl;

  void dispose() {
    oddsCtrl.dispose();
    maxBetCtrl.dispose();
    periodLimitCtrl.dispose();
    minBetCtrl.dispose();
  }
}

/// 下级赔率：交互对齐房间「赔率设置」，彩种 Tab / 统一调节 / 每玩法卡片。
class AgentChildOddsPage extends ConsumerStatefulWidget {
  const AgentChildOddsPage({
    super.key,
    required this.accountId,
    required this.title,
  });

  final int accountId;
  final String title;

  @override
  ConsumerState<AgentChildOddsPage> createState() => _AgentChildOddsPageState();
}

class _AgentChildOddsPageState extends ConsumerState<AgentChildOddsPage> {
  final List<_OddsRow> _rows = [];
  final _stepCtrl = TextEditingController(text: '0.01');
  bool _loading = true;
  bool _saving = false;
  int _gameIndex = 0;
  final List<({String type, String name})> _games = const [
    (type: 'JS_SC', name: '极速赛车'),
    (type: 'AZXY10', name: '澳洲幸运10'),
  ];

  String get _gameType =>
      _games.isEmpty ? 'JS_SC' : _games[_gameIndex.clamp(0, _games.length - 1)].type;

  @override
  void initState() {
    super.initState();
    Future.microtask(_loadOdds);
  }

  @override
  void dispose() {
    _stepCtrl.dispose();
    _clearRows();
    super.dispose();
  }

  void _clearRows() {
    for (final r in _rows) {
      r.dispose();
    }
    _rows.clear();
  }

  Future<void> _loadOdds() async {
    setState(() => _loading = true);
    try {
      final raw = await ref.read(agentRepositoryProvider).getChildOdds(
            widget.accountId,
            gameType: _gameType,
          );
      if (!mounted) return;
      _clearRows();
      final merged = mergePlayOddsRows(raw);
      for (final m in merged) {
        final shown = m.shown;
        _rows.add(
          _OddsRow(
            plays: [
              for (final c in m.codes)
                if (c.isNotEmpty) _OddsPlay(c, (shown['playName'] ?? m.name).toString()),
            ],
            name: m.name,
            rangeText: '${shown['rangeText'] ?? ''}',
            gameType: '${shown['gameType'] ?? _gameType}',
            oddsCtrl: TextEditingController(text: displayNumber(shown['odds'])),
            maxBetCtrl: TextEditingController(text: displayNumber(shown['maxBet'] ?? shown['minBet'])),
            periodLimitCtrl: TextEditingController(text: displayNumber(shown['periodLimit'])),
            minBetCtrl: TextEditingController(text: displayNumber(shown['minBet'])),
          ),
        );
      }
      setState(() => _loading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      AppToast.error(e.toString());
    }
  }

  double get _step => double.tryParse(_stepCtrl.text.trim()) ?? 0.01;

  void _adjustAll(double sign) {
    final delta = _step * sign;
    setState(() {
      for (final r in _rows) {
        final cur = double.tryParse(r.oddsCtrl.text.trim()) ?? 0;
        var next = double.parse((cur + delta).toStringAsFixed(3));
        if (next < 0) next = 0;
        r.oddsCtrl.text = displayNumber(next);
      }
    });
  }

  Future<void> _onGameChanged(int i) async {
    if (i == _gameIndex) return;
    setState(() => _gameIndex = i);
    await _loadOdds();
  }

  Future<void> _save() async {
    if (_saving) return;
    final payload = <Map<String, dynamic>>[];
    for (final r in _rows) {
      final odds = num.tryParse(r.oddsCtrl.text.trim());
      if (odds == null) {
        AppToast.error('${r.name} 请填写有效赔率');
        return;
      }
      final maxBet = num.tryParse(r.maxBetCtrl.text.trim());
      final period = num.tryParse(r.periodLimitCtrl.text.trim());
      final minBet = num.tryParse(r.minBetCtrl.text.trim());
      for (final play in r.plays) {
        payload.add({
          'gameType': r.gameType.isEmpty ? _gameType : r.gameType,
          'playCode': play.code,
          'odds': odds,
          'minBet': ?minBet,
          'maxBet': ?maxBet,
          'periodLimit': ?period,
        });
      }
    }
    if (payload.isEmpty) {
      AppToast.error('没有赔率数据');
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(agentRepositoryProvider).saveChildOdds(
            widget.accountId,
            payload,
            gameType: _gameType,
          );
      AppToast.success('赔率设置已保存');
      await _loadOdds();
    } catch (e) {
      AppToast.error(e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AgentPageFrame(
      title: '',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AgentBackTitle(title: '修改${_games[_gameIndex.clamp(0, _games.length - 1)].name}倍率'),
          AgentGameTabs(
            games: [for (final g in _games) g.name],
            current: _gameIndex,
            onChanged: _saving ? (_) {} : _onGameChanged,
          ),
          Expanded(
            child: _loading
                ? const AppPageLoading()
                : ListView(
                    padding: EdgeInsets.fromLTRB(0, 8.h, 0, 16.h),
                    children: [
                      AgentSurface(
                        child: _labeledRow(
                          '统一调节赔率',
                          child: _stepperField(
                            controller: _stepCtrl,
                            onMinus: () => _adjustAll(-1),
                            onPlus: () => _adjustAll(1),
                          ),
                        ),
                      ),
                      SizedBox(height: 10.h),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12.w),
                        child: Text(
                          '${_games[_gameIndex.clamp(0, _games.length - 1)].name}赔率',
                          style: TextStyle(
                            fontSize: 15.sp,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                      SizedBox(height: 10.h),
                      if (_rows.isEmpty)
                        Padding(
                          padding: EdgeInsets.symmetric(vertical: 40.h),
                          child: Center(
                            child: Text('暂无数据', style: TextStyle(fontSize: 14.sp, color: AppColors.textHint)),
                          ),
                        )
                      else
                        for (var i = 0; i < _rows.length; i++) ...[
                          _playCard(i, _rows[i]),
                          SizedBox(height: 10.h),
                        ],
                    ],
                  ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(12.w, 8.h, 12.w, 16.h),
            child: AgentTealButton(
              label: _saving ? '...' : '保存',
              block: true,
              onTap: _loading || _saving ? () {} : _save,
            ),
          ),
        ],
      ),
    );
  }

  Widget _playCard(int index, _OddsRow row) {
    final no = (index + 1).toString().padLeft(2, '0');
    return AgentSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 3.h),
                decoration: BoxDecoration(
                  color: AgentChrome.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(4.r),
                ),
                child: Text(
                  no,
                  style: TextStyle(
                    fontSize: 12.sp,
                    color: AgentChrome.accent,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              SizedBox(width: 8.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(row.name, style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600)),
                    if (row.rangeText.trim().isNotEmpty)
                      Text(
                        row.rangeText,
                        style: TextStyle(fontSize: 11.sp, color: AppColors.textHint),
                      ),
                  ],
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
          SizedBox(height: 10.h),
          _fieldCol('单注最低', row.minBetCtrl),
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
      color: AgentChrome.accent.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(8.r),
      child: InkWell(
        onTap: _saving ? null : onTap,
        borderRadius: BorderRadius.circular(8.r),
        child: SizedBox(
          width: 36.w,
          height: 36.w,
          child: Icon(icon, size: 18.sp, color: AgentChrome.accent),
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
      enabled: !_saving,
      keyboardType: keyboardType,
      textAlign: textAlign,
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
      ],
      decoration: InputDecoration(
        isDense: true,
        contentPadding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 10.h),
        filled: true,
        fillColor: AgentChrome.fieldBg,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8.r),
          borderSide: const BorderSide(color: AgentChrome.cardBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8.r),
          borderSide: const BorderSide(color: AgentChrome.cardBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8.r),
          borderSide: const BorderSide(color: AgentChrome.accent, width: 1.2),
        ),
      ),
    );
  }
}
