import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import '../../../config/router/route_paths.dart';
import '../../../config/theme/app_colors.dart';
import '../../../core/network/session_store.dart';
import '../../../core/utils/submit_guard.dart';
import '../../../data/models/chat_message_model.dart';
import '../../../data/models/lottery_game_model.dart';
import '../../../data/repositories/providers.dart';
import '../../../shared/widgets/emulator_safe_text_field.dart';
import '../../../shared/widgets/input_dialog.dart';
import '../../../shared/widgets/page_app_bar.dart';
import '../../auth/providers/auth_session_provider.dart';
import '../utils/bet_receipt_format.dart';
import '../../host/pages/host_shell_page.dart';
import '../../room/pages/room_shell_page.dart';
import '../../room/pages/customer_service_page.dart';
import '../../wallet/pages/apply_records_page.dart';
import '../../wallet/pages/bet_records_page.dart';
import '../../wallet/pages/points_change_page.dart';
import '../../wallet/pages/welfare_report_page.dart';
import '../services/chat_push_cache.dart';
import '../providers/lottery_live_provider.dart';
import '../utils/chat_timeline.dart';
import '../utils/draw_history_rows.dart';
import '../utils/lottery_period_ui.dart';
import '../utils/bet_play_codec.dart';
import '../utils/bet_repeat_helper.dart';
import '../widgets/bet_action_menu_panel.dart';
import '../widgets/bet_confirm_dialog.dart';
import '../widgets/bet_input_bar.dart';
import '../widgets/bet_keypad_panel.dart';
import '../widgets/bet_slip_panel.dart';
import '../widgets/chat_message_item.dart';
import '../widgets/history_draw_panel.dart';
import '../widgets/live_period_widgets.dart';
import '../widgets/long_dragon_panel.dart';
import '../widgets/switch_game_dialog.dart';
import 'market_bet_page.dart';
import '../../../shared/widgets/app_page_loading.dart';

enum _BottomPanel { none, keypad, menu, quickBet }
enum _TopPanel { none, betSlip, longDragon }

/// 大厅 Overlay Offstage 可见性，供 ChatBetPage 在隐藏时收起盘口。
class ChatOverlayVisibility extends InheritedWidget {
  const ChatOverlayVisibility({
    super.key,
    required this.visible,
    required super.child,
  });

  final bool visible;

  static ChatOverlayVisibility? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<ChatOverlayVisibility>();
  }

  @override
  bool updateShouldNotify(ChatOverlayVisibility oldWidget) =>
      visible != oldWidget.visible;
}

class ChatBetPage extends ConsumerStatefulWidget {
  const ChatBetPage({
    super.key,
    required this.roomId,
    required this.gameId,
    this.onClose,
    this.onSwitchGame,
  });

  final String roomId;
  final String gameId;

  /// 非空时表示由大厅 Overlay 打开：关闭只卸 Overlay，不动路由/大厅。
  final VoidCallback? onClose;

  /// 大厅 Overlay 模式：切换彩种由大厅换页保活，不在本页改 gameId。
  final ValueChanged<String>? onSwitchGame;

  @override
  ConsumerState<ChatBetPage> createState() => _ChatBetPageState();
}

class _ChatBetPageState extends ConsumerState<ChatBetPage> {
  final _messagesNotifier = ValueNotifier<List<ChatMessageModel>>([]);
  final _betSlipsNotifier = ValueNotifier<List<BetSlipRow>>([]);
  final _betCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  late String _gameId;
  final _gameIdNotifier = ValueNotifier<String>('');
  final _messagesLoadingNotifier = ValueNotifier(false);
  _BottomPanel _panel = _BottomPanel.none;
  bool _overlayWasVisible = true;
  final _panelNotifier = ValueNotifier<_BottomPanel>(_BottomPanel.none);
  final _topPanelNotifier = ValueNotifier<_TopPanel>(_TopPanel.none);
  final _historyExpandedNotifier = ValueNotifier(false);
  /// 历史面板首次打开后保活，避免每次展开重建 EasyRefresh 卡顿。
  final _historyPanelMounted = ValueNotifier(false);
  final _historyLoadingNotifier = ValueNotifier(false);
  final _longDragonRowsNotifier = ValueNotifier<List<LongDragonRow>?>(null);
  final _longDragonLoadingNotifier = ValueNotifier(false);
  final _fabSelectedNotifier = ValueNotifier<int?>(null);
  final _marketReadyNotifier = ValueNotifier(false);
  final _dockPaddingNotifier = ValueNotifier(0.0);
  DateTime? _lastPanelToggleAt;
  final _chatHiddenNotifier = ValueNotifier(false);
  final _messageIds = <String>{};
  final _historyDisplayRowsNotifier = ValueNotifier<List<HistoryDrawRow>>(const []);
  final _betGuard = SubmitGuard(debounce: const Duration(milliseconds: 300));
  final _betBusy = ValueNotifier(false);
  final _walletGuard = SubmitGuard();
  bool _walletDialogOpen = false;
  StreamSubscription<LotteryChatPush>? _chatPushSub;

  int _msgLoadGen = 0;
  Future<void>? _msgLoadInflight;
  bool _submitLocked = false;
  int _longDragonLoadGen = 0;
  int _historyReadyGen = 0;
  String? _longDragonLoadedGameId;
  bool _pinnedToBottom = true;
  final _showJumpBottomNotifier = ValueNotifier(false);
  Timer? _draftSaveTimer;
  Timer? _historyRowsDebounce;
  DateTime? _overlayIgnoreDismissUntil;
  bool _disposed = false;
  int _chatSubGen = 0;
  String _accountId = '';
  String? _lastTimelineSig;
  bool _timelineSyncQueued = false;
  bool _bottomJumpWait = false;
  /// reverse 列表下标：stable key → itemBuilder 下标，插入新消息时复用已有格子。
  final _childIndexByKey = <String, int>{};

  void _onScrollChanged() {
    if (!_scrollCtrl.hasClients) return;
    final pinned = _scrollCtrl.offset <= 64;
    _pinnedToBottom = pinned;
    final showJump = !pinned;
    if (_showJumpBottomNotifier.value != showJump) {
      _showJumpBottomNotifier.value = showJump;
    }
  }

