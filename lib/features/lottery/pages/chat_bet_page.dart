import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../config/theme/app_colors.dart';
import '../../../core/utils/submit_guard.dart';
import '../../../data/models/chat_message_model.dart';
import '../../../data/models/lottery_game_model.dart';
import '../../../data/repositories/providers.dart';
import '../../../shared/widgets/emulator_safe_text_field.dart';
import '../../../shared/widgets/input_dialog.dart';
import '../../../shared/widgets/page_app_bar.dart';
import '../../auth/providers/auth_session_provider.dart';
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
import '../widgets/bet_input_bar.dart';
import '../widgets/bet_keypad_panel.dart';
import '../widgets/bet_slip_panel.dart';
import '../widgets/chat_message_item.dart';
import '../widgets/history_draw_panel.dart';
import '../widgets/live_period_widgets.dart';
import '../widgets/long_dragon_panel.dart';
import '../widgets/switch_game_dialog.dart';
import 'market_bet_page.dart';

enum _BottomPanel { none, keypad, menu, quickBet }
enum _TopPanel { none, betSlip, longDragon }

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
  final _panelNotifier = ValueNotifier<_BottomPanel>(_BottomPanel.none);
  final _topPanelNotifier = ValueNotifier<_TopPanel>(_TopPanel.none);
  final _historyExpandedNotifier = ValueNotifier(false);
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
  Timer? _draftSaveTimer;
  Timer? _historyRowsDebounce;
  bool _disposed = false;
  int _chatSubGen = 0;
  String _accountId = '';
  String? _lastTimelineSig;

  void _onScrollChanged() {
    if (!_scrollCtrl.hasClients) return;
    _pinnedToBottom = _scrollCtrl.offset <= 64;
  }

  /// reverse ListView 下 offset 0 即底部
  void _scrollToBottom({bool animated = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollCtrl.hasClients) return;
      const target = 0.0;
      if (animated) {
        _scrollCtrl.animateTo(
          target,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      } else {
        _scrollCtrl.jumpTo(target);
      }
    });
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
        ..write(m.drawRanks?.join(',') ?? '')
        ..write('|');
    }
    return buf.toString();
  }

  void _setMessages(List<ChatMessageModel> messages) {
    final maxVisible = ChatPushCache.maxVisibleChatMessages;
    final trimmed = messages.length > maxVisible
        ? messages.sublist(messages.length - maxVisible)
        : messages;
    final nextIds = trimmed.map((m) => m.id).toSet();
    if (setEquals(nextIds, _messageIds) &&
        trimmed.length == _messagesNotifier.value.length) {
      var same = true;
      for (var i = 0; i < trimmed.length; i++) {
        if (trimmed[i].id != _messagesNotifier.value[i].id) {
          same = false;
          break;
        }
      }
      if (same) return;
    }
    _messageIds
      ..clear()
      ..addAll(nextIds);
    _messagesNotifier.value = trimmed;
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

  /// 开奖推送：先 HTTP 回补缺口，再整表同步，避免稀疏 buffer 先上屏再闪成完整列表。
  Future<void> _syncDrawsAfterBackfill() async {
    if (_disposed || !mounted) return;
    final live = ref.read(roomLotteryLiveProvider(widget.roomId).notifier);
    if (ChatPushCache.instance.hasDrawGap(widget.roomId, _gameId)) {
      await live.reconcileChatDraws(_gameId);
      if (_disposed || !mounted) return;
    }
    _syncMessagesFromCache();
  }

  List<ChatMessageModel> _mergeLiveSeals(List<ChatMessageModel> timeline) {
    var maxDrawKey = 0;
    final sealedInTimeline = <int>{};
    final warnInTimeline = <int>{};
    for (final m in timeline) {
      final issue = extractIssue(m);
      if (issue == null || issue.isEmpty) continue;
      final key = issueCompareKey(issue);
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
    final extras = <ChatMessageModel>[];
    for (final m in _messagesNotifier.value) {
      if (m.type != ChatMessageType.system) continue;
      final issue = extractIssue(m);
      if (issue == null || issue.isEmpty) continue;
      final key = issueCompareKey(issue);
      if (key <= maxDrawKey) continue;
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
    return [...timeline, ...extras];
  }

  void _appendChatMessage(ChatMessageModel message) {
    if (!_messageIds.add(message.id)) return;
    final list = _messagesNotifier.value;
    final next = list.isEmpty ? [message] : [...list, message];
    final maxVisible = ChatPushCache.maxVisibleChatMessages;
    if (next.length > maxVisible) {
      final trimmed = next.sublist(next.length - maxVisible);
      _messageIds
        ..clear()
        ..addAll(trimmed.map((m) => m.id));
      _messagesNotifier.value = trimmed;
    } else {
      _messagesNotifier.value = next;
    }
    if (_pinnedToBottom) {
      _scrollToBottom();
    }
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

  void _dismissHistoryPanel() {
    if (_historyExpandedNotifier.value) {
      _historyExpandedNotifier.value = false;
    }
  }

  void _dismissOverlays() {
    _dismissTopPanel();
    _dismissHistoryPanel();
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
    );
    _appendChatMessage(message);
    ChatPushCache.instance.pushOnce(
      roomId: widget.roomId,
      dedupeKey: id,
      gameId: _gameId,
      message: message,
    );
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
        final playName =
            '${row['playName'] ?? row['play_name'] ?? row['playCode'] ?? ''}';
        final amount = row['amount'];
        final label = playName.isNotEmpty ? '$playName/$amount' : '$amount';
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
    final cache = ChatPushCache.instance;
    final live = ref.read(roomLotteryLiveProvider(widget.roomId).notifier);
    if (!cache.hasDrawsForGame(widget.roomId, _gameId) &&
        !live.isChatTimelineWarm(_gameId)) {
      return;
    }
    _messagesLoadingNotifier.value = false;
    _lastTimelineSig = null;
    _syncMessagesFromCache(forceScroll: true);
  }

  void _scheduleChatSync() {
    // 下注后已乐观更新聊天；WS 会推封盘/开奖，不再全量重拉时间线。
  }

  @override
  void initState() {
    super.initState();
    _accountId = ref.read(authSessionProvider).user?.id ?? '';
    _scrollCtrl.addListener(_onScrollChanged);
    _betCtrl.addListener(_scheduleBetDraftSave);
    _gameId = widget.gameId;
    _gameIdNotifier.value = widget.gameId;
    _hydrateMessagesFromCacheIfReady();
    _scheduleDockLayoutSync();
    final subGen = ++_chatSubGen;
    Future.microtask(() async {
      if (_disposed || subGen != _chatSubGen) return;
      unawaited(
        ref.read(roomLotteryLiveProvider(widget.roomId).notifier).ensureLoaded(),
      );
      if (_disposed || subGen != _chatSubGen) return;
      _chatPushSub?.cancel();
      _chatPushSub = ref
          .read(roomLotteryLiveProvider(widget.roomId).notifier)
          .chatPushes
          .listen((push) {
        if (_disposed || !mounted || push.gameId != _gameId) return;
        if (push.message.type == ChatMessageType.resultCard) {
          // 有缺口先回补再刷 UI，杜绝 5317 跳 5320 的中间态闪屏
          unawaited(_syncDrawsAfterBackfill());
        } else {
          _appendChatMessage(push.message);
        }
      });
      if (_disposed || subGen != _chatSubGen) {
        _chatPushSub?.cancel();
        _chatPushSub = null;
        return;
      }
      unawaited(_loadMessages());
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncDockLayout();
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
    _scrollCtrl.removeListener(_onScrollChanged);
    _scrollCtrl.dispose();
    _betCtrl.dispose();
    _messagesNotifier.dispose();
    _betSlipsNotifier.dispose();
    _messagesLoadingNotifier.dispose();
    _panelNotifier.dispose();
    _topPanelNotifier.dispose();
    _historyExpandedNotifier.dispose();
    _historyLoadingNotifier.dispose();
    _longDragonRowsNotifier.dispose();
    _longDragonLoadingNotifier.dispose();
    _fabSelectedNotifier.dispose();
    _marketReadyNotifier.dispose();
    _dockPaddingNotifier.dispose();
    _historyDisplayRowsNotifier.dispose();
    _chatHiddenNotifier.dispose();
    _betBusy.dispose();
    super.dispose();
  }

  /// 切彩种：不先清空列表（避免白屏闪一下），有缓存则一步替换，无缓存则遮罩加载。
  void _switchToGame(String gameId) {
    if (gameId == _gameId) return;
    _gameId = gameId;
    _gameIdNotifier.value = gameId;
    _lastTimelineSig = null;
    _messageIds.clear();
    _longDragonLoadedGameId = null;
    _longDragonRowsNotifier.value = null;

    final hasBufferedDraws = ChatPushCache.instance
        .hasDrawsForGame(widget.roomId, gameId);
    if (hasBufferedDraws) {
      _messagesLoadingNotifier.value = false;
      // 有缓存：一步换成新彩种时间线，后台静默对齐
      _syncMessagesFromCache(forceScroll: true, skipLiveMerge: true);
      unawaited(_loadMessages(forceReload: true, silent: true));
      return;
    }

    // 无缓存：旧列表暂留，遮罩转圈，数据就绪后一次替换（不经过空白态）
    _messagesLoadingNotifier.value = true;
    unawaited(_loadMessages(forceReload: true));
  }

  Future<void> _loadMessages({
    bool silent = false,
    bool forceReload = false,
  }) {
    return _msgLoadInflight ??= _loadMessagesImpl(
      silent: silent,
      forceReload: forceReload,
    ).whenComplete(() {
      _msgLoadInflight = null;
    });
  }

  Future<void> _loadMessagesImpl({
    bool silent = false,
    bool forceReload = false,
  }) async {
    final gen = ++_msgLoadGen;
    final liveNotifier =
        ref.read(roomLotteryLiveProvider(widget.roomId).notifier);

    final warm =
        !forceReload && liveNotifier.isChatTimelineWarm(_gameId);
    final hasCache = ChatPushCache.instance
        .hasDrawsForGame(widget.roomId, _gameId);
    // 已有内容上屏时后台刷新，不把列表换成转圈（防闪）
    final hasVisibleMessages = _messagesNotifier.value.isNotEmpty;
    if (!silent && !warm && !hasVisibleMessages && !hasCache) {
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

      if (!silent) {
        if (forceReload || (!warm && !hasCache)) {
          await liveNotifier.timelineForGameAsync(_gameId);
        }
        if (!mounted || gen != _msgLoadGen) return;
        _lastTimelineSig = null;
        _syncMessagesFromCache(forceScroll: true);
        await _restoreBetDraft();
        await _restoreBetSlipsFromServer();
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
    if (selected == null || !mounted) return;
    if (selected.id == _gameId) return;

    // Overlay 模式：交给大厅切换保活页，避免本页改 gameId 与 overlay 错位
    final switchViaHall = widget.onSwitchGame;
    if (switchViaHall != null) {
      switchViaHall(selected.id);
      return;
    }

    _switchToGame(selected.id);
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

  void _onMenuItem(String label) {
    _setPanel(_BottomPanel.none);
    if (label == '上分' || label == '下分') {
      _submitWalletApplication(label == '上分' ? 'UP' : 'DOWN');
      return;
    }
    final page = switch (label) {
      '申请记录' => const ApplyRecordsPage(),
      '积分账变' => const PointsChangePage(),
      '福利报表' || '自助回水' => const WelfareReportPage(),
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
    _submitLocked = true;
    _betBusy.value = true;
    try {
      final done = await _betGuard.run((requestId) async {
        final orderIds = await ref.read(lotteryRepositoryProvider).submitBet(
              roomId: widget.roomId,
              gameId: _gameId,
              command: command,
              requestId: requestId,
            );
        return orderIds;
      });
      if (done == null || !mounted) return;
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
      _appendLocalMessage(command, orderIds: done);
      _rememberSuccessfulBet(command);
      _appendBetSlip(command, orderIds: done);
      AppToast.success('下注成功');
      _scheduleChatSync();
    } catch (e) {
      AppToast.error(e.toString());
    } finally {
      _submitLocked = false;
      if (mounted) _betBusy.value = false;
    }
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
    HistoryDrawRow? liveHead;
    if (issue.isNotEmpty && balls.isNotEmpty) {
      liveHead = HistoryDrawRow(
        issue: issue,
        numbers: balls,
        summary: balls.length >= 2 ? '${balls[0] + balls[1]}' : '',
      );
    }
    return mergeDrawHistoryRows(
      base: rows,
      liveHead: liveHead,
      maxRows: HistoryDrawPanel.maxRows,
    );
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
    _historyLoadingNotifier.value = true;
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
    ref.listen<(String, int)?>(
      roomLotteryLiveProvider(widget.roomId).select((s) {
        final g = s.gameById(_gameId);
        if (g == null) return null;
        return (
          normalizedGameChatMeta(
            currentIssue: g.currentIssue,
            previousIssue: g.previousIssue,
            previousResults: g.previousResults,
          ),
          s.drawCacheEpoch,
        );
      }),
      (prev, next) {
        if (_disposed || !mounted || next == null) return;
        final prevMeta = prev?.$1;
        final nextMeta = next.$1;
        // 期号/开奖结果真变了才 reconcile；不要每次 epoch 整表刷聊天（那是 2 秒闪的源头）
        if (prevMeta != nextMeta) {
          ref
              .read(roomLotteryLiveProvider(widget.roomId).notifier)
              .scheduleReconcileChatDraws(_gameId);
          _scheduleHistoryRowsRefresh();
        } else if (prev == null || prev.$2 != next.$2) {
          // epoch 变了：若仍有缺口，禁止用稀疏 timeline 刷屏
          if (ChatPushCache.instance.hasDrawGap(widget.roomId, _gameId)) {
            unawaited(_syncDrawsAfterBackfill());
          } else {
            _syncMessagesFromCache();
          }
          _scheduleHistoryRowsRefresh();
        }
        if (_disposed || !mounted) return;
        if (_historyExpandedNotifier.value) {
          unawaited(
            ref
                .read(roomLotteryLiveProvider(widget.roomId).notifier)
                .refreshDrawHistoryRows(_gameId)
                .then((_) {
              if (mounted) _refreshHistoryRows();
            }),
          );
        }
      },
    );
    return AppPageScaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: const Color(0xFFF5F5F5),
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
            onToggleHistory: () {
              final next = !_historyExpandedNotifier.value;
              _historyExpandedNotifier.value = next;
              if (next) {
                _topPanelNotifier.value = _TopPanel.none;
                _refreshHistoryRows();
                unawaited(_ensureHistoryPanelReady());
              }
            },
            onBetSlip: () {
              final next = _topPanelNotifier.value == _TopPanel.betSlip
                  ? _TopPanel.none
                  : _TopPanel.betSlip;
              _topPanelNotifier.value = next;
              _historyExpandedNotifier.value = false;
              if (_panel != _BottomPanel.none) _setPanel(_BottomPanel.none);
              _fabSelectedNotifier.value = null;
            },
            onLongDragon: () {
              final open = _topPanelNotifier.value != _TopPanel.longDragon;
              _topPanelNotifier.value = open ? _TopPanel.longDragon : _TopPanel.none;
              _historyExpandedNotifier.value = false;
              if (_panel != _BottomPanel.none) _setPanel(_BottomPanel.none);
              _fabSelectedNotifier.value = null;
              if (open) unawaited(_loadLongDragon());
            },
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
                                    return const Center(
                                      child: CircularProgressIndicator(),
                                    );
                                  }
                                  final list = ListView.builder(
                                    reverse: true,
                                    controller: _scrollCtrl,
                                    cacheExtent: 400,
                                    addAutomaticKeepAlives: true,
                                    addRepaintBoundaries: true,
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
                                      return RepaintBoundary(
                                        child: ChatMessageItem(
                                          key: ValueKey(stableChatItemKey(m)),
                                          message: m,
                                        ),
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
                                        color: const Color(0xFFF5F5F5)
                                            .withValues(alpha: 0.72),
                                        child: const Center(
                                          child: CircularProgressIndicator(),
                                        ),
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
                            onBetSuccess: (command, orderIds) {
                              _appendLocalMessage(command);
                              _rememberSuccessfulBet(command);
                              _appendBetSlip(command, orderIds: orderIds);
                              _scheduleChatSync();
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
                              _historyExpandedNotifier.value = false;
                            },
                            onToggleMenu: () {
                              if (!canBet || !_acceptPanelToggle()) return;
                              _setPanel(
                                panel == _BottomPanel.menu
                                    ? _BottomPanel.none
                                    : _BottomPanel.menu,
                              );
                              _fabSelectedNotifier.value = null;
                              _historyExpandedNotifier.value = false;
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
                  child: ValueListenableBuilder<int?>(
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
                          _fabSelectedNotifier.value = null;
                        },
                        onService: () {
                          _fabSelectedNotifier.value = 1;
                          if (_panel == _BottomPanel.quickBet) {
                            _setPanel(_BottomPanel.none);
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
                  ),
                ),
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: ValueListenableBuilder<bool>(
                    valueListenable: _historyExpandedNotifier,
                    builder: (_, expanded, __) {
                      if (!expanded) return const SizedBox.shrink();
                      return _HistoryOverlayPanel(
                        roomId: widget.roomId,
                        gameId: activeGameId,
                        rowsListenable: _historyDisplayRowsNotifier,
                        loadingListenable: _historyLoadingNotifier,
                        onRetry: () => unawaited(_ensureHistoryPanelReady()),
                        onEpochChange: _refreshHistoryRows,
                      );
                    },
                  ),
                ),
                // 注单/长龙/历史展开时：点面板外区域关闭
                Positioned.fill(
                  child: ListenableBuilder(
                    listenable: Listenable.merge([
                      _topPanelNotifier,
                      _historyExpandedNotifier,
                    ]),
                    builder: (_, __) {
                      final showTop = _topPanelNotifier.value != _TopPanel.none;
                      final showHist = _historyExpandedNotifier.value;
                      if (!showTop && !showHist) {
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
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: ValueListenableBuilder<_TopPanel>(
                    valueListenable: _topPanelNotifier,
                    builder: (_, topPanel, __) {
                      switch (topPanel) {
                        case _TopPanel.betSlip:
                          return ValueListenableBuilder<List<BetSlipRow>>(
                            valueListenable: _betSlipsNotifier,
                            builder: (_, rows, __) => BetSlipPanel(
                              rows: rows,
                              onCancelRow: _cancelBetSlipRow,
                            ),
                          );
                        case _TopPanel.longDragon:
                          return ValueListenableBuilder<bool>(
                            valueListenable: _longDragonLoadingNotifier,
                            builder: (_, loading, __) {
                              if (loading &&
                                  (_longDragonRowsNotifier.value?.isEmpty ?? true)) {
                                return SizedBox(
                                  height: LongDragonPanel.panelHeight(context),
                                  child: const Center(child: CircularProgressIndicator()),
                                );
                              }
                              return ValueListenableBuilder<List<LongDragonRow>?>(
                                valueListenable: _longDragonRowsNotifier,
                                builder: (_, rows, __) {
                                  return LongDragonPanel(rows: rows ?? const []);
                                },
                              );
                            },
                          );
                        case _TopPanel.none:
                          return const SizedBox.shrink();
                      }
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

  @override
  Widget build(BuildContext context) {
    final maxPanelH = BetKeypadPanel.panelHeight >
            BetActionMenuPanel.panelHeight(context)
        ? BetKeypadPanel.panelHeight
        : BetActionMenuPanel.panelHeight(context);
    final showPanel = canBet &&
        (panel == _BottomPanel.keypad || panel == _BottomPanel.menu);
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;

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
                          onInsert: onInsert,
                          onBackspace: onBackspace,
                          onClearAll: onClearAll,
                          onAction: onAction,
                        ),
                        BetActionMenuPanel(onItemTap: onMenuItem),
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

    return ValueListenableBuilder<bool>(
      valueListenable: historyExpandedListenable,
      builder: (_, historyExpanded, __) {
        return ValueListenableBuilder<_TopPanel>(
          valueListenable: topPanelListenable,
          builder: (_, topPanel, __) {
            return _GameStatusBar(
              roomId: roomId,
              gameId: gameId,
              currentIssue: currentIssue,
              historyExpanded: historyExpanded,
              topPanel: topPanel,
              onToggleHistory: onToggleHistory,
              onBetSlip: onBetSlip,
              onLongDragon: onLongDragon,
            );
          },
        );
      },
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
      width: 40.w,
      child: Text(
        label.isEmpty ? '--' : label,
        style: TextStyle(
          fontSize: 12.sp,
          color: const Color(0xFF7A7A7A),
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

class _GameStatusBar extends StatelessWidget {
  const _GameStatusBar({
    required this.roomId,
    required this.gameId,
    required this.currentIssue,
    required this.historyExpanded,
    required this.topPanel,
    required this.onToggleHistory,
    required this.onBetSlip,
    required this.onLongDragon,
  });

  final String roomId;
  final String gameId;
  final String currentIssue;
  final bool historyExpanded;
  final _TopPanel topPanel;
  final VoidCallback onToggleHistory;
  final VoidCallback onBetSlip;
  final VoidCallback onLongDragon;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _StatusIssueColumn(label: currentIssue),
              SizedBox(width: 8.w),
              Expanded(
                child: LiveLotteryPeriodCountdownRow(
                  roomId: roomId,
                  gameId: gameId,
                  showIssue: false,
                ),
              ),
              GestureDetector(
                onTap: onBetSlip,
                child: _pillBtn('注单', active: topPanel == _TopPanel.betSlip),
              ),
              SizedBox(width: 6.w),
              GestureDetector(
                onTap: onLongDragon,
                child: _pillBtn('长龙', active: topPanel == _TopPanel.longDragon),
              ),
            ],
          ),
          SizedBox(height: 6.h),
          GestureDetector(
            onTap: onToggleHistory,
            behavior: HitTestBehavior.opaque,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: 40.w,
                  child: LiveLatestDrawIssueText(
                    roomId: roomId,
                    gameId: gameId,
                    compact: true,
                    emptyLabel: '--',
                    style: TextStyle(
                      fontSize: 12.sp,
                      color: const Color(0xFF7A7A7A),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                SizedBox(width: 8.w),
                Expanded(
                  child: LiveLatestDrawBalls(
                    roomId: roomId,
                    gameId: gameId,
                    ballSize: 18.w,
                  ),
                ),
                LiveLatestDrawSumText(roomId: roomId, gameId: gameId),
                Icon(
                  historyExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                  color: AppColors.primary,
                  size: 20.sp,
                ),
              ],
            ),
          ),
        ],
      ),
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
  @override
  Widget build(BuildContext context) {
    ref.listen(
      roomLotteryLiveProvider(widget.roomId).select((s) => s.drawCacheEpoch),
      (_, __) => widget.onEpochChange(),
    );
    ref.listen(
      roomLotteryLiveProvider(widget.roomId).select((s) {
        final g = s.gameById(widget.gameId);
        if (g == null) return null;
        return (g.previousIssue, g.previousResults.join(','));
      }),
      (_, __) => widget.onEpochChange(),
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
            );
          },
        );
      },
    );
  }
}
