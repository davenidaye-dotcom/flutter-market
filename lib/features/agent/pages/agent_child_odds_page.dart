import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../config/theme/app_colors.dart';
import '../../../data/repositories/providers.dart';
import '../../../shared/format/display_number.dart';
import '../../../shared/format/game_series.dart';
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
    this.parentOdds,
    this.hPlay,
  });

  final List<_OddsPlay> plays;
  final String name;
  final String rangeText;
  final String gameType;
  final TextEditingController oddsCtrl;
  final TextEditingController maxBetCtrl;
  final TextEditingController periodLimitCtrl;
  final TextEditingController minBetCtrl;
  final num? parentOdds;
  final num? hPlay;

  String rebateLabel() {
    final odds = num.tryParse(oddsCtrl.text.trim());
    final p = parentOdds;
    final h = hPlay;
    if (odds == null || p == null || h == null || h == 0) {
      return '抽用返点0%';
    }
    var r = (p - odds) / h * 100;
    if (r < 0) r = 0;
    return '抽用返点${displayNumber(r)}%';
  }

  void dispose() {
    oddsCtrl.dispose();
    maxBetCtrl.dispose();
    periodLimitCtrl.dispose();
    minBetCtrl.dispose();
  }
}

/// 下级赔率返水 — 对齐参考：统一修改 + 彩种胶囊 Tab + 玩法卡（赔率/返点说明/单期限额）
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
  final _stepCtrl = TextEditingController(text: '0.100');
  final _minLimitCtrl = TextEditingController(text: '1');
  bool _loading = true;
  bool _saving = false;
  /// 默认勾选：保存时同步同系列
  bool _syncSameSeries = true;
  int _gameIndex = 0;
  final List<({String type, String name})> _games = const [
    (type: 'JS_SC', name: '极速赛车'),
    (type: 'AZXY10', name: '澳洲幸运10'),
    (type: 'TW_BG_Q', name: '台湾宾果赛车(前)'),
    (type: 'TW_BG_H', name: '台湾宾果赛车(后)'),
  ];

  static const _pageBg = Color(0xFFE8EEF5);
  static const _tabIdle = Color(0xFF8A94A6);
  static const _tabActive = Color(0xFF5C6B7A);

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

  num? _asNum(dynamic v) {
    if (v == null) return null;
    if (v is num) return v;
    return num.tryParse('$v'.trim());
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
      num? firstMin;
      for (final m in merged) {
        final shown = m.shown;
        final minBet = _asNum(shown['minBet']);
        firstMin ??= minBet;
        _rows.add(
          _OddsRow(
            plays: [
              for (final c in m.codes)
                if (c.isNotEmpty) _OddsPlay(c, (shown['playName'] ?? m.name).toString()),
            ],
            name: m.name,
            rangeText: '${shown['rangeText'] ?? ''}',
            gameType: '${shown['gameType'] ?? _gameType}',
            oddsCtrl: TextEditingController(text: displayNumber(shown['odds'], maxDecimals: 4)),
            maxBetCtrl: TextEditingController(text: displayNumber(shown['maxBet'] ?? 50000)),
            periodLimitCtrl: TextEditingController(
              text: displayNumber(shown['periodLimit'] ?? shown['userPeriodLimit'] ?? 0),
            ),
            minBetCtrl: TextEditingController(text: displayNumber(minBet ?? 1)),
            parentOdds: _asNum(shown['parentOdds']),
            hPlay: _asNum(shown['hPlay']),
          ),
        );
      }
      _minLimitCtrl.text = displayNumber(firstMin ?? 1);
      setState(() => _loading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      AppToast.error(e.toString());
    }
  }

  double get _step => double.tryParse(_stepCtrl.text.trim()) ?? 0.1;

  void _adjustAll(double sign) {
    final delta = _step * sign;
    setState(() {
      for (final r in _rows) {
        final cur = double.tryParse(r.oddsCtrl.text.trim()) ?? 0;
        var next = double.parse((cur + delta).toStringAsFixed(3));
        if (next < 0) next = 0;
        r.oddsCtrl.text = displayNumber(next, maxDecimals: 4);
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
    final globalMin = num.tryParse(_minLimitCtrl.text.trim()) ?? 1;
    final payload = <Map<String, dynamic>>[];
    for (final r in _rows) {
      final odds = num.tryParse(r.oddsCtrl.text.trim());
      if (odds == null) {
        AppToast.error('${r.name} 请填写有效赔率');
        return;
      }
      final maxBet = num.tryParse(r.maxBetCtrl.text.trim());
      final period = num.tryParse(r.periodLimitCtrl.text.trim());
      final minBet = num.tryParse(r.minBetCtrl.text.trim()) ?? globalMin;
      for (final play in r.plays) {
        payload.add({
          'gameType': r.gameType.isEmpty ? _gameType : r.gameType,
          'playCode': play.code,
          'odds': odds,
          'minBet': minBet,
          'maxBet': ?maxBet,
          'periodLimit': ?period,
        });
      }
    }
    if (payload.isEmpty) {
      AppToast.error('没有赔率数据');
      return;
    }
    final doSync = _syncSameSeries && GameSeries.isPk10(_gameType);
    setState(() => _saving = true);
    try {
      await ref.read(agentRepositoryProvider).saveChildOdds(
            widget.accountId,
            payload,
            gameType: _gameType,
            syncSameSeries: doSync,
          );
      AppToast.success(doSync ? '已保存并同步同类型' : '赔率返水已保存');
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
      child: ColoredBox(
        color: _pageBg,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _topBar(),
            Expanded(
              child: _loading
                  ? const AppPageLoading()
                  : ListView(
                      padding: EdgeInsets.fromLTRB(12.w, 8.h, 12.w, 20.h),
                      children: [
                        _infoCard(),
                        SizedBox(height: 10.h),
                        _unifyCard(),
                        SizedBox(height: 12.h),
                        _gamePills(),
                        SizedBox(height: 12.h),
                        if (_rows.isEmpty)
                          Padding(
                            padding: EdgeInsets.symmetric(vertical: 40.h),
                            child: Center(
                              child: Text('暂无数据', style: TextStyle(fontSize: 14.sp, color: AppColors.textHint)),
                            ),
                          )
                        else
                          for (final r in _rows) ...[
                            _playCard(r),
                            SizedBox(height: 10.h),
                          ],
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _topBar() {
    return Container(
      color: Colors.white,
      padding: EdgeInsets.fromLTRB(4.w, 4.h, 12.w, 4.h),
      child: Row(
        children: [
          IconButton(
            icon: Icon(Icons.arrow_back_ios_new, size: 16.sp, color: AppColors.navBlue),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          Expanded(
            child: Text(
              '赔率返水',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 17.sp,
                fontWeight: FontWeight.w700,
                color: AppColors.navBlue,
              ),
            ),
          ),
          if (GameSeries.isPk10(_gameType))
            InkWell(
              onTap: _loading || _saving
                  ? null
                  : () => setState(() => _syncSameSeries = !_syncSameSeries),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 20.w,
                    height: 20.w,
                    child: Checkbox(
                      value: _syncSameSeries,
                      onChanged: _loading || _saving
                          ? null
                          : (v) => setState(() => _syncSameSeries = v ?? true),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                  Text(
                    '同步同类型',
                    style: TextStyle(fontSize: 12.sp, color: AppColors.textSecondary),
                  ),
                  SizedBox(width: 4.w),
                ],
              ),
            ),
          TextButton(
            onPressed: _loading || _saving ? null : _save,
            child: Text(
              _saving ? '...' : '保存',
              style: TextStyle(fontSize: 15.sp, color: AgentChrome.ink, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoCard() {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 14.h),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12.r),
      ),
      child: Text(
        '${widget.title} 赔率返水',
        style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w700, color: AgentChrome.ink),
      ),
    );
  }

  Widget _unifyCard() {
    return Container(
      padding: EdgeInsets.fromLTRB(14.w, 12.h, 14.w, 14.h),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12.r),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('统一修改', style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w700, color: AgentChrome.ink)),
          SizedBox(height: 10.h),
          Row(
            children: [
              _stepBtn('−', () => _adjustAll(-1)),
              SizedBox(width: 10.w),
              Expanded(
                child: _inputBox(
                  controller: _stepCtrl,
                  textAlign: TextAlign.center,
                  decimal: true,
                ),
              ),
              SizedBox(width: 10.w),
              _stepBtn('+', () => _adjustAll(1)),
            ],
          ),
          SizedBox(height: 12.h),
          Text('最低限额', style: TextStyle(fontSize: 13.sp, color: AppColors.textSecondary)),
          SizedBox(height: 6.h),
          _inputBox(controller: _minLimitCtrl),
        ],
      ),
    );
  }

  Widget _stepBtn(String label, VoidCallback onTap) {
    return Material(
      color: const Color(0xFFF0F3F7),
      borderRadius: BorderRadius.circular(10.r),
      child: InkWell(
        onTap: _saving ? null : onTap,
        borderRadius: BorderRadius.circular(10.r),
        child: SizedBox(
          width: 44.w,
          height: 44.w,
          child: Center(
            child: Text(label, style: TextStyle(fontSize: 22.sp, color: AgentChrome.ink, fontWeight: FontWeight.w500)),
          ),
        ),
      ),
    );
  }

  Widget _gamePills() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var i = 0; i < _games.length; i++) ...[
            if (i > 0) SizedBox(width: 8.w),
            Material(
              color: _gameIndex == i ? _tabActive : Colors.white,
              borderRadius: BorderRadius.circular(20.r),
              child: InkWell(
                onTap: _saving ? null : () => _onGameChanged(i),
                borderRadius: BorderRadius.circular(20.r),
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
                  child: Text(
                    _games[i].name,
                    style: TextStyle(
                      fontSize: 13.sp,
                      fontWeight: FontWeight.w600,
                      color: _gameIndex == i ? Colors.white : _tabIdle,
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

  Widget _playCard(_OddsRow row) {
    return Container(
      padding: EdgeInsets.fromLTRB(14.w, 12.h, 14.w, 14.h),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12.r),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(row.name, style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w700, color: AgentChrome.ink)),
          SizedBox(height: 10.h),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('赔率返水', style: TextStyle(fontSize: 11.sp, color: AppColors.textSecondary)),
                    SizedBox(height: 6.h),
                    _inputBox(
                      controller: row.oddsCtrl,
                      decimal: true,
                      onChanged: (_) => setState(() {}),
                    ),
                  ],
                ),
              ),
              SizedBox(width: 8.w),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(top: 18.h),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        row.rebateLabel(),
                        style: TextStyle(fontSize: 11.sp, color: AppColors.textSecondary),
                      ),
                      SizedBox(height: 4.h),
                      Text(
                        row.rangeText.trim().isEmpty ? '' : '限制调节${row.rangeText.trim()}',
                        style: TextStyle(fontSize: 11.sp, color: AppColors.textHint),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 10.h),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('单注限额', style: TextStyle(fontSize: 11.sp, color: AppColors.textSecondary)),
                    SizedBox(height: 6.h),
                    _inputBox(controller: row.maxBetCtrl),
                  ],
                ),
              ),
              SizedBox(width: 8.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('单期总限额', style: TextStyle(fontSize: 11.sp, color: AppColors.textSecondary)),
                    SizedBox(height: 6.h),
                    _inputBox(controller: row.periodLimitCtrl),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _inputBox({
    required TextEditingController controller,
    bool decimal = false,
    TextAlign textAlign = TextAlign.start,
    ValueChanged<String>? onChanged,
  }) {
    return EmulatorSafeTextField(
      controller: controller,
      enabled: !_saving,
      keyboardType: decimal
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.number,
      textAlign: textAlign,
      onChanged: onChanged,
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
      ],
      decoration: InputDecoration(
        isDense: true,
        contentPadding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 10.h),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8.r),
          borderSide: const BorderSide(color: Color(0xFFD8DEE6)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8.r),
          borderSide: const BorderSide(color: Color(0xFFD8DEE6)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8.r),
          borderSide: const BorderSide(color: AppColors.navBlue, width: 1.2),
        ),
      ),
    );
  }
}