  /// 已在底部不跳。手指还在滑或惯性未停时不 jump，避免和滚动抢位置。
  void _scrollToBottom({bool animated = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_disposed || !mounted) return;
      _jumpToBottomIfPinned(animated: animated);
    });
  }

  /// 用户点右下角按钮：强制滚到底并重新钉住底部。
  void _forceScrollToBottom() {
    _pinnedToBottom = true;
    _showJumpBottomNotifier.value = false;
    if (!_scrollCtrl.hasClients) return;
    _scrollCtrl.animateTo(
      0,
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
    );
  }

  void _jumpToBottomIfPinned({bool animated = false}) {
    if (_disposed || !mounted || !_scrollCtrl.hasClients) return;
    if (!_pinnedToBottom) return;
    if (_scrollCtrl.offset <= 1) return;
    if (_scrollCtrl.position.isScrollingNotifier.value) {
      if (_bottomJumpWait) return;
      _bottomJumpWait = true;
      _scrollCtrl.position.isScrollingNotifier.addListener(_onScrollIdleForBottom);
      return;
    }
    if (animated) {
      _scrollCtrl.animateTo(
        0,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    } else {
      _scrollCtrl.jumpTo(0);
    }
  }

  void _onScrollIdleForBottom() {
    if (_disposed || !mounted || !_scrollCtrl.hasClients) {
      _bottomJumpWait = false;
      return;
    }
    if (_scrollCtrl.position.isScrollingNotifier.value) return;
    _scrollCtrl.position.isScrollingNotifier.removeListener(_onScrollIdleForBottom);
    _bottomJumpWait = false;
    _jumpToBottomIfPinned();
  }

  void _rebuildChildIndex(List<ChatMessageModel> messages) {
    _childIndexByKey.clear();
    for (var i = 0; i < messages.length; i++) {
      _childIndexByKey[stableChatItemKey(messages[messages.length - 1 - i])] = i;
    }
  }

  int? _findChildIndex(Key key) {
    if (key is! ValueKey<String>) return null;
    return _childIndexByKey[key.value];
  }

  String _timelineSig(List<ChatMessageModel> messages) {
    if (messages.isEmpty) return '';
    final buf = StringBuffer();
    for (final m in messages) {
      final issue = extractIssue(m);
      final issueKey =
          issue != null && issue.isNotEmpty ? issueCompareKey(issue) : 0;
      buf
        ..write(m.type.index)
        ..write(':')
        ..write(issueKey)
        ..write(':')
        ..write(m.content.length)
        ..write(':')
        ..write(m.avatarUrl ?? '')
        ..write(':')
        ..write(m.drawRanks?.join(',') ?? '')
        ..write('|');
    }
    return buf.toString();
  }

  void _setMessages(List<ChatMessageModel> messages) {
    final nextIds = messages.map((m) => m.id).toSet();
    final prev = _messagesNotifier.value;
    if (setEquals(nextIds, _messageIds) && messages.length == prev.length) {
      var sameOrder = true;
      for (var i = 0; i < messages.length; i++) {
        if (messages[i].id != prev[i].id) {
          sameOrder = false;
          break;
        }
      }
      if (sameOrder) {
        var contentSame = true;
        for (var i = 0; i < messages.length; i++) {
          final a = messages[i];
          final b = prev[i];
          if (a.content != b.content ||
              a.issueNo != b.issueNo ||
              a.avatarUrl != b.avatarUrl ||
              !listEquals(a.drawRanks, b.drawRanks)) {
            contentSame = false;
            break;
          }
        }
        if (contentSame) return;
      }
    }
    _messageIds
      ..clear()
      ..addAll(nextIds);
    _rebuildChildIndex(messages);
    _messagesNotifier.value = messages;
  }

  /// 立刻上屏：无固定延时。仅把「同一时刻连发」的多条推送合并进下一次 microtask，
  /// 避免同一帧里反复整表赋值；不是人为等 40ms。
  void _applyTimelineFromCache() {
    if (_disposed || !mounted) return;
    _lastTimelineSig = null;
    if (_timelineSyncQueued) return;
    _timelineSyncQueued = true;
    scheduleMicrotask(() {
      _timelineSyncQueued = false;
      if (_disposed || !mounted) return;
      _syncMessagesFromCache();
    });
  }

  void _syncMessagesFromCache({
    bool forceScroll = false,
    bool skipLiveMerge = false,
  }) {
    if (_disposed || !mounted) return;
    final timeline = ref
        .read(roomLotteryLiveProvider(widget.roomId).notifier)
        .timelineForGame(_gameId);
    // 切彩种时禁止把上一彩种 live 封盘 merge 进来
    final merged =
        skipLiveMerge ? timeline : _mergeLiveSeals(timeline);
    final sig = _timelineSig(merged);
    if (sig == _lastTimelineSig) return;
    final prevTailId = _messagesNotifier.value.isNotEmpty
        ? _messagesNotifier.value.last.id
        : null;
    _lastTimelineSig = sig;
    _setMessages(merged);
    final newTailId = merged.isNotEmpty ? merged.last.id : null;
    if (_pinnedToBottom && (forceScroll || newTailId != prevTailId)) {
      _scrollToBottom();
    }
  }

  List<ChatMessageModel> _mergeLiveSeals(List<ChatMessageModel> timeline) {
    var maxDrawKey = 0;
    final sealedInTimeline = <int>{};
    final warnInTimeline = <int>{};
    for (final m in timeline) {
      final issue = extractIssue(m);
      if (issue == null || issue.isEmpty) continue;
      final key = issueCompareKey(issue);
      if (key <= 0) continue;
      if (m.type == ChatMessageType.resultCard) {
        maxDrawKey = math.max(maxDrawKey, key);
      } else if (m.type == ChatMessageType.system) {
        if (m.content.contains('封盘线') || m.content.contains('停止战斗')) {
          sealedInTimeline.add(key);
        } else if (m.content.contains('封盘')) {
          warnInTimeline.add(key);
        }
      }
    }
    final game = ref.read(roomLotteryLiveProvider(widget.roomId)).gameById(_gameId);
    final currentKey = issueCompareKey(game?.currentIssue ?? '');
    final extras = <ChatMessageModel>[];
    for (final m in _messagesNotifier.value) {
      if (m.type != ChatMessageType.system) continue;
      final issue = extractIssue(m);
      if (issue == null || issue.isEmpty) continue;
      final key = issueCompareKey(issue);
      if (key <= 0 || key != currentKey || key <= maxDrawKey) continue;
      final isLine =
          m.content.contains('封盘线') || m.content.contains('停止战斗');
      final isWarn = m.content.contains('封盘');
      if (isLine && !sealedInTimeline.contains(key)) {
        extras.add(m);
        sealedInTimeline.add(key);
      } else if (!isLine && isWarn && !warnInTimeline.contains(key)) {
        extras.add(m);
        warnInTimeline.add(key);
      }
    }
    if (extras.isEmpty) return timeline;
    // 必须重排，禁止把封盘 append 到开奖/中奖核对后面
    return buildChatTimeline(
      [...timeline, ...extras],
      gameId: _gameId,
      syntheticSeals: false,
    );
  }

  /// 写入缓存后统一走时间线，避免只 append 导致期序乱。
  void _publishChatMessage(ChatMessageModel message, {required String dedupeKey}) {
    ChatPushCache.instance.pushOnce(
      roomId: widget.roomId,
      dedupeKey: dedupeKey,
      gameId: _gameId,
      message: message,
    );
    // 指令和确认卡、以及随后的 WS 回声，合并成一次时间线刷新。
    _applyTimelineFromCache();
  }

  void _syncDockLayout() {
    if (!mounted) return;
    final nextPad = _dockBottomPadding(_panel);
    if (_dockPaddingNotifier.value != nextPad) {
      _dockPaddingNotifier.value = nextPad;
    }
    final hidden =
        _panel == _BottomPanel.quickBet && _marketReadyNotifier.value;
    if (_chatHiddenNotifier.value != hidden) {
      _chatHiddenNotifier.value = hidden;
    }
  }

  bool _acceptPanelToggle() {
    final now = DateTime.now();
    final last = _lastPanelToggleAt;
    if (last != null && now.difference(last).inMilliseconds < 120) {
      return false;
    }
    _lastPanelToggleAt = now;
    return true;
  }

  void _dismissTopPanel() {
    if (_topPanelNotifier.value != _TopPanel.none) {
      _topPanelNotifier.value = _TopPanel.none;
    }
  }

  void _markOverlayOpened() {
    // 忽略同一手指抬起落到遮罩上；遮罩立即显示，不人为卡顿
    _overlayIgnoreDismissUntil =
        DateTime.now().add(const Duration(milliseconds: 200));
  }

  void _dismissOverlays() {
    final until = _overlayIgnoreDismissUntil;
    if (until != null && DateTime.now().isBefore(until)) return;
    // 历史下拉只由顶栏球号行再点一次关闭，点聊天/输入不关
    _dismissTopPanel();
  }

  void _toggleHistoryPanel() {
    if (_historyExpandedNotifier.value) {
      _historyExpandedNotifier.value = false;
      return;
    }
    // 按下即展开：先灌缓存再翻状态，网络刷新丢到帧后
    if (_topPanelNotifier.value != _TopPanel.none) {
      _topPanelNotifier.value = _TopPanel.none;
    }
    _refreshHistoryRows();
    if (!_historyPanelMounted.value) {
      _historyPanelMounted.value = true;
    }
    _historyExpandedNotifier.value = true;
    _markOverlayOpened();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_disposed || !mounted || !_historyExpandedNotifier.value) return;
      unawaited(_ensureHistoryPanelReady());
    });
  }

  /// 首帧挂载后才能读 MediaQuery（initState 里调用会崩）。
  void _scheduleDockLayoutSync() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncDockLayout();
    });
  }

  void _setPanel(_BottomPanel panel) {
    if (_panel == panel) return;
    _panel = panel;
    _panelNotifier.value = panel;
    if (panel == _BottomPanel.quickBet && !_marketReadyNotifier.value) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _marketReadyNotifier.value = true;
          _syncDockLayout();
        }
      });
    } else if (panel != _BottomPanel.quickBet) {
      _marketReadyNotifier.value = false;
    }
    _syncDockLayout();
  }

  double _betInputBarHeight() => 10.h + 44.h + 10.h;

  double _maxBottomPanelHeight() {
    final keypadH = BetKeypadPanel.panelHeight;
    final menuH = BetActionMenuPanel.panelHeight(context);
    return keypadH > menuH ? keypadH : menuH;
  }

  double _dockBottomPadding(_BottomPanel panel) {
    final bottomSafe = MediaQuery.viewPaddingOf(context).bottom;
    final inputH = _betInputBarHeight();
    const extra = 12.0;
    if (panel == _BottomPanel.keypad || panel == _BottomPanel.menu) {
      return inputH + _maxBottomPanelHeight() + bottomSafe + extra;
    }
    return inputH + bottomSafe + extra;
  }

  String? _pendingLocalBetId;

  String _publishOptimisticBet(String command) {
    final user = ref.read(authSessionProvider).user;
    final sender =
        (user?.nickname.isNotEmpty == true) ? user!.nickname : '我';
    final issue = ref
            .read(roomLotteryLiveProvider(widget.roomId))
            .gameById(_gameId)
            ?.currentIssue ??
        '';
    final id = 'local-bet-$_gameId-${DateTime.now().microsecondsSinceEpoch}';
    _pendingLocalBetId = id;
    _publishChatMessage(
      ChatMessageModel(
        id: id,
        sender: sender,
        content: command,
        time: TimeOfDay.now().format(context),
        issueNo: issue.isNotEmpty ? issue : null,
        isSelf: true,
        avatarUrl: user?.avatarUrl,
      ),
      dedupeKey: id,
    );
    return id;
  }

  void _dropOptimisticBet(String localId) {
    if (_pendingLocalBetId == localId) _pendingLocalBetId = null;
    ChatPushCache.instance.dropMessage(
      roomId: widget.roomId,
      gameId: _gameId,
      dedupeKey: localId,
    );
    _applyTimelineFromCache();
  }

  void _completeOptimisticBet(String command, List<String> orderIds) {
    final localId = _pendingLocalBetId;
    _pendingLocalBetId = null;
    if (localId == null) {
      _appendLocalMessage(command, orderIds: orderIds);
      return;
    }
    if (orderIds.isNotEmpty) {
      ChatPushCache.instance.adoptLocalBet(
        roomId: widget.roomId,
        gameId: _gameId,
        localId: localId,
        orderId: orderIds.first,
      );
      _applyTimelineFromCache();
    }
    _appendLocalReceipt(command, orderIds: orderIds);
  }

  void _appendLocalMessage(String command, {List<String> orderIds = const []}) {
    final user = ref.read(authSessionProvider).user;
    final sender =
        (user?.nickname.isNotEmpty == true) ? user!.nickname : '我';
    final issue = ref
            .read(roomLotteryLiveProvider(widget.roomId))
            .gameById(_gameId)
            ?.currentIssue ??
        '';
    final id = orderIds.isNotEmpty
        ? 'bet-chat-$_gameId-${orderIds.first}'
        : 'bet-chat-$_gameId-${DateTime.now().millisecondsSinceEpoch}';
    final message = ChatMessageModel(
      id: id,
      sender: sender,
      content: command,
      time: TimeOfDay.now().format(context),
      issueNo: issue.isNotEmpty ? issue : null,
      isSelf: true,
      avatarUrl: user?.avatarUrl,
    );
    _publishChatMessage(message, dedupeKey: id);
    _appendLocalReceipt(
      command,
      orderIds: orderIds,
      sender: sender,
      issue: issue,
      time: message.time,
    );
  }

  void _appendLocalReceipt(
    String command, {
    List<String> orderIds = const [],
    String? sender,
    String? issue,
    String? time,
  }) {
    final user = ref.read(authSessionProvider).user;
    final mention = sender ??
        ((user?.nickname.isNotEmpty == true) ? user!.nickname : '我');
    final issueNo = issue ??
        (ref
                .read(roomLotteryLiveProvider(widget.roomId))
                .gameById(_gameId)
                ?.currentIssue ??
            '');
    final stamp = time ?? TimeOfDay.now().format(context);
    final receiptId = orderIds.isNotEmpty
        ? 'bet-receipt-$_gameId-${orderIds.first}'
        : 'bet-receipt-$_gameId-${DateTime.now().millisecondsSinceEpoch}';
    final receipt = ChatMessageModel(
      id: receiptId,
      sender: '机器人',
      content: formatBetReceiptText(
        mention: mention,
        issue: issueNo,
        fallbackContent: command,
      ),
      time: stamp,
      type: ChatMessageType.betReceipt,
      issueNo: issueNo.isNotEmpty ? issueNo : null,
    );
    _publishChatMessage(receipt, dedupeKey: receipt.id);
  }

  void _appendBetSlip(String command, {List<String> orderIds = const []}) {
    final issue = ref
            .read(roomLotteryLiveProvider(widget.roomId))
            .gameById(_gameId)
            ?.currentIssue ??
        '-';
    final canCancel = _canCancelBetsNow();
    final rows = <BetSlipRow>[];
    if (orderIds.isEmpty) {
      rows.add(BetSlipRow(
        issue: issue,
        amount: command,
        canCancel: canCancel,
      ));
    } else {
      for (final id in orderIds) {
        rows.add(BetSlipRow(
          issue: issue,
          amount: command,
          orderId: id,
          canCancel: canCancel,
        ));
      }
    }
    _betSlipsNotifier.value = [
      ...rows,
      ..._betSlipsNotifier.value,
    ];
  }

  bool _canCancelBetsNow() {
    final game = ref
        .read(roomLotteryLiveProvider(widget.roomId).notifier)
        .displayGameFor(_gameId);
    if (game == null) return false;
    return LotteryPeriodHelper.canBetNow(game);
  }

  Future<void> _cancelCurrentIssueBets() async {
    if (!ref.read(authSessionProvider).canPlaceBet) return;
    final game = ref
        .read(roomLotteryLiveProvider(widget.roomId).notifier)
        .displayGameFor(_gameId);
    if (game == null) {
      AppToast.info('彩种信息加载中');
      return;
    }
    if (!LotteryPeriodHelper.canBetNow(game)) {
      AppToast.info('已封盘，不能取消');
      return;
    }
    final issueNo = game.currentIssue;
    if (issueNo.isEmpty) {
      AppToast.info('期号无效');
      return;
    }
    if (_betGuard.isBusy) return;
    try {
      final cancelled = await _betGuard.run((requestId) async {
        return ref.read(lotteryRepositoryProvider).cancelIssueBets(
              gameId: _gameId,
              issueNo: issueNo,
              requestId: requestId,
            );
      });
      if (!mounted) return;
      unawaited(
        ref.read(roomLotteryLiveProvider(widget.roomId).notifier).refreshWallet(),
      );
      _betSlipsNotifier.value = _betSlipsNotifier.value
          .where((r) => r.issue != issueNo)
          .toList();
      _clearBetText();
      if ((cancelled ?? 0) <= 0) {
        AppToast.info('当前期暂无可取消注单');
        return;
      }
      _appendLocalMessage('取消');
      AppToast.success('已取消 $cancelled 笔注单');
    } catch (e) {
      AppToast.error(e.toString());
    }
  }

  Future<void> _cancelBetSlipRow(int index) async {
    if (!ref.read(authSessionProvider).canPlaceBet) return;
    final rows = _betSlipsNotifier.value;
    if (index < 0 || index >= rows.length) return;
    final row = rows[index];
    if (!row.canCancel) {
      AppToast.info('已封盘，不能取消');
      return;
    }
    final orderId = row.orderId;
    if (orderId == null || orderId.isEmpty) {
      await _cancelCurrentIssueBets();
      return;
    }
    if (_betGuard.isBusy) return;
    try {
      final done = await _betGuard.run((requestId) async {
        await ref.read(lotteryRepositoryProvider).cancelBetOrder(
              orderId: orderId,
              requestId: requestId,
            );
        return true;
      });
      if (done != true || !mounted) return;
      unawaited(
        ref.read(roomLotteryLiveProvider(widget.roomId).notifier).refreshWallet(),
      );
      final next = List<BetSlipRow>.from(rows)..removeAt(index);
      _betSlipsNotifier.value = next;
      AppToast.success('已取消注单');
    } catch (e) {
      AppToast.error(e.toString());
    }
  }

  void _rememberSuccessfulBet(String command) {
    unawaited(
      BetRepeatStore.save(
        roomId: widget.roomId,
        gameId: _gameId,
        accountId: _accountId,
        command: command,
      ),
    );
  }

  void _scheduleBetDraftSave() {
    _draftSaveTimer?.cancel();
    _draftSaveTimer = Timer(const Duration(milliseconds: 400), () {
      if (!mounted) return;
      unawaited(
        BetDraftStore.save(
          roomId: widget.roomId,
          gameId: _gameId,
          accountId: _accountId,
          draft: _betCtrl.text,
        ),
      );
    });
  }

  Future<void> _restoreBetDraft() async {
    final draft = await BetDraftStore.read(
      roomId: widget.roomId,
      gameId: _gameId,
      accountId: _accountId,
    );
    if (!mounted || draft == null || draft.isEmpty) return;
    _betCtrl.value = TextEditingValue(
      text: draft,
      selection: TextSelection.collapsed(offset: draft.length),
    );
  }

  Future<void> _restoreBetSlipsFromServer() async {
    final game =
        ref.read(roomLotteryLiveProvider(widget.roomId)).gameById(_gameId);
    if (game == null) return;
    final issue = game.currentIssue;
    if (issue.isEmpty) return;
    try {
      final data = await ref.read(walletRepositoryProvider).getBets(
            pageSize: 100,
          );
      final raw = data['rows'];
      if (raw is! List || !mounted) return;
      final canCancel = _canCancelBetsNow();
      final slips = <BetSlipRow>[];
      for (final item in raw.whereType<Map>()) {
        final row = Map<String, dynamic>.from(item);
        if ('${row['status'] ?? ''}' != 'PENDING') continue;
        final gameType = '${row['gameType'] ?? row['game_type'] ?? ''}';
        if (gameType != _gameId) continue;
        final orderIssue = '${row['issueNo'] ?? row['issue_no'] ?? ''}';
        if (orderIssue != issue) continue;
        final orderId = '${row['orderId'] ?? row['order_id'] ?? ''}';
        final content = '${row['content'] ?? ''}'.trim();
        final playName =
            '${row['playName'] ?? row['play_name'] ?? row['playCode'] ?? ''}';
        final amount = row['amount'];
        final label = content.isNotEmpty
            ? content
            : (playName.isNotEmpty ? '$playName/$amount' : '$amount');
        slips.add(
          BetSlipRow(
            issue: issue,
            amount: label,
            orderId: orderId.isNotEmpty ? orderId : null,
            canCancel: canCancel,
          ),
        );
      }
      if (slips.isNotEmpty) {
        _betSlipsNotifier.value = slips.reversed.toList();
      }
    } catch (_) {}
  }

  Future<void> _repeatLastBet() async {
    final user = ref.read(authSessionProvider).user;
    final command = await BetRepeatStore.read(
          roomId: widget.roomId,
          gameId: _gameId,
          accountId: _accountId,
        ) ??
        findRepeatableFromMessages(_messagesNotifier.value, user);
    if (!mounted) return;
    if (command == null || command.isEmpty) {
      AppToast.info('暂无可重复注单');
      return;
    }
    _betCtrl.value = TextEditingValue(
      text: command,
      selection: TextSelection.collapsed(offset: command.length),
    );
    unawaited(
      BetDraftStore.save(
        roomId: widget.roomId,
        gameId: _gameId,
        accountId: _accountId,
        draft: command,
      ),
    );
  }

  void _hydrateMessagesFromCacheIfReady() {
    _messagesLoadingNotifier.value = false;
    final cache = ChatPushCache.instance;
    final live = ref.read(roomLotteryLiveProvider(widget.roomId).notifier);
    final hasBuffered =
        cache.bufferedForGame(widget.roomId, _gameId).isNotEmpty ||
        cache.hasDrawsForGame(widget.roomId, _gameId) ||
        live.isChatTimelineWarm(_gameId);
    if (!hasBuffered) return;
    _lastTimelineSig = null;
    _syncMessagesFromCache(forceScroll: true);
  }

  @override
  void initState() {
    super.initState();
    _accountId = ref.read(authSessionProvider).user?.id ?? '';
    _scrollCtrl.addListener(_onScrollChanged);
    _betCtrl.addListener(_scheduleBetDraftSave);
    _gameId = widget.gameId;
    _gameIdNotifier.value = widget.gameId;
    // 竞品路径：首帧绝不转圈；内存有货立刻画。
    _messagesLoadingNotifier.value = false;
    _hydrateMessagesFromCacheIfReady();
    _scheduleDockLayoutSync();
    final subGen = ++_chatSubGen;
    Future.microtask(() async {
      if (_disposed || subGen != _chatSubGen) return;
      final live = ref.read(roomLotteryLiveProvider(widget.roomId).notifier);
      // 磁盘缓冲先上屏，不等人房间全彩种 15 期预载。
      await live.ensureChatBufferLoaded();
      if (_disposed || subGen != _chatSubGen) return;
      _messagesLoadingNotifier.value = false;
      _hydrateMessagesFromCacheIfReady();

      // 房间态 / 全彩种预拉全部后台，不挡首屏。
      unawaited(live.ensureLoaded());
      unawaited(live.ensureDrawHistoryPreloaded());
      unawaited(live.refreshWallet());

      if (_disposed || subGen != _chatSubGen) return;
      _chatPushSub?.cancel();
      _chatPushSub = live.chatPushes.listen((push) {
        if (_disposed || !mounted || push.gameId != _gameId) return;
        _applyTimelineFromCache();
      });
      if (_disposed || subGen != _chatSubGen) {
        _chatPushSub?.cancel();
        _chatPushSub = null;
        return;
      }
      // 当前彩种后台核对，永不盖转圈。
      unawaited(
        _loadMessages(showLoadingOverlay: false, silent: true),
      );
      unawaited(_restoreBetDraft());
      unawaited(_restoreBetSlipsFromServer());
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncDockLayout();
    final visible = ChatOverlayVisibility.maybeOf(context)?.visible ?? true;
    if (_overlayWasVisible && !visible) {
      if (_panel != _BottomPanel.none) {
        _setPanel(_BottomPanel.none);
      }
      _topPanelNotifier.value = _TopPanel.none;
      _historyExpandedNotifier.value = false;
      _fabSelectedNotifier.value = null;
    }
    _overlayWasVisible = visible;
  }

  @override
  void didUpdateWidget(covariant ChatBetPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.gameId != widget.gameId && widget.gameId != _gameId) {
      _switchToGame(widget.gameId);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _chatSubGen++;
    _chatPushSub?.cancel();
    _chatPushSub = null;
    _draftSaveTimer?.cancel();
    _historyRowsDebounce?.cancel();
    _betCtrl.removeListener(_scheduleBetDraftSave);
    final accountId = _accountId;
    final draft = _betCtrl.text;
    unawaited(
      BetDraftStore.save(
        roomId: widget.roomId,
        gameId: _gameId,
        accountId: accountId,
        draft: draft,
      ),
    );
    _gameIdNotifier.dispose();
    if (_bottomJumpWait && _scrollCtrl.hasClients) {
      _scrollCtrl.position.isScrollingNotifier.removeListener(_onScrollIdleForBottom);
    }
    _scrollCtrl.removeListener(_onScrollChanged);
    _scrollCtrl.dispose();
    _betCtrl.dispose();
    _messagesNotifier.dispose();
    _betSlipsNotifier.dispose();
    _messagesLoadingNotifier.dispose();
    _panelNotifier.dispose();
    _topPanelNotifier.dispose();
    _historyExpandedNotifier.dispose();
    _historyPanelMounted.dispose();
    _historyLoadingNotifier.dispose();
    _longDragonRowsNotifier.dispose();
    _longDragonLoadingNotifier.dispose();
    _fabSelectedNotifier.dispose();
    _marketReadyNotifier.dispose();
    _dockPaddingNotifier.dispose();
    _historyDisplayRowsNotifier.dispose();
    _chatHiddenNotifier.dispose();
    _showJumpBottomNotifier.dispose();
    _betBusy.dispose();
    super.dispose();
  }

  /// 切彩种：不转圈。有缓冲立刻换时间线；无缓冲暂留旧列表，后台静默拉完再替换。
  void _switchToGame(String gameId) {
    if (gameId == _gameId) return;
    _gameId = gameId;
    _gameIdNotifier.value = gameId;
    _lastTimelineSig = null;
    _messageIds.clear();
    _longDragonLoadedGameId = null;
    _longDragonRowsNotifier.value = null;
    _setPanel(_BottomPanel.none);
    _topPanelNotifier.value = _TopPanel.none;
    _historyExpandedNotifier.value = false;
    _fabSelectedNotifier.value = null;
    _messagesLoadingNotifier.value = false;

    final live = ref.read(roomLotteryLiveProvider(widget.roomId).notifier);
    final warm = live.isChatTimelineWarm(gameId);
    final hasBuffered =
        ChatPushCache.instance.bufferedForGame(widget.roomId, gameId).isNotEmpty ||
        ChatPushCache.instance.hasDrawsForGame(widget.roomId, gameId);
    if (warm || hasBuffered) {
      _syncMessagesFromCache(forceScroll: true, skipLiveMerge: true);
    } else {
      // 冷切：清空旧彩种列表，勿把上一彩种内容留到新彩种（不转圈）。
      _messagesNotifier.value = const [];
      _messageIds.clear();
    }
    unawaited(
      _loadMessages(
        forceReload: !warm,
        silent: true,
        showLoadingOverlay: false,
      ),
    );
  }

  Future<void> _loadMessages({
    bool silent = false,
    bool forceReload = false,
    bool showLoadingOverlay = false,
  }) {
    // 每次新开（含切彩）：靠 _msgLoadGen 丢弃过期结果，勿用 ??= 卡住后续彩种。
    final future = _loadMessagesImpl(
      silent: silent,
      forceReload: forceReload,
      showLoadingOverlay: showLoadingOverlay,
    );
    _msgLoadInflight = future;
    return future.whenComplete(() {
      if (identical(_msgLoadInflight, future)) {
        _msgLoadInflight = null;
      }
    });
  }

  Future<void> _loadMessagesImpl({
    bool silent = false,
    bool forceReload = false,
    bool showLoadingOverlay = false,
  }) async {
    final gen = ++_msgLoadGen;
    final liveNotifier =
        ref.read(roomLotteryLiveProvider(widget.roomId).notifier);

    final warm =
        !forceReload && liveNotifier.isChatTimelineWarm(_gameId);
    final hasCache = ChatPushCache.instance
        .hasDrawsForGame(widget.roomId, _gameId);
    final hasVisibleMessages = _messagesNotifier.value.isNotEmpty;
    // 竞品：有内容可画就不转圈；默认也不转圈（仅显式要求且空列表时才转）。
    if (showLoadingOverlay &&
        !silent &&
        !warm &&
        !hasVisibleMessages &&
        !hasCache) {
      _messagesLoadingNotifier.value = true;
    } else {
      _messagesLoadingNotifier.value = false;
      if (warm || hasVisibleMessages || hasCache) {
        _lastTimelineSig = null;
        _syncMessagesFromCache(forceScroll: true);
      }
    }

    try {
      await liveNotifier.ensureChatBufferLoaded();
      if (!mounted || gen != _msgLoadGen) return;

      await liveNotifier.prepareChatTimeline(
        _gameId,
        forceNetwork: forceReload || (!warm && !hasCache),
      );

      if (!mounted || gen != _msgLoadGen) return;
      _lastTimelineSig = null;
      _syncMessagesFromCache(forceScroll: true);
      _scheduleHistoryRowsRefresh();

      if (!silent) {
        unawaited(_restoreBetDraft());
        unawaited(_restoreBetSlipsFromServer());
        _setPanel(_BottomPanel.none);
        _topPanelNotifier.value = _TopPanel.none;
        _historyExpandedNotifier.value = false;
        _fabSelectedNotifier.value = null;
        _marketReadyNotifier.value = false;
        _syncDockLayout();
        _pinnedToBottom = true;
        _scrollToBottom();
      }
    } catch (e) {
      if (!mounted || gen != _msgLoadGen) return;
      AppToast.error(e.toString());
    } finally {
      if (mounted && gen == _msgLoadGen) {
        _messagesLoadingNotifier.value = false;
      }
    }
  }

  Future<void> _openSwitchGame() async {
    final live = ref.read(roomLotteryLiveProvider(widget.roomId));
    if (live.games.isEmpty) return;
    final selected = await showSwitchGameDialog(
      context: context,
      games: live.games,
      currentGameId: _gameId,
    );
    if (!mounted) return;
    // 先清 FAB 高亮，避免与切 Overlay 同帧叠重建
    _fabSelectedNotifier.value = null;
    if (selected == null || selected.id == _gameId) return;

    final targetId = selected.id;
    final switchViaHall = widget.onSwitchGame;
    // 再等一帧：弹窗 route 已卸完，本帧布局稳定后再换保活页
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (switchViaHall != null) {
        switchViaHall(targetId);
        return;
      }
      _switchToGame(targetId);
    });
  }

  void _insertText(String text) {
    final value = _betCtrl.text;
    final next = '$value$text';
    _betCtrl.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: next.length),
    );
  }

  void _backspace() {
    final value = _betCtrl.text;
    if (value.isEmpty) return;
    final next = value.substring(0, value.length - 1);
    _betCtrl.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: next.length),
    );
  }

  void _clearBetText() {
    _betCtrl.value = const TextEditingValue(
      text: '',
      selection: TextSelection.collapsed(offset: 0),
    );
  }

  Future<void> _handleAction(String action) async {
    if ((action == '上分' || action == '下分') &&
        ref.read(roomLotteryLiveProvider(widget.roomId)).isTrialAccount) {
      AppToast.info('试玩账号不可$action');
      return;
    }
    switch (action) {
      case '取消':
        await _cancelCurrentIssueBets();
        return;
      case '重复':
        await _repeatLastBet();
        return;
      case '梭哈':
        _insertText('梭哈');
        return;
      case '上分':
        await _submitWalletApplication('UP');
        return;
      case '下分':
        await _submitWalletApplication('DOWN');
        return;
    }
  }

  Future<void> _submitWalletApplication(String applyType) async {
    if (!ref.read(authSessionProvider).canPlaceBet) return;
    if (ref.read(roomLotteryLiveProvider(widget.roomId)).isTrialAccount) {
      AppToast.info(applyType == 'UP' ? '试玩账号不可上分' : '试玩账号不可下分');
      return;
    }
    if (_walletGuard.isBusy || _walletDialogOpen) return;
    _walletDialogOpen = true;
    final label = applyType == 'UP' ? '上分' : '下分';
    // 关掉自定义键盘/菜单，避免挡住弹窗或抢走输入焦点（下分在键盘最右侧更易误触）
    _setPanel(_BottomPanel.none);
    _fabSelectedNotifier.value = null;
    try {
      final amountText = await showTextInputDialog(
        context: context,
        title: '申请$label',
        hint: '请输入$label金额',
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        digitsOnly: true,
      );
      if (amountText == null) return;
      final amount = double.tryParse(amountText);
      if (amount == null || amount <= 0) {
        AppToast.info('请输入有效金额');
        return;
      }
      final done = await _walletGuard.run((requestId) async {
        await ref.read(walletRepositoryProvider).submitApplication(
              applyType: applyType,
              amount: amount,
              remark: 'chat-$label',
              requestId: requestId,
            );
        return true;
      });
      if (done != true || !mounted) return;
      AppToast.success('$label申请已提交');
      pushLocalPage(context, const ApplyRecordsPage());
    } catch (e) {
      AppToast.error(e.toString());
    } finally {
      _walletDialogOpen = false;
    }
  }

  Future<void> _claimRebate() async {
    if (ref.read(roomLotteryLiveProvider(widget.roomId)).isTrialAccount) {
      AppToast.info('试玩账号不可自助回水');
      return;
    }
    try {
      final data = await ref.read(walletRepositoryProvider).claimRebate();
      final raw = data['claimed'];
      final claimed = raw is num ? raw.toDouble() : double.tryParse('$raw') ?? 0;
      if (!mounted) return;
      if (claimed > 0) {
        AppToast.success('已领取回水 ${claimed.toStringAsFixed(2)}');
      } else {
        AppToast.info('暂无可领取回水');
      }
      unawaited(
        ref.read(roomLotteryLiveProvider(widget.roomId).notifier).refreshWallet(),
      );
    } catch (e) {
      AppToast.error(e.toString());
    }
  }

  void _onMenuItem(String label) {
    // 自助回水就地领取，保持下注菜单展开；其它项关闭菜单后再跳转/弹窗
    if (label != '自助回水') {
      _setPanel(_BottomPanel.none);
    }
    final trialBlocked = const {'上分', '下分', '申请记录', '自助回水'};
    if (trialBlocked.contains(label) &&
        ref.read(roomLotteryLiveProvider(widget.roomId)).isTrialAccount) {
      AppToast.info('试玩账号不可$label');
      return;
    }
    if (label == '上分' || label == '下分') {
      _submitWalletApplication(label == '上分' ? 'UP' : 'DOWN');
      return;
    }
    if (label == '自助回水') {
      unawaited(_claimRebate());
      return;
    }
    final page = switch (label) {
      '申请记录' => const ApplyRecordsPage(),
      '积分账变' => const PointsChangePage(),
      '福利报表' => const WelfareReportPage(),
      '竞猜报表' => const BetRecordsPage(),
      _ => null,
    };
    if (page == null) {
      AppToast.info('暂不支持「$label」');
      return;
    }
    pushLocalPage(context, page);
  }

  Future<void> _submitBet() async {
    if (!ref.read(authSessionProvider).canPlaceBet) return;
    final command = _betCtrl.text.trim();
    if (command.isEmpty) {
      AppToast.info('请输入下注指令');
      return;
    }
    if (command == '取消') {
      await _cancelCurrentIssueBets();
      return;
    }
    if (command == '重复') {
      await _repeatLastBet();
      return;
    }
    if (isMachinePlayCode(command)) {
      AppToast.info('请使用指令格式，例如 1/大/100');
      return;
    }
    if (_submitLocked || _betGuard.isBusy || _betBusy.value) return;

    final live = ref.read(roomLotteryLiveProvider(widget.roomId));
    final needConfirm = live.betConfirm || SessionStore.instance.betConfirm;
    if (needConfirm) {
      final game = ref
          .read(roomLotteryLiveProvider(widget.roomId).notifier)
          .displayGameFor(_gameId);
      final issue = game?.currentIssue ?? '';
      final ok = await showBetConfirmDialog(
        context: context,
        command: command,
        issueNo: issue,
        amountText: _guessBetAmountText(command),
      );
      if (!ok || !mounted) return;
    }

    _submitLocked = true;
    _betBusy.value = true;
    final localId = _publishOptimisticBet(command);
    try {
      final done = await _betGuard.run((requestId) async {
        return ref.read(lotteryRepositoryProvider).submitBet(
              roomId: widget.roomId,
              gameId: _gameId,
              command: command,
              requestId: requestId,
            );
      });
      if (done == null || !mounted) {
        _dropOptimisticBet(localId);
        return;
      }
      unawaited(
        ref.read(roomLotteryLiveProvider(widget.roomId).notifier).refreshWallet(),
      );
      if (!mounted) return;
      _betCtrl.clear();
      unawaited(
        BetDraftStore.clear(
          roomId: widget.roomId,
          gameId: _gameId,
          accountId: _accountId,
        ),
      );
      final slip = done.content.trim().isNotEmpty ? done.content.trim() : command;
      _completeOptimisticBet(command, done.orderIds);
      _rememberSuccessfulBet(command);
      _appendBetSlip(slip, orderIds: done.orderIds);
      AppToast.success('下注成功');
    } catch (e) {
      _dropOptimisticBet(localId);
      AppToast.error(e.toString());
    } finally {
      _submitLocked = false;
      if (mounted) _betBusy.value = false;
    }
  }

  String? _guessBetAmountText(String command) {
    // 1/大/10  大/100  大100  多个指令空格分隔时汇总数字段
    final shorthand = RegExp(r'^[大小单双]([1-9]\d*)$');
    final parts = command.split(RegExp(r'\s+'));
    final amounts = <String>[];
    for (final p in parts) {
      final segs = p.split('/');
      if (segs.length >= 2) {
        final last = segs.last.trim();
        if (num.tryParse(last) != null) amounts.add(last);
        continue;
      }
      final hit = shorthand.firstMatch(p.trim());
      if (hit != null) amounts.add(hit.group(1)!);
    }
    if (amounts.isEmpty) return null;
    if (amounts.length == 1) return amounts.first;
    return amounts.join('+');
  }

  Future<void> _claimRedpack() async {
    _fabSelectedNotifier.value = 2;
    if (_panel == _BottomPanel.quickBet) {
      _setPanel(_BottomPanel.none);
    }
    try {
      final list = await ref.read(memberRepositoryProvider).getRedpacks();
      if (!mounted) return;
      if (list.isEmpty) {
        AppToast.info('\u6682\u65e0\u53ef\u9886\u7ea2\u5305');
        return;
      }
      final first = list.first;
      final id = (first['redpackId'] ?? first['id'] ?? '').toString();
      if (id.isEmpty) {
        AppToast.info('\u7ea2\u5305\u6570\u636e\u5f02\u5e38');
        return;
      }
      final claimed = first['claimed'] == true;
      if (claimed) {
        AppToast.info('\u5df2\u9886\u53d6');
        return;
      }
      final res = await ref.read(memberRepositoryProvider).claimRedpack(id);
      if (!mounted) return;
      final amount = res['amount'];
      final msg = (res['message'] ?? '').toString();
      if (res['success'] == false) {
        AppToast.info(msg.isEmpty ? '\u9886\u53d6\u5931\u8d25' : msg);
      } else {
        AppToast.success(msg.isEmpty ? '\u9886\u53d6\u6210\u529f ${amount ?? ''}' : msg);
        await ref.read(roomLotteryLiveProvider(widget.roomId).notifier).refreshWallet();
      }
    } catch (e) {
      AppToast.error(e.toString());
    } finally {
      if (mounted) _fabSelectedNotifier.value = null;
    }
  }

  Future<void> _loadLongDragon({bool force = false}) async {
    if (!force &&
        _longDragonLoadedGameId == _gameId &&
        _longDragonRowsNotifier.value != null) {
      return;
    }
    if (_longDragonLoadingNotifier.value) return;
    final gen = ++_longDragonLoadGen;
    _longDragonLoadingNotifier.value = true;
    try {
      final items = await ref.read(lotteryRepositoryProvider).getLongDragon(
            gameId: _gameId,
            limit: LongDragonPanel.maxRows,
          );
      if (!mounted || gen != _longDragonLoadGen) return;
      _longDragonRowsNotifier.value = _mapLongDragonItems(items)
          .take(LongDragonPanel.maxRows)
          .toList();
      _longDragonLoadedGameId = _gameId;
    } catch (_) {
      if (!mounted || gen != _longDragonLoadGen) return;
      _longDragonRowsNotifier.value = const [];
    } finally {
      if (mounted && gen == _longDragonLoadGen) {
        _longDragonLoadingNotifier.value = false;
      }
    }
  }

  List<LongDragonRow> _mapLongDragonItems(List<Map<String, dynamic>> items) {
    Color? colorForSide(String side) {
      final s = side.toUpperCase();
      if (s.contains('BIG') || s.contains('ODD') || s.contains('DRAGON')) {
        return const Color(0xFFE53935);
      }
      if (s.contains('SMALL') || s.contains('EVEN') || s.contains('TIGER')) {
        return const Color(0xFF1E88E5);
      }
      return null;
    }

    String sideLabel(String side) {
      switch (side.toUpperCase()) {
        case 'BIG':
          return '大';
        case 'SMALL':
          return '小';
        case 'ODD':
          return '单';
        case 'EVEN':
          return '双';
        case 'DRAGON':
          return '龙';
        case 'TIGER':
          return '虎';
        default:
          return side;
      }
    }

    return items
        .map(
          (e) => LongDragonRow(
            position: e['categoryName']?.toString() ?? '',
            result: sideLabel('${e['side'] ?? ''}'),
            streak: int.tryParse('${e['streak'] ?? 0}') ?? 0,
            resultColor: colorForSide('${e['side'] ?? ''}'),
          ),
        )
        .toList();
  }

  List<HistoryDrawRow> _mergeLiveHistoryHead(
    LotteryGameModel game,
    List<HistoryDrawRow> rows,
  ) {
    final issue = game.previousIssue?.trim() ?? '';
    final balls = game.previousResults.where((n) => n > 0).toList();
    if (issue.isEmpty || balls.isEmpty) {
      return rows.take(HistoryDrawPanel.maxCachedRows).toList(growable: false);
    }
    final liveHead = HistoryDrawRow(
      issue: issue,
      numbers: balls,
      summary: balls.length >= 2 ? '${balls[0] + balls[1]}' : '',
    );
    // 历史面板要能上拉翻页：只做表头顶条合并，不能用断档截断 / pageSize=20 上限
    final out = <HistoryDrawRow>[liveHead];
    for (final row in rows) {
      if (sameIssueNo(row.issue, liveHead.issue)) continue;
      out.add(row);
      if (out.length >= HistoryDrawPanel.maxCachedRows) break;
    }
    return out;
  }

  void _scheduleHistoryRowsRefresh() {
    _historyRowsDebounce?.cancel();
    _historyRowsDebounce = Timer(const Duration(milliseconds: 400), () {
      if (_disposed || !mounted) return;
      _refreshHistoryRows();
    });
  }

  void _refreshHistoryRows() {
    final live = ref.read(roomLotteryLiveProvider(widget.roomId));
    final game = live.gameById(_gameId);
    final cached = ref
        .read(roomLotteryLiveProvider(widget.roomId).notifier)
        .drawHistoryForGame(_gameId);
    _historyDisplayRowsNotifier.value = game != null
        ? _mergeLiveHistoryHead(game, cached)
        : cached;
  }

  Future<void> _ensureHistoryPanelReady() async {
    final gen = ++_historyReadyGen;
    final hasRows = _historyDisplayRowsNotifier.value.isNotEmpty;
    // 有缓存先上屏，不盖转圈；无缓存才 loading
    if (!hasRows) _historyLoadingNotifier.value = true;
    try {
      await ref
          .read(roomLotteryLiveProvider(widget.roomId).notifier)
          .refreshDrawHistoryRows(_gameId);
      if (mounted && gen == _historyReadyGen) {
        _refreshHistoryRows();
      }
    } finally {
      if (mounted && gen == _historyReadyGen) {
        _historyLoadingNotifier.value = false;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // 根 build 不 setState：倒计时/键盘/面板各自 ValueNotifier + Consumer select
    final canBet = ref.watch(authSessionProvider.select((s) => s.canPlaceBet));
    final isTrialAccount = ref.watch(
      roomLotteryLiveProvider(widget.roomId).select((s) => s.isTrialAccount),
    );
    ref.listen<String?>(
      roomLotteryLiveProvider(widget.roomId).select((s) {
        final g = s.gameById(_gameId);
        if (g == null) return null;
        return normalizedGameChatMeta(
          currentIssue: g.currentIssue,
          previousIssue: g.previousIssue,
          previousResults: g.previousResults,
        );
      }),
      (prev, next) {
        if (_disposed || !mounted || next == null || prev == next) return;
        ref
            .read(roomLotteryLiveProvider(widget.roomId).notifier)
            .scheduleReconcileChatDraws(_gameId);
        _scheduleHistoryRowsRefresh();
      },
    );
    return AppPageScaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: Colors.white,
      body: ValueListenableBuilder<String>(
        valueListenable: _gameIdNotifier,
        builder: (context, activeGameId, _) {
          return Column(
        children: [
          Consumer(
            builder: (context, ref, _) {
              final gameName = ref.watch(
                roomLotteryLiveProvider(widget.roomId).select(
                  (s) => s.gameById(activeGameId)?.name ?? '',
                ),
              );
              return _ChatHeader(
                gameName: gameName,
                roomId: widget.roomId,
                onBack: () {
                  // Overlay 保活：离开前必须收起盘口，否则再进仍停在快捷下单
                  if (_panel == _BottomPanel.quickBet) {
                    _setPanel(_BottomPanel.none);
                    return;
                  }
                  if (_panel != _BottomPanel.none) {
                    _setPanel(_BottomPanel.none);
                  }
                  final close = widget.onClose;
                  if (close != null) {
                    close();
                    return;
                  }
                  final nav = Navigator.of(context);
                  if (nav.canPop()) {
                    nav.pop();
                    return;
                  }
                  final isHost = ref.read(authSessionProvider).isHostSide;
                  if (isHost) {
                    goHostLottery(context, widget.roomId);
                  } else {
                    goRoomLottery(context, widget.roomId);
                  }
                },
                onTapTitle: _openSwitchGame,
              );
            },
          ),
          _ChatGameStatusSection(
            key: ValueKey('chat-status-$activeGameId'),
            roomId: widget.roomId,
            gameId: activeGameId,
            topPanelListenable: _topPanelNotifier,
            historyExpandedListenable: _historyExpandedNotifier,
            onToggleHistory: _toggleHistoryPanel,
            onBetSlip: () {
              final next = _topPanelNotifier.value == _TopPanel.betSlip
                  ? _TopPanel.none
                  : _TopPanel.betSlip;
              _topPanelNotifier.value = next;
              _historyExpandedNotifier.value = false;
              if (next != _TopPanel.none) _markOverlayOpened();
              if (_panel != _BottomPanel.none) _setPanel(_BottomPanel.none);
              _fabSelectedNotifier.value = null;
            },
            onLongDragon: () {
              final open = _topPanelNotifier.value != _TopPanel.longDragon;
              _topPanelNotifier.value = open ? _TopPanel.longDragon : _TopPanel.none;
              _historyExpandedNotifier.value = false;
              if (open) _markOverlayOpened();
              if (_panel != _BottomPanel.none) _setPanel(_BottomPanel.none);
              _fabSelectedNotifier.value = null;
              if (open) unawaited(_loadLongDragon());
            },
          ),
          // 紧贴顶栏下方：不浮在聊天上，避免缝里透出消息
          _StatusDropdownSlot(
            roomId: widget.roomId,
            gameId: activeGameId,
            historyExpandedListenable: _historyExpandedNotifier,
            historyMountedListenable: _historyPanelMounted,
            topPanelListenable: _topPanelNotifier,
            rowsListenable: _historyDisplayRowsNotifier,
            historyLoadingListenable: _historyLoadingNotifier,
            betSlipsListenable: _betSlipsNotifier,
            longDragonRowsListenable: _longDragonRowsNotifier,
            longDragonLoadingListenable: _longDragonLoadingNotifier,
            onHistoryRetry: () => unawaited(_ensureHistoryPanelReady()),
            onHistoryEpochChange: _refreshHistoryRows,
            onCancelBetSlipRow: _cancelBetSlipRow,
          ),
          Expanded(
            child: Stack(
              clipBehavior: Clip.hardEdge,
              children: [
                // 消息区：仅监听 padding / 消息，不跟键盘面板联动重建
                Positioned.fill(
                  child: ValueListenableBuilder<bool>(
                    valueListenable: _chatHiddenNotifier,
                    builder: (_, hidden, __) {
                      if (hidden) return const SizedBox.shrink();
                      return ValueListenableBuilder<double>(
                        valueListenable: _dockPaddingNotifier,
                        builder: (_, bottomPad, __) {
                          return ValueListenableBuilder<bool>(
                            valueListenable: _messagesLoadingNotifier,
                            builder: (_, loading, __) {
                              return ValueListenableBuilder<List<ChatMessageModel>>(
                                valueListenable: _messagesNotifier,
                                builder: (_, messages, __) {
                                  if (loading && messages.isEmpty) {
                                    return const AppPageLoading();
                                  }
                                  final list = ListView.builder(
                                    reverse: true,
                                    controller: _scrollCtrl,
                                    cacheExtent: 720,
                                    addAutomaticKeepAlives: false,
                                    addRepaintBoundaries: true,
                                    findChildIndexCallback: _findChildIndex,
                                    padding: EdgeInsets.fromLTRB(
                                      12.w,
                                      12.h,
                                      56.w,
                                      bottomPad,
                                    ),
                                    itemCount: messages.length,
                                    itemBuilder: (_, i) {
                                      final m =
                                          messages[messages.length - 1 - i];
                                      return ChatMessageItem(
                                        key: ValueKey(stableChatItemKey(m)),
                                        message: m,
                                      );
                                    },
                                  );
                                  if (!loading || messages.isEmpty) {
                                    return list;
                                  }
                                  return Stack(
                                    children: [
                                      list,
                                      ColoredBox(
                                        color: Colors.white
                                            .withValues(alpha: 0.72),
                                        child: const AppPageLoading(),
                                      ),
                                    ],
                                  );
                                },
                              );
                            },
                          );
                        },
                      );
                    },
                  ),
                ),
                // 上滑离开底部时：右下角回到最新
                Positioned(
                  right: 12.w,
                  bottom: 0,
                  child: ValueListenableBuilder<double>(
                    valueListenable: _dockPaddingNotifier,
                    builder: (_, bottomPad, __) {
                      return Padding(
                        padding: EdgeInsets.only(bottom: bottomPad + 10.h),
                        child: ValueListenableBuilder<bool>(
                          valueListenable: _chatHiddenNotifier,
                          builder: (_, hidden, __) {
                            if (hidden) return const SizedBox.shrink();
                            return ValueListenableBuilder<_BottomPanel>(
                              valueListenable: _panelNotifier,
                              builder: (_, panel, __) {
                                if (panel == _BottomPanel.quickBet) {
                                  return const SizedBox.shrink();
                                }
                                return ValueListenableBuilder<bool>(
                                  valueListenable: _showJumpBottomNotifier,
                                  builder: (_, show, __) {
                                    return AnimatedOpacity(
                                      opacity: show ? 1 : 0,
                                      duration: const Duration(milliseconds: 160),
                                      child: IgnorePointer(
                                        ignoring: !show,
                                        child: Material(
                                          color: AppColors.navBlue,
                                          elevation: 3,
                                          shadowColor: Colors.black26,
                                          shape: const CircleBorder(),
                                          child: InkWell(
                                            customBorder: const CircleBorder(),
                                            onTap: _forceScrollToBottom,
                                            child: SizedBox(
                                              width: 40.w,
                                              height: 40.w,
                                              child: Icon(
                                                Icons.keyboard_arrow_down_rounded,
                                                size: 26.sp,
                                                color: Colors.white,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                );
                              },
                            );
                          },
                        ),
                      );
                    },
                  ),
                ),
                // 盘口全屏层：Positioned 必须是 Stack 直接子节点
                Positioned.fill(
                  child: ValueListenableBuilder<bool>(
                    valueListenable: _marketReadyNotifier,
                    builder: (_, marketReady, __) {
                      return ValueListenableBuilder<_BottomPanel>(
                        valueListenable: _panelNotifier,
                        builder: (_, panel, __) {
                          if (panel != _BottomPanel.quickBet || !marketReady) {
                            return const SizedBox.shrink();
                          }
                          return MarketBetPage(
                            key: ValueKey('market-$activeGameId'),
                            roomId: widget.roomId,
                            gameId: activeGameId,
                            embedded: true,
                            onBetStart: _publishOptimisticBet,
                            onBetFailed: _dropOptimisticBet,
                            onBetSuccess: (command, orderIds, content) {
                              final slip = content.trim().isNotEmpty ? content.trim() : command;
                              _completeOptimisticBet(command, orderIds);
                              _rememberSuccessfulBet(command);
                              _appendBetSlip(slip, orderIds: orderIds);
                            },
                          );
                        },
                      );
                    },
                  ),
                ),
                // 底部输入 dock：盘口模式由 MarketBetPage 自带底栏
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: ValueListenableBuilder<bool>(
                    valueListenable: _betBusy,
                    builder: (_, submitting, __) {
                      return ValueListenableBuilder<_BottomPanel>(
                        valueListenable: _panelNotifier,
                        builder: (_, panel, __) {
                          if (panel == _BottomPanel.quickBet) {
                            return const SizedBox.shrink();
                          }
                          return _ChatBetDock(
                            canBet: canBet,
                            isTrialAccount: isTrialAccount,
                            submitting: submitting,
                            panel: panel,
                            controller: _betCtrl,
                            onTapInput: () {
                              if (!canBet || !_acceptPanelToggle()) return;
                              if (_panel == _BottomPanel.keypad) {
                                _setPanel(_BottomPanel.none);
                              } else {
                                _setPanel(_BottomPanel.keypad);
                              }
                              _fabSelectedNotifier.value = null;
                              // 历史下拉保持展开，仅再点顶栏球号行才关
                            },
                            onToggleMenu: () {
                              if (!canBet || !_acceptPanelToggle()) return;
                              _setPanel(
                                panel == _BottomPanel.menu
                                    ? _BottomPanel.none
                                    : _BottomPanel.menu,
                              );
                              _fabSelectedNotifier.value = null;
                              // 历史下拉保持展开
                            },
                            onSend: _submitBet,
                            onInsert: _insertText,
                            onBackspace: _backspace,
                            onClearAll: _clearBetText,
                            onAction: _handleAction,
                            onMenuItem: _onMenuItem,
                          );
                        },
                      );
                    },
                  ),
                ),
                Positioned(
                  right: 0,
                  top: 40.h,
                  child: ValueListenableBuilder<bool>(
                    valueListenable: _historyExpandedNotifier,
                    builder: (_, historyOpen, __) {
                      if (historyOpen) return const SizedBox.shrink();
                      return ValueListenableBuilder<int?>(
                    valueListenable: _fabSelectedNotifier,
                    builder: (_, fabSelected, __) {
                      return _FloatingActions(
                        selectedIndex: fabSelected,
                        onSwitchGame: () async {
                          _fabSelectedNotifier.value = 0;
                          if (_panel == _BottomPanel.quickBet) {
                            _setPanel(_BottomPanel.none);
                          }
                          await _openSwitchGame();
                        },
                        onService: () {
                          _fabSelectedNotifier.value = 1;
                          if (_panel == _BottomPanel.quickBet) {
                            _setPanel(_BottomPanel.none);
                          }
                          final isHost =
                              ref.read(authSessionProvider).isHostSide;
                          if (isHost) {
                            // 房主必须进经营端客服，不能走会员 /member/cs
                            widget.onClose?.call();
                            context.go(RoutePaths.hostService(widget.roomId));
                            return;
                          }
                          pushLocalPage(
                            context,
                            CustomerServicePage(roomId: widget.roomId),
                          );
                        },
                        onRedPacket: () => _claimRedpack(),
                        onMarket: () {
                          final open = _panel != _BottomPanel.quickBet;
                          if (open) {
                            _setPanel(_BottomPanel.quickBet);
                          } else {
                            _setPanel(_BottomPanel.none);
                          }
                          _fabSelectedNotifier.value = open ? 3 : null;
                          _historyExpandedNotifier.value = false;
                          _topPanelNotifier.value = _TopPanel.none;
                        },
                      );
                    },
                  );
                    },
                  ),
                ),
                // 仅注单/长龙展开时：点聊天区关闭。历史下拉不盖遮罩，点输入框可正常下注。
                Positioned.fill(
                  child: ValueListenableBuilder<_TopPanel>(
                    valueListenable: _topPanelNotifier,
                    builder: (_, topPanel, __) {
                      if (topPanel == _TopPanel.none) {
                        return const SizedBox.shrink();
                      }
                      return GestureDetector(
                        onTap: _dismissOverlays,
                        behavior: HitTestBehavior.opaque,
                        child: const ColoredBox(color: Color(0x03000000)),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      );
        },
      ),
    );
  }
}

/// 底部输入 dock：浮在聊天列表上，带阴影，抬高可见区域
class _ChatBetDock extends StatelessWidget {
  const _ChatBetDock({
    required this.canBet,
    required this.isTrialAccount,
    required this.submitting,
    required this.panel,
    required this.controller,
    required this.onTapInput,
    required this.onToggleMenu,
    required this.onSend,
    required this.onInsert,
    required this.onBackspace,
    required this.onClearAll,
    required this.onAction,
    required this.onMenuItem,
  });

  final bool canBet;
  final bool isTrialAccount;
  final bool submitting;
  final _BottomPanel panel;
  final TextEditingController controller;
  final VoidCallback onTapInput;
  final VoidCallback onToggleMenu;
  final VoidCallback onSend;
  final ValueChanged<String> onInsert;
  final VoidCallback onBackspace;
  final VoidCallback onClearAll;
  final ValueChanged<String> onAction;
  final ValueChanged<String> onMenuItem;

  static const _trialDisabled = {'上分', '下分', '申请记录', '自助回水'};

  @override
  Widget build(BuildContext context) {
    final maxPanelH = BetKeypadPanel.panelHeight >
            BetActionMenuPanel.panelHeight(context)
        ? BetKeypadPanel.panelHeight
        : BetActionMenuPanel.panelHeight(context);
    final showPanel = canBet &&
        (panel == _BottomPanel.keypad || panel == _BottomPanel.menu);
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    final trialDisabled = isTrialAccount ? _trialDisabled : const <String>{};

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.only(bottom: bottomInset),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            BetInputBar(
              controller: controller,
              enabled: canBet,
              submitting: submitting,
              menuOpen: panel == _BottomPanel.menu,
              keypadOpen: panel == _BottomPanel.keypad,
              onTapInput: onTapInput,
              onToggleMenu: onToggleMenu,
              onSend: onSend,
            ),
            if (canBet)
              Offstage(
                offstage: !showPanel,
                child: ClipRect(
                  child: SizedBox(
                    height: maxPanelH,
                    width: double.infinity,
                    child: IndexedStack(
                      index: panel == _BottomPanel.menu ? 1 : 0,
                      sizing: StackFit.expand,
                      children: [
                        BetKeypadPanel(
                          enabled: canBet,
                          disabledActions: trialDisabled,
                          onInsert: onInsert,
                          onBackspace: onBackspace,
                          onClearAll: onClearAll,
                          onAction: onAction,
                        ),
                        BetActionMenuPanel(
                          onItemTap: onMenuItem,
                          disabledLabels: trialDisabled,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ChatHeader extends ConsumerWidget {
  const _ChatHeader({
    required this.gameName,
    required this.roomId,
    required this.onBack,
    required this.onTapTitle,
  });

  final String gameName;
  final String roomId;
  final VoidCallback onBack;
  final VoidCallback onTapTitle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wallet = ref.watch(
      roomLotteryLiveProvider(roomId).select(
        (s) => (s.points, s.turnover, s.winLoss, s.rebate),
      ),
    );
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.bgGradientStart, AppColors.primaryLight],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(4.w, 0, 12.w, 8.h),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              IconButton(
                icon: Icon(Icons.arrow_back_ios, size: 18.sp),
                onPressed: onBack,
              ),
              GestureDetector(
                onTap: onTapTitle,
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: EdgeInsets.only(right: 8.w),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        gameName,
                        style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w600),
                      ),
                      SizedBox(width: 2.w),
                      Icon(Icons.arrow_drop_down, size: 20.sp, color: AppColors.textPrimary),
                    ],
                  ),
                ),
              ),
              const Spacer(),
              Padding(
                padding: EdgeInsets.only(right: 28.w),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(width: 88.w, child: _statText('积分:${wallet.$1}')),
                        SizedBox(width: 72.w, child: _statText('流水:${wallet.$2}')),
                      ],
                    ),
                    SizedBox(height: 2.h),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(width: 88.w, child: _statText('输赢:${wallet.$3}')),
                        SizedBox(width: 72.w, child: _statText('回水:${wallet.$4}')),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statText(String text) {
    return Text(
      text,
      textAlign: TextAlign.left,
      style: TextStyle(fontSize: 11.sp, color: AppColors.textPrimary, height: 1.2),
    );
  }
}

/// 游戏状态条：只读当前 [gameId] 的 live 态，展示用短号（后4位）。
class _ChatGameStatusSection extends ConsumerWidget {
  const _ChatGameStatusSection({
    super.key,
    required this.roomId,
    required this.gameId,
    required this.topPanelListenable,
    required this.historyExpandedListenable,
    required this.onToggleHistory,
    required this.onBetSlip,
    required this.onLongDragon,
  });

  final String roomId;
  final String gameId;
  final ValueListenable<_TopPanel> topPanelListenable;
  final ValueListenable<bool> historyExpandedListenable;
  final VoidCallback onToggleHistory;
  final VoidCallback onBetSlip;
  final VoidCallback onLongDragon;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentIssue = ref.watch(
      roomLotteryLiveProvider(roomId).select((s) {
        final issue = s.gameById(gameId)?.currentIssue ?? '';
        return issue.isEmpty ? '' : compactIssueNo(issue);
      }),
    );
    if (currentIssue.isEmpty &&
        ref.read(roomLotteryLiveProvider(roomId)).gameById(gameId) == null) {
      return SizedBox(height: 56.h);
    }

    return _GameStatusBar(
      roomId: roomId,
      gameId: gameId,
      currentIssue: currentIssue,
      topPanelListenable: topPanelListenable,
      historyExpandedListenable: historyExpandedListenable,
      onToggleHistory: onToggleHistory,
      onBetSlip: onBetSlip,
      onLongDragon: onLongDragon,
    );
  }
}

/// 期号列宽固定，使「距封盘/封盘中」与下行第一个开奖球左对齐
class _StatusIssueColumn extends StatelessWidget {
  const _StatusIssueColumn({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: HistoryDrawLayout.issueW(),
      child: Text(
        label.isEmpty ? '--' : label,
        textAlign: TextAlign.center,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: HistoryDrawLayout.issueStyle(),
      ),
    );
  }
}

class _GameStatusBar extends StatelessWidget {
  const _GameStatusBar({
    required this.roomId,
    required this.gameId,
    required this.currentIssue,
    required this.topPanelListenable,
    required this.historyExpandedListenable,
    required this.onToggleHistory,
    required this.onBetSlip,
    required this.onLongDragon,
  });

  final String roomId;
  final String gameId;
  final String currentIssue;
  final ValueListenable<_TopPanel> topPanelListenable;
  final ValueListenable<bool> historyExpandedListenable;
  final VoidCallback onToggleHistory;
  final VoidCallback onBetSlip;
  final VoidCallback onLongDragon;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        historyExpandedListenable,
        topPanelListenable,
      ]),
      builder: (_, __) {
        final flushBottom = historyExpandedListenable.value ||
            topPanelListenable.value != _TopPanel.none;
        return Container(
          color: Colors.white,
          padding: EdgeInsets.fromLTRB(
            HistoryDrawLayout.hPad(),
            8.h,
            HistoryDrawLayout.hPad(),
            // 下拉展开时去掉底 padding，与面板顶边贴死
            flushBottom ? 0 : 8.h,
          ),
          child: Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _StatusIssueColumn(label: currentIssue),
                  SizedBox(width: HistoryDrawLayout.issueGap()),
                  Expanded(
                    child: LiveLotteryPeriodCountdownRow(
                      roomId: roomId,
                      gameId: gameId,
                      showIssue: false,
                      countdownColor: AppColors.countdownGreen,
                    ),
                  ),
                  ValueListenableBuilder<_TopPanel>(
                    valueListenable: topPanelListenable,
                    builder: (_, topPanel, __) {
                      return Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          GestureDetector(
                            onTap: onBetSlip,
                            behavior: HitTestBehavior.opaque,
                            child: _pillBtn('注单', active: topPanel == _TopPanel.betSlip),
                          ),
                          SizedBox(width: 6.w),
                          GestureDetector(
                            onTap: onLongDragon,
                            behavior: HitTestBehavior.opaque,
                            child: _pillBtn('长龙', active: topPanel == _TopPanel.longDragon),
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
              SizedBox(height: 6.h),
              SizedBox(
                height: HistoryDrawLayout.rowHeight(),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Pk10AlignRow(
                      issue: LiveLatestDrawIssueText(
                        roomId: roomId,
                        gameId: gameId,
                        compact: true,
                        emptyLabel: '--',
                        style: HistoryDrawLayout.issueStyle(),
                      ),
                      middle: LiveLatestDrawBalls(
                        roomId: roomId,
                        gameId: gameId,
                        expandSlots: true,
                        digitFontSize: HistoryDrawLayout.ballDigitSize(),
                        gap: HistoryDrawLayout.ballGap(),
                      ),
                      gy: LiveLatestDrawSumText(
                        roomId: roomId,
                        gameId: gameId,
                        prefix: '',
                        style: TextStyle(
                          fontSize: 11.sp,
                          height: 1.1,
                          color: AppColors.danger,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      dt: ValueListenableBuilder<bool>(
                        valueListenable: historyExpandedListenable,
                        builder: (_, expanded, __) {
                          return Icon(
                            expanded
                                ? Icons.keyboard_arrow_up
                                : Icons.keyboard_arrow_down,
                            color: AppColors.primary,
                            size: 18.sp,
                          );
                        },
                      ),
                    ),
                    Positioned.fill(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: onToggleHistory,
                        child: const ColoredBox(color: Color(0x00000000)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _pillBtn(String text, {bool active = false}) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
      decoration: BoxDecoration(
        color: active ? AppColors.navBlue : AppColors.navBlue.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(12.r),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11.sp,
          color: active ? Colors.white : AppColors.navBlue,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

class _FloatingActions extends StatelessWidget {
  const _FloatingActions({
    required this.onSwitchGame,
    required this.onService,
    required this.onRedPacket,
    required this.onMarket,
    this.selectedIndex,
  });

  final VoidCallback onSwitchGame;
  final VoidCallback onService;
  final VoidCallback onRedPacket;
  final VoidCallback onMarket;
  final int? selectedIndex;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        _fab(0, Icons.swap_vert, AppColors.navBlue, onSwitchGame),
        SizedBox(height: 10.h),
        _fab(1, Icons.headset_mic, AppColors.navBlue, onService),
        SizedBox(height: 10.h),
        _fab(2, Icons.redeem, const Color(0xFFFF6B8A), onRedPacket),
        SizedBox(height: 10.h),
        _fab(3, Icons.grid_view, AppColors.navBlue, onMarket),
      ],
    );
  }

  Widget _fab(int index, IconData icon, Color color, VoidCallback onTap) {
    final selected = selectedIndex == index;
    final size = 40.w;

    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        // 固定槽位，避免选中胶囊撑开把下面按钮顶下去
        height: size,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.centerRight,
          children: [
            if (selected)
              Positioned(
                right: 0,
                top: -6.h,
                bottom: -6.h,
                child: Container(
                  padding: EdgeInsets.fromLTRB(10.w, 6.h, 8.w, 6.h),
                  decoration: BoxDecoration(
                    color: const Color(0xFFD4E9F8),
                    borderRadius: BorderRadius.horizontal(left: Radius.circular(24.r)),
                  ),
                  alignment: Alignment.center,
                  child: SizedBox(width: size, height: size),
                ),
              ),
            Padding(
              padding: EdgeInsets.only(right: 8.w),
              child: Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: color.withValues(alpha: 0.35),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Icon(icon, color: Colors.white, size: 20.sp),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 顶栏正下方下拉槽：历史/注单/长龙紧贴状态栏，不浮在聊天上（避免缝里透消息）。
class _StatusDropdownSlot extends ConsumerWidget {
  const _StatusDropdownSlot({
    required this.roomId,
    required this.gameId,
    required this.historyExpandedListenable,
    required this.historyMountedListenable,
    required this.topPanelListenable,
    required this.rowsListenable,
    required this.historyLoadingListenable,
    required this.betSlipsListenable,
    required this.longDragonRowsListenable,
    required this.longDragonLoadingListenable,
    required this.onHistoryRetry,
    required this.onHistoryEpochChange,
    required this.onCancelBetSlipRow,
  });

  final String roomId;
  final String gameId;
  final ValueListenable<bool> historyExpandedListenable;
  final ValueListenable<bool> historyMountedListenable;
  final ValueListenable<_TopPanel> topPanelListenable;
  final ValueListenable<List<HistoryDrawRow>> rowsListenable;
  final ValueListenable<bool> historyLoadingListenable;
  final ValueListenable<List<BetSlipRow>> betSlipsListenable;
  final ValueListenable<List<LongDragonRow>?> longDragonRowsListenable;
  final ValueListenable<bool> longDragonLoadingListenable;
  final VoidCallback onHistoryRetry;
  final VoidCallback onHistoryEpochChange;
  final Future<void> Function(int index) onCancelBetSlipRow;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        historyExpandedListenable,
        historyMountedListenable,
        topPanelListenable,
      ]),
      builder: (_, __) {
        final hist = historyExpandedListenable.value;
        final top = topPanelListenable.value;
        if (!hist && top == _TopPanel.none) {
          return const SizedBox.shrink();
        }

        Widget panel;
        if (hist) {
          if (!historyMountedListenable.value) {
            return const SizedBox.shrink();
          }
          panel = _HistoryOverlayPanel(
            roomId: roomId,
            gameId: gameId,
            rowsListenable: rowsListenable,
            loadingListenable: historyLoadingListenable,
            onRetry: onHistoryRetry,
            onEpochChange: onHistoryEpochChange,
          );
        } else if (top == _TopPanel.betSlip) {
          panel = ValueListenableBuilder<List<BetSlipRow>>(
            valueListenable: betSlipsListenable,
            builder: (_, rows, __) {
              final issue = ref
                      .read(roomLotteryLiveProvider(roomId))
                      .gameById(gameId)
                      ?.currentIssue ??
                  '';
              final pending = rows
                  .where((r) => issue.isEmpty || r.issue == issue)
                  .toList();
              return BetSlipPanel(
                rows: pending,
                onCancelRow: onCancelBetSlipRow,
              );
            },
          );
        } else {
          panel = ValueListenableBuilder<bool>(
            valueListenable: longDragonLoadingListenable,
            builder: (_, loading, __) {
              if (loading &&
                  (longDragonRowsListenable.value?.isEmpty ?? true)) {
                return SizedBox(
                  height: LongDragonPanel.panelHeight(context),
                  child: const ColoredBox(
                    color: Colors.white,
                    child: AppPageLoading(),
                  ),
                );
              }
              return ValueListenableBuilder<List<LongDragonRow>?>(
                valueListenable: longDragonRowsListenable,
                builder: (_, rows, __) {
                  return LongDragonPanel(rows: rows ?? const []);
                },
              );
            },
          );
        }

        // 白底顶条盖住与状态栏的接缝，滚动时不会透出聊天
        return ColoredBox(
          color: Colors.white,
          child: panel,
        );
      },
    );
  }
}

/// 历史面板：仅在 epoch / 实时态变化时刷新行数据，不在每次 build 重算。
class _HistoryOverlayPanel extends ConsumerStatefulWidget {
  const _HistoryOverlayPanel({
    required this.roomId,
    required this.gameId,
    required this.rowsListenable,
    required this.loadingListenable,
    required this.onRetry,
    required this.onEpochChange,
  });

  final String roomId;
  final String gameId;
  final ValueListenable<List<HistoryDrawRow>> rowsListenable;
  final ValueListenable<bool> loadingListenable;
  final VoidCallback onRetry;
  final VoidCallback onEpochChange;

  @override
  ConsumerState<_HistoryOverlayPanel> createState() => _HistoryOverlayPanelState();
}

class _HistoryOverlayPanelState extends ConsumerState<_HistoryOverlayPanel> {
  Future<void> _onRefresh() async {
    await ref
        .read(roomLotteryLiveProvider(widget.roomId).notifier)
        .refreshDrawHistoryRows(widget.gameId);
    if (mounted) widget.onEpochChange();
  }

  Future<bool> _onLoadMore() async {
    final hasMore = await ref
        .read(roomLotteryLiveProvider(widget.roomId).notifier)
        .loadMoreDrawHistoryRows(widget.gameId);
    if (mounted) widget.onEpochChange();
    return hasMore;
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(
      roomLotteryLiveProvider(widget.roomId).select((s) => s.drawCacheEpoch),
      (_, __) {
        if (mounted) widget.onEpochChange();
      },
    );
    ref.listen(
      roomLotteryLiveProvider(widget.roomId).select((s) {
        final g = s.gameById(widget.gameId);
        if (g == null) return null;
        return (g.previousIssue, g.previousResults.join(','));
      }),
      (_, __) {
        if (mounted) widget.onEpochChange();
      },
    );
    return ValueListenableBuilder<bool>(
      valueListenable: widget.loadingListenable,
      builder: (_, loading, __) {
        return ValueListenableBuilder<List<HistoryDrawRow>>(
          valueListenable: widget.rowsListenable,
          builder: (_, rows, __) {
            return HistoryDrawPanel(
              rows: rows,
              loading: loading && rows.isEmpty,
              error: false,
              onRetry: widget.onRetry,
              onRefresh: _onRefresh,
              onLoadMore: _onLoadMore,
            );
          },
        );
      },
    );
  }
}
