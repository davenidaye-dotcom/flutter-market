import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import '../../../config/theme/app_colors.dart';
import '../../../core/network/session_store.dart';
import '../../../core/utils/submit_guard.dart';
import '../../../data/models/lottery_game_model.dart';
import '../../../data/repositories/providers.dart';
import '../../../shared/widgets/emulator_safe_text_field.dart';
import '../../../shared/widgets/lottery_ball.dart';
import '../../../shared/widgets/page_app_bar.dart';
import '../../auth/providers/auth_session_provider.dart';
import '../providers/lottery_live_provider.dart';
import '../widgets/bet_confirm_dialog.dart';
import '../widgets/live_period_widgets.dart';
import '../utils/draw_history_rows.dart';
import '../utils/lottery_period_ui.dart';
import '../utils/bet_play_codec.dart';
import '../utils/bet_repeat_helper.dart';

/// 盘口下注详情 — 快捷 / 两面 / 1-10名 / 冠亚和
/// [embedded] 为 true 时作为聊天页遮罩层，不含独立 Scaffold/顶栏
class MarketBetPage extends ConsumerStatefulWidget {
  const MarketBetPage({
    super.key,
    required this.roomId,
    required this.gameId,
    this.embedded = false,
    this.onBetSuccess,
  });

  final String roomId;
  final String gameId;
  final bool embedded;
  final void Function(String command, List<String> orderIds)? onBetSuccess;

  @override
  ConsumerState<MarketBetPage> createState() => _MarketBetPageState();
}

class _MarketBetPageState extends ConsumerState<MarketBetPage> {
  final _betGuard = SubmitGuard();

  @override
  void initState() {
    super.initState();
    if (!widget.embedded) {
      Future.microtask(() async {
        final live = ref.read(roomLotteryLiveProvider(widget.roomId).notifier);
        await live.ensureLoaded();
        await live.refreshWallet();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final canBet = ref.watch(authSessionProvider.select((s) => s.canPlaceBet));
    final body = Column(
      children: [
        if (!widget.embedded)
          _MarketStatusSection(roomId: widget.roomId, gameId: widget.gameId),
        Expanded(
          child: _MarketBetBody(
            roomId: widget.roomId,
            gameId: widget.gameId,
            canBet: canBet,
            betGuard: _betGuard,
            onBetSuccess: widget.onBetSuccess,
          ),
        ),
      ],
    );

    if (widget.embedded) {
      return Material(color: const Color(0xFFF5F5F5), child: body);
    }
    return AppPageScaffold(backgroundColor: const Color(0xFFF5F5F5), body: body);
  }
}

/// Isolated from 1s countdown — odds taps only rebuild this subtree.
class _MarketBetBody extends ConsumerStatefulWidget {
  const _MarketBetBody({
    required this.roomId,
    required this.gameId,
    required this.canBet,
    required this.betGuard,
    this.onBetSuccess,
  });

  final String roomId;
  final String gameId;
  final bool canBet;
  final SubmitGuard betGuard;
  final void Function(String command, List<String> orderIds)? onBetSuccess;

  @override
  ConsumerState<_MarketBetBody> createState() => _MarketBetBodyState();
}

class _MarketBetBodyState extends ConsumerState<_MarketBetBody> {
  int _tab = 0;
  final Set<int> _quickRanks = {0};
  int _amountPreset = 0;
  final _amountPresetNotifier = ValueNotifier(0);
  final _amountCtrl = TextEditingController();
  final _selectedNotifier = ValueNotifier<Set<String>>(<String>{});
  final _layoutNotifier = ValueNotifier<int>(0);
  final Set<String> _collapsed = {};
  final ValueNotifier<bool> _submitting = ValueNotifier(false);
  bool _submitLocked = false;
  DateTime? _lastToggleAt;

  static const _tabs = ['快捷', '两面', '1-10名', '冠亚和'];
  static const _ranks = ['冠军', '亚军', '三名', '四名', '五名', '六名', '七名', '八名', '九名', '十名'];
  static const _presets = [5, 10, 50, 100, 500];
  static const _twoSides = ['大', '小', '单', '双', '龙', '虎'];
  static const _sumOdds = {
    3: '42',
    4: '42',
    5: '21',
    6: '21',
    7: '12',
    8: '12',
    9: '8.5',
    10: '8.5',
    11: '8.5',
    12: '8.5',
    13: '12',
    14: '12',
    15: '21',
    16: '21',
    17: '42',
    18: '42',
  };
  static const _twoSideRanks = ['冠亚和', ..._ranks];

  @override
  void initState() {
    super.initState();
    _amountCtrl.text = '${_presets[_amountPreset]}';
    for (final rank in _twoSideRanks) {
      _collapsed.add('两面-$rank');
    }
    for (final rank in _ranks) {
      _collapsed.add('名次-$rank');
    }
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _selectedNotifier.dispose();
    _layoutNotifier.dispose();
    _amountPresetNotifier.dispose();
    _submitting.dispose();
    super.dispose();
  }

  double get _unit => double.tryParse(_amountCtrl.text.trim()) ?? 0;

  /// 指令金额：后端要求正整数，禁止 double 插值出 `5.0`
  String? get _unitToken {
    final raw = _amountCtrl.text.trim();
    if (!RegExp(r'^[1-9]\d*$').hasMatch(raw)) return null;
    return raw;
  }

  String _intAmountText(num n) {
    if (n == n.roundToDouble()) return '${n.round()}';
    return n.toString();
  }

  void _toggle(String key) {
    if (!widget.canBet || _submitting.value) return;
    final now = DateTime.now();
    final last = _lastToggleAt;
    if (last != null && now.difference(last).inMilliseconds < 50) return;
    _lastToggleAt = now;
    final next = Set<String>.from(_selectedNotifier.value);
    if (next.contains(key)) {
      next.remove(key);
    } else {
      next.add(key);
    }
    _selectedNotifier.value = next;
  }

  void _rememberBet(String command) {
    final accountId = ref.read(authSessionProvider).user?.id ?? '';
    unawaited(
      BetRepeatStore.save(
        roomId: widget.roomId,
        gameId: widget.gameId,
        accountId: accountId,
        command: command,
      ),
    );
  }

  /// 按上一笔成功注单再下。开了下注确认则先展示指令。
  Future<void> _repeatLast() async {
    if (!widget.canBet) return;
    if (_submitLocked || widget.betGuard.isBusy || _submitting.value) return;
    final accountId = ref.read(authSessionProvider).user?.id ?? '';
    final command = await BetRepeatStore.read(
      roomId: widget.roomId,
      gameId: widget.gameId,
      accountId: accountId,
    );
    if (!mounted) return;
    if (command == null || command.trim().isEmpty) {
      AppToast.info('暂无可重投注单');
      return;
    }
    final text = command.trim();
    final live = ref.read(roomLotteryLiveProvider(widget.roomId));
    final needConfirm = live.betConfirm || SessionStore.instance.betConfirm;
    if (needConfirm) {
      final game = ref
          .read(roomLotteryLiveProvider(widget.roomId).notifier)
          .displayGameFor(widget.gameId);
      final ok = await showBetConfirmDialog(
        context: context,
        command: text,
        issueNo: game?.currentIssue,
        amountText: _amountOfStored(text),
      );
      if (!ok || !mounted) return;
    }
    final items = _itemsFromStored(text);
    _submitLocked = true;
    _submitting.value = true;
    try {
      final done = await widget.betGuard.run((requestId) async {
        return ref.read(lotteryRepositoryProvider).submitBet(
              roomId: widget.roomId,
              gameId: widget.gameId,
              command: text,
              items: items,
              requestId: requestId,
            );
      });
      if (done == null || !mounted) return;
      unawaited(
        ref.read(roomLotteryLiveProvider(widget.roomId).notifier).refreshWallet(),
      );
      if (!mounted) return;
      widget.onBetSuccess?.call(text, done);
      AppToast.success('重投成功');
    } catch (e) {
      AppToast.error(e.toString());
    } finally {
      _submitLocked = false;
      if (mounted) _submitting.value = false;
    }
  }

  /// `冠军/1/5 亚军/3/10` → 机器 items；聊天指令解析不了则只发 command。
  List<Map<String, dynamic>>? _itemsFromStored(String command) {
    final tokens = command.split(RegExp(r'\s+')).where((e) => e.isNotEmpty);
    final items = <Map<String, dynamic>>[];
    for (final token in tokens) {
      final parts = token.split('/');
      if (parts.length < 3) return null;
      final amount = num.tryParse(parts.last);
      if (amount == null || amount <= 0) return null;
      final uiKey = parts.sublist(0, parts.length - 1).join('/');
      final code = uiKeyToPlayCode(uiKey);
      if (code == null) return null;
      items.add({'playCode': code, 'amount': amount});
    }
    return items.isEmpty ? null : items;
  }

  String? _amountOfStored(String command) {
    var sum = 0.0;
    var any = false;
    for (final token in command.split(RegExp(r'\s+'))) {
      final parts = token.split('/');
      if (parts.isEmpty) continue;
      final n = double.tryParse(parts.last);
      if (n == null) continue;
      sum += n;
      any = true;
    }
    if (!any) return null;
    return sum.toStringAsFixed(sum == sum.roundToDouble() ? 0 : 1);
  }

  void _reset() {
    _selectedNotifier.value = <String>{};
    _amountPreset = 0;
    _amountCtrl.text = '${_presets[0]}';
  }

  void _bumpLayout() => _layoutNotifier.value++;

  void _setTab(int i) {
    if (_tab == i) return;
    setState(() {
      _tab = i;
      _selectedNotifier.value = <String>{};
    });
    _bumpLayout();
  }

  void _toggleQuickRank(int i) {
    if (_quickRanks.contains(i)) {
      if (_quickRanks.length == 1) return;
      _quickRanks.remove(i);
    } else {
      _quickRanks.add(i);
    }
    _bumpLayout();
  }

  /// 当前勾选的名次一起加减这个号码。已全选则取消，否则补上。
  void _toggleQuickNumber(int number) {
    if (!widget.canBet || _submitting.value || _quickRanks.isEmpty) return;
    final ranks = [for (final i in _quickRanks) _ranks[i]];
    final next = Set<String>.from(_selectedNotifier.value);
    final allOn = ranks.every((rank) => next.contains('$rank/$number'));
    for (final rank in ranks) {
      final key = '$rank/$number';
      if (allOn) {
        next.remove(key);
      } else {
        next.add(key);
      }
    }
    _selectedNotifier.value = next;
  }

  bool _quickNumberOn(Set<String> selected, int number) {
    if (_quickRanks.isEmpty) return false;
    return _quickRanks.every(
      (i) => selected.contains('${_ranks[i]}/$number'),
    );
  }

  void _toggleCollapse(String key) {
    if (_collapsed.contains(key)) {
      _collapsed.remove(key);
    } else {
      _collapsed.add(key);
    }
    _bumpLayout();
  }

  Future<void> _submit() async {
    if (!widget.canBet) return;
    final selected = _selectedNotifier.value;
    if (selected.isEmpty) {
      AppToast.info('请选择玩法');
      return;
    }
    final unitToken = _unitToken;
    if (unitToken == null) {
      AppToast.info('下注金额必须是正整数');
      return;
    }
    final unit = int.parse(unitToken);
    if (_submitLocked || widget.betGuard.isBusy || _submitting.value) return;
    final command = selected.map((e) => '$e/$unitToken').join(' ');
    final live = ref.read(roomLotteryLiveProvider(widget.roomId));
    final needConfirm = live.betConfirm || SessionStore.instance.betConfirm;
    if (needConfirm) {
      final game = ref
          .read(roomLotteryLiveProvider(widget.roomId).notifier)
          .displayGameFor(widget.gameId);
      final ok = await showBetConfirmDialog(
        context: context,
        command: command,
        issueNo: game?.currentIssue,
        amountText: _intAmountText(selected.length * unit),
      );
      if (!ok || !mounted) return;
    }
    _submitLocked = true;
    _submitting.value = true;
    try {
      final machineItems = <Map<String, dynamic>>[];
      for (final key in selected) {
        final code = uiKeyToPlayCode(key);
        if (code == null) {
          AppToast.error('玩法无法识别: $key');
          return;
        }
        machineItems.add({'playCode': code, 'amount': unit});
      }
      final done = await widget.betGuard.run((requestId) async {
        return ref.read(lotteryRepositoryProvider).submitBet(
              roomId: widget.roomId,
              gameId: widget.gameId,
              // 带可读 command，后端才能广播给同房其他人
              command: command,
              items: machineItems,
              requestId: requestId,
            );
      });
      if (done == null || !mounted) return;
      unawaited(
        ref.read(roomLotteryLiveProvider(widget.roomId).notifier).refreshWallet(),
      );
      if (!mounted) return;
      widget.onBetSuccess?.call(command, done);
      _rememberBet(command);
      AppToast.success('下注成功');
      _reset();
    } catch (e) {
      AppToast.error(e.toString());
    } finally {
      _submitLocked = false;
      if (mounted) _submitting.value = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _SideTabs(
                tabs: _tabs,
                current: _tab,
                onTap: _setTab,
              ),
              Expanded(
                child: ValueListenableBuilder<int>(
                  valueListenable: _layoutNotifier,
                  builder: (_, __, ___) {
                    return ValueListenableBuilder<Set<String>>(
                      valueListenable: _selectedNotifier,
                      builder: (_, selected, __) => _buildBody(selected),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        ValueListenableBuilder<Set<String>>(
          valueListenable: _selectedNotifier,
          builder: (_, selected, __) {
            final unit = _unit;
            return ValueListenableBuilder<int>(
              valueListenable: _amountPresetNotifier,
              builder: (_, presetIndex, __) {
                return _BottomBar(
              presets: _presets,
              presetIndex: presetIndex,
              amountCtrl: _amountCtrl,
              total: unit * selected.length,
              count: selected.length,
              submittingListenable: _submitting,
              enabled: widget.canBet,
              onPreset: (i) {
                if (!widget.canBet || _submitting.value || widget.betGuard.isBusy) return;
                _amountPreset = i;
                _amountPresetNotifier.value = i;
                _amountCtrl.text = '${_presets[i]}';
                _amountCtrl.selection = TextSelection.collapsed(offset: _amountCtrl.text.length);
              },
              onAmountChanged: (text) {
                final n = int.tryParse(text.trim());
                final idx = n == null ? -1 : _presets.indexOf(n);
                if (_amountPreset == idx) return;
                _amountPreset = idx;
                _amountPresetNotifier.value = idx;
              },
              onBet: _submit,
              onRepeat: _repeatLast,
              onReset: () {
                if (_submitting.value || widget.betGuard.isBusy) return;
                _reset();
              },
            );
              },
            );
          },
        ),
      ],
    );
  }

  Widget _buildBody(Set<String> selected) {
    return switch (_tab) {
      0 => _buildQuick(selected),
      1 => _buildTwoSides(selected),
      2 => _buildRankNumbers(selected),
      _ => _buildSum(selected),
    };
  }

  Widget _buildQuick(Set<String> selected) {
    return ListView.builder(
      padding: EdgeInsets.all(8.w),
      itemCount: 6,
      itemBuilder: (_, index) {
        if (index == 0) {
          return Wrap(
            spacing: 6.w,
            runSpacing: 6.h,
            children: [
              for (var i = 0; i < _ranks.length; i++)
                _RankChip(
                  label: _ranks[i],
                  active: _quickRanks.contains(i),
                  onTap: () => _toggleQuickRank(i),
                ),
            ],
          );
        }
        final pairIndex = index - 1;
        final a = pairIndex * 2 + 1;
        final b = pairIndex * 2 + 2;
        return Padding(
          padding: EdgeInsets.only(top: index == 1 ? 10.h : 0, bottom: 6.h),
          child: Row(
            children: [
              Expanded(
                child: _BallOddsCell(
                  number: a,
                  odds: '9.995',
                  selected: _quickNumberOn(selected, a),
                  onTap: () => _toggleQuickNumber(a),
                ),
              ),
              SizedBox(width: 6.w),
              Expanded(
                child: _BallOddsCell(
                  number: b,
                  odds: '9.995',
                  selected: _quickNumberOn(selected, b),
                  onTap: () => _toggleQuickNumber(b),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTwoSides(Set<String> selected) {
    return ListView.builder(
      padding: EdgeInsets.all(8.w),
      itemCount: _twoSideRanks.length,
      itemBuilder: (_, index) {
        final rank = _twoSideRanks[index];
        final collapseKey = '两面-$rank';
        final collapsed = _collapsed.contains(collapseKey);
        final sides = rank == '冠亚和' ? const ['大', '小', '单', '双'] : _twoSides;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _SectionHeader(
              title: rank,
              collapsed: collapsed,
              onTap: () => _toggleCollapse(collapseKey),
            ),
            if (!collapsed)
              Padding(
                padding: EdgeInsets.only(bottom: 8.h),
                child: Wrap(
                  spacing: 6.w,
                  runSpacing: 6.h,
                  children: [
                    for (final side in sides)
                      _OddsCell(
                        label: side,
                        odds: '1.998',
                        selected: selected.contains('$rank/$side'),
                        onTap: () => _toggle('$rank/$side'),
                      ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildRankNumbers(Set<String> selected) {
    return ListView.builder(
      padding: EdgeInsets.all(8.w),
      itemCount: _ranks.length,
      itemBuilder: (_, index) {
        final rank = _ranks[index];
        final collapseKey = '名次-$rank';
        final collapsed = _collapsed.contains(collapseKey);
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SectionHeader(
              title: rank,
              collapsed: collapsed,
              onTap: () => _toggleCollapse(collapseKey),
            ),
            if (!collapsed) ..._numberPairs(rank, selected),
          ],
        );
      },
    );
  }

  List<Widget> _numberPairs(String rank, Set<String> selected) {
    final widgets = <Widget>[];
    for (var i = 0; i < 10; i += 2) {
      final a = i + 1;
      final b = i + 2;
      widgets.add(
        Padding(
          padding: EdgeInsets.only(bottom: 6.h),
          child: Row(
            children: [
              Expanded(
                child: _BallOddsCell(
                  number: a,
                  odds: '9.995',
                  selected: selected.contains('$rank/$a'),
                  onTap: () => _toggle('$rank/$a'),
                ),
              ),
              SizedBox(width: 6.w),
              Expanded(
                child: _BallOddsCell(
                  number: b,
                  odds: '9.995',
                  selected: selected.contains('$rank/$b'),
                  onTap: () => _toggle('$rank/$b'),
                ),
              ),
            ],
          ),
        ),
      );
    }
    return widgets;
  }

  Widget _buildSum(Set<String> selected) {
    final keys = _sumOdds.keys.toList()..sort();
    return GridView.builder(
      padding: EdgeInsets.all(8.w),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 6.h,
        crossAxisSpacing: 6.w,
        childAspectRatio: 2.8,
      ),
      itemCount: keys.length,
      itemBuilder: (_, i) {
        final n = keys[i];
        final key = '冠亚和/$n';
        return _OddsCell(
          label: '$n',
          odds: _sumOdds[n]!,
          selected: selected.contains(key),
          onTap: () => _toggle(key),
          expand: true,
        );
      },
    );
  }
}

class _MarketStatusSection extends ConsumerWidget {
  const _MarketStatusSection({required this.roomId, required this.gameId});

  final String roomId;
  final String gameId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(
      roomLotteryLiveProvider(roomId).select(
        (s) {
          final g = s.gameById(gameId);
          if (g == null) return null;
          return (
            g.name,
            g.currentIssue,
            g.previousIssue,
            g.isDrawing,
            g.status,
            g.previousResults,
          );
        },
      ),
    );
    if (snapshot == null) return const SizedBox.shrink();
    final game = LotteryGameModel(
      id: gameId,
      name: snapshot.$1,
      currentIssue: snapshot.$2,
      previousIssue: snapshot.$3,
      countdownSeconds: 0,
      isDrawing: snapshot.$4,
      status: snapshot.$5,
      previousResults: snapshot.$6,
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _Header(gameName: game.name),
        _StatusBar(roomId: roomId, gameId: gameId, game: game),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.gameName});

  final String gameName;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFA5D6F7), Color(0xFFE8F4FC)],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(4.w, 0, 12.w, 6.h),
          child: Row(
            children: [
              IconButton(
                icon: Icon(Icons.arrow_back_ios, size: 18.sp, color: AppColors.textPrimary),
                onPressed: () {
                  if (context.canPop()) context.pop();
                },
              ),
              Text(
                gameName,
                style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
              ),
              const Spacer(),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('积分:10658', style: TextStyle(fontSize: 11.sp, color: AppColors.textPrimary)),
                  Text('输赢:0', style: TextStyle(fontSize: 11.sp, color: AppColors.textPrimary)),
                ],
              ),
              SizedBox(width: 10.w),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('流水:0', style: TextStyle(fontSize: 11.sp, color: AppColors.textPrimary)),
                  Text('回水:0', style: TextStyle(fontSize: 11.sp, color: AppColors.textPrimary)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusBar extends StatelessWidget {
  const _StatusBar({
    required this.roomId,
    required this.gameId,
    required this.game,
  });

  final String roomId;
  final String gameId;
  final LotteryGameModel game;

  @override
  Widget build(BuildContext context) {
    final drawing = LotteryPeriodHelper.showDrawingPlaceholders(game);
    return Container(
      color: Colors.white,
      padding: EdgeInsets.fromLTRB(12.w, 8.h, 12.w, 8.h),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: LiveLotteryPeriodCountdownRow(
                  roomId: roomId,
                  gameId: gameId,
                  issuePrefix: compactIssueNo(game.currentIssue),
                  issueStyle: TextStyle(fontSize: 13.sp, color: AppColors.textPrimary),
                  labelStyle: TextStyle(fontSize: 13.sp, color: AppColors.textPrimary),
                ),
              ),
              _miniBtn('注单'),
              SizedBox(width: 6.w),
              _miniBtn('长龙'),
            ],
          ),
          SizedBox(height: 8.h),
          Row(
            children: [
              Text(
                game.previousIssue ?? game.currentIssue,
                style: TextStyle(fontSize: 12.sp, color: AppColors.textSecondary),
              ),
              SizedBox(width: 6.w),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      if (drawing)
                        for (var i = 0; i < 10; i++) ...[
                          if (i > 0) SizedBox(width: 3.w),
                          LotteryBall(number: 0, size: 20.w, placeholder: true),
                        ]
                      else
                        for (var i = 0; i < game.previousResults.length; i++) ...[
                          if (i > 0) SizedBox(width: 3.w),
                          LotteryBall(number: game.previousResults[i], size: 20.w),
                        ],
                    ],
                  ),
                ),
              ),
              Text('冠亚和', style: TextStyle(fontSize: 11.sp, color: const Color(0xFF7A7A7A))),
              Icon(Icons.arrow_drop_down, size: 18.sp, color: AppColors.navBlue),
            ],
          ),
        ],
      ),
    );
  }

  Widget _miniBtn(String text) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
      decoration: BoxDecoration(
        color: AppColors.navBlue.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(12.r),
      ),
      child: Text(text, style: TextStyle(fontSize: 11.sp, color: AppColors.navBlue)),
    );
  }
}

class _SideTabs extends StatelessWidget {
  const _SideTabs({required this.tabs, required this.current, required this.onTap});

  final List<String> tabs;
  final int current;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 72.w,
      color: AppColors.sidebarInactive,
      child: Column(
        children: [
          for (var i = 0; i < tabs.length; i++)
            GestureDetector(
              onTap: () => onTap(i),
              child: Container(
                width: double.infinity,
                padding: EdgeInsets.symmetric(vertical: 16.h),
                color: current == i ? AppColors.sidebarActive : AppColors.sidebarInactive,
                alignment: Alignment.center,
                child: Text(
                  tabs[i],
                  style: TextStyle(
                    fontSize: 13.sp,
                    color: current == i ? Colors.white : AppColors.textPrimary,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _RankChip extends StatelessWidget {
  const _RankChip({required this.label, required this.active, required this.onTap});

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: (MediaQuery.sizeOf(context).width - 72.w - 16.w - 18.w) / 4,
        height: 36.h,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? const Color(0xFFE3F2FD) : Colors.white,
          borderRadius: BorderRadius.circular(4.r),
          border: Border.all(color: active ? AppColors.navBlue : const Color(0xFFE0E0E0)),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13.sp,
            color: active ? AppColors.navBlue : AppColors.textPrimary,
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.collapsed, required this.onTap});

  final String title;
  final bool collapsed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 36.h,
        margin: EdgeInsets.only(bottom: 6.h),
        padding: EdgeInsets.symmetric(horizontal: 10.w),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(4.r),
          border: Border.all(color: const Color(0xFFE0E0E0)),
        ),
        child: Row(
          children: [
            Text(title, style: TextStyle(fontSize: 14.sp, color: AppColors.textPrimary)),
            const Spacer(),
            Icon(
              collapsed ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_up,
              size: 18.sp,
              color: AppColors.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}

class _OddsCell extends StatelessWidget {
  const _OddsCell({
    required this.label,
    required this.odds,
    required this.selected,
    required this.onTap,
    this.expand = false,
  });

  final String label;
  final String odds;
  final bool selected;
  final VoidCallback onTap;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: expand ? null : (MediaQuery.sizeOf(context).width - 72.w - 16.w - 6.w) / 2,
        height: 44.h,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFE3F2FD) : Colors.white,
          borderRadius: BorderRadius.circular(4.r),
          border: Border.all(color: selected ? AppColors.navBlue : const Color(0xFFE0E0E0)),
        ),
        child: RichText(
          text: TextSpan(
            children: [
              TextSpan(
                text: label,
                style: TextStyle(fontSize: 15.sp, color: AppColors.textPrimary, fontWeight: FontWeight.w500),
              ),
              TextSpan(
                text: '  $odds',
                style: TextStyle(fontSize: 12.sp, color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BallOddsCell extends StatelessWidget {
  const _BallOddsCell({
    required this.number,
    required this.odds,
    required this.selected,
    required this.onTap,
  });

  final int number;
  final String odds;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 44.h,
        padding: EdgeInsets.symmetric(horizontal: 10.w),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFE3F2FD) : Colors.white,
          borderRadius: BorderRadius.circular(4.r),
          border: Border.all(color: selected ? AppColors.navBlue : const Color(0xFFE0E0E0)),
        ),
        child: Row(
          children: [
            LotteryBall(number: number, size: 26.w),
            SizedBox(width: 10.w),
            Text(odds, style: TextStyle(fontSize: 13.sp, color: AppColors.textSecondary)),
          ],
        ),
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.presets,
    required this.presetIndex,
    required this.amountCtrl,
    required this.total,
    required this.count,
    required this.onPreset,
    required this.onAmountChanged,
    required this.onBet,
    required this.onRepeat,
    required this.onReset,
    required this.submittingListenable,
    this.enabled = true,
  });

  final List<int> presets;
  final int presetIndex;
  final TextEditingController amountCtrl;
  final double total;
  final int count;
  final ValueChanged<int> onPreset;
  final ValueChanged<String> onAmountChanged;
  final VoidCallback onBet;
  final VoidCallback onRepeat;
  final VoidCallback onReset;
  final ValueListenable<bool> submittingListenable;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: submittingListenable,
      builder: (context, submitting, _) {
        final canInteract = enabled && !submitting;
        final presetColor = canInteract ? AppColors.navBlue : AppColors.textHint;
        final presetActiveColor = canInteract ? AppColors.primaryDark : AppColors.textHint;
        return Container(
          color: canInteract ? Colors.white : const Color(0xFFEEEEEE),
          padding: EdgeInsets.fromLTRB(12.w, 8.h, 12.w, 8.h),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    for (var i = 0; i < presets.length; i++) ...[
                      if (i > 0) SizedBox(width: 6.w),
                      Expanded(
                        child: GestureDetector(
                          onTap: canInteract ? () => onPreset(i) : null,
                          child: Container(
                            height: 32.h,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: presetIndex == i ? presetActiveColor : presetColor,
                              borderRadius: BorderRadius.circular(4.r),
                            ),
                            child: Text(
                              '${presets[i]}',
                              style: TextStyle(fontSize: 14.sp, color: Colors.white, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                SizedBox(height: 8.h),
                ValueListenableBuilder<TextEditingValue>(
                  valueListenable: amountCtrl,
                  builder: (_, value, _) {
                    final unit = int.tryParse(value.text.trim()) ??
                        (double.tryParse(value.text.trim())?.round() ?? 0);
                    final liveTotal = unit * count;
                    return Row(
                      children: [
                        Text(
                          '下注总额: $liveTotal',
                          style: TextStyle(fontSize: 12.sp, color: AppColors.textSecondary),
                        ),
                        const Spacer(),
                        Text(
                          '共$count注单',
                          style: TextStyle(fontSize: 12.sp, color: AppColors.textSecondary),
                        ),
                      ],
                    );
                  },
                ),
                SizedBox(height: 8.h),
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 40.h,
                        child: EmulatorSafeTextField(
                          controller: amountCtrl,
                          enabled: canInteract,
                          keyboardType: TextInputType.number,
                          textInputAction: TextInputAction.done,
                          onChanged: onAmountChanged,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          style: TextStyle(fontSize: 14.sp, color: canInteract ? AppColors.textPrimary : AppColors.textHint),
                          decoration: InputDecoration(
                            hintText: enabled ? '请输入下注金额' : '房主不可下注',
                            hintStyle: TextStyle(fontSize: 13.sp, color: AppColors.textHint),
                            filled: true,
                            fillColor: canInteract ? const Color(0xFFF5F5F5) : const Color(0xFFDDDDDD),
                            contentPadding: EdgeInsets.symmetric(horizontal: 12.w),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(4.r),
                              borderSide: const BorderSide(color: Color(0xFFDDDDDD)),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(4.r),
                              borderSide: const BorderSide(color: Color(0xFFDDDDDD)),
                            ),
                            disabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(4.r),
                              borderSide: const BorderSide(color: Color(0xFFCCCCCC)),
                            ),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(width: 8.w),
                    GestureDetector(
                      onTap: canInteract ? onBet : null,
                      child: Container(
                        height: 40.h,
                        padding: EdgeInsets.symmetric(horizontal: 18.w),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: canInteract ? AppColors.navBlue : AppColors.textHint,
                          borderRadius: BorderRadius.circular(4.r),
                        ),
                        child: submitting
                            ? SizedBox(
                                width: 18.w,
                                height: 18.w,
                                child: const CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Text('下注', style: TextStyle(fontSize: 15.sp, color: Colors.white)),
                      ),
                    ),
                    SizedBox(width: 8.w),
                    GestureDetector(
                      onTap: canInteract ? onRepeat : null,
                      child: Container(
                        height: 40.h,
                        padding: EdgeInsets.symmetric(horizontal: 12.w),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: canInteract ? const Color(0xFF43A047) : AppColors.textHint,
                          borderRadius: BorderRadius.circular(4.r),
                        ),
                        child: Text('重投', style: TextStyle(fontSize: 15.sp, color: Colors.white)),
                      ),
                    ),
                    SizedBox(width: 8.w),
                    GestureDetector(
                      onTap: canInteract ? onReset : null,
                      child: Container(
                        height: 40.h,
                        padding: EdgeInsets.symmetric(horizontal: 18.w),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: canInteract ? AppColors.danger : AppColors.textHint.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(4.r),
                        ),
                        child: Text('重置', style: TextStyle(fontSize: 15.sp, color: Colors.white)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
