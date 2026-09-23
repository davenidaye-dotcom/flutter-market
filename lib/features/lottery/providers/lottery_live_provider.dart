import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/flyroom_ws_client.dart';
import '../../../core/network/session_store.dart';
import '../../../core/testing/regression_test_flags.dart';
import '../../../data/models/chat_message_model.dart';
import '../../../data/models/lottery_game_model.dart';
import '../../../data/repositories/providers.dart';
import '../../auth/providers/auth_session_provider.dart';
import '../engine/lottery_period_engine.dart';
import '../services/chat_push_cache.dart';
import '../utils/bet_receipt_format.dart';
import '../utils/draw_history_rows.dart';
import '../utils/lottery_period_ui.dart';
import '../utils/chat_timeline.dart';
import '../widgets/history_draw_panel.dart';

export '../services/chat_push_cache.dart' show LotteryChatPush;

/// Room lottery live session shared by hall / chat / market.
class RoomLotteryLiveState {
  const RoomLotteryLiveState({
    this.games = const [],
    this.announcement = '\u6b22\u8fce\u8fdb\u5165\u672c\u623f\u95f4',
    this.points = 0,
    this.turnover = 0,
    this.winLoss = 0,
    this.rebate = 0,
    this.isTrialAccount = false,
    this.ready = false,
    this.loadError,
    this.drawCacheEpoch = 0,
    this.uiTick = 0,
    this.interactionPaused = false,
    this.betConfirm = false,
  });

  final List<LotteryGameModel> games;
  final String announcement;
  final int points;
  final int turnover;
  final int winLoss;
  final int rebate;
  /// 本房会员 playMode=TRIAL（试玩号）
  final bool isTrialAccount;
  final bool ready;
  final String? loadError;
  /// 本地开奖缓存变更代次，供历史面板刷新
  final int drawCacheEpoch;
  /// 房间级 1s 节拍：倒计时 UI 只监听此字段，避免 N 个 Timer + 全量 games 重建
  final int uiTick;
  /// 聊天/键盘交互中：暂停 ticker、磁盘落盘
  final bool interactionPaused;
  /// 房主「下注确认」开关
  final bool betConfirm;

  LotteryGameModel? gameById(String id) {
    for (final g in games) {
      if (g.id == id) return g;
    }
    return null;
  }

  RoomLotteryLiveState copyWith({
    List<LotteryGameModel>? games,
    String? announcement,
    int? points,
    int? turnover,
    int? winLoss,
    int? rebate,
    bool? isTrialAccount,
    bool? ready,
    String? loadError,
    bool clearLoadError = false,
    int? drawCacheEpoch,
    int? uiTick,
    bool? interactionPaused,
    bool? betConfirm,
  }) {
    return RoomLotteryLiveState(
      games: games ?? this.games,
      announcement: announcement ?? this.announcement,
      points: points ?? this.points,
      turnover: turnover ?? this.turnover,
      winLoss: winLoss ?? this.winLoss,
      rebate: rebate ?? this.rebate,
      isTrialAccount: isTrialAccount ?? this.isTrialAccount,
      ready: ready ?? this.ready,
      loadError: clearLoadError ? null : (loadError ?? this.loadError),
      drawCacheEpoch: drawCacheEpoch ?? this.drawCacheEpoch,
      uiTick: uiTick ?? this.uiTick,
      interactionPaused: interactionPaused ?? this.interactionPaused,
      betConfirm: betConfirm ?? this.betConfirm,
    );
  }
}

class RoomLotteryLiveNotifier extends StateNotifier<RoomLotteryLiveState> {
  RoomLotteryLiveNotifier(this._ref, this.roomId) : super(const RoomLotteryLiveState());

  final Ref _ref;
  final String roomId;
  final _engine = LotteryPeriodEngine();

  Timer? _ticker;
  Future<void>? _loading;
  FlyroomWsClient? _ws;
  StreamSubscription? _wsSub;
  bool _wsConnected = false;
  bool _wsDisposed = false;
  Timer? _wsReconnectTimer;
  int _wsReconnectAttempt = 0;
  bool _wsIsHost = false;
  int _wsConnectGen = 0;
  Future<void>? _wsConnectInflight;
  final Set<String> _wsSubscribedTopics = {};
  final _chatPushController = StreamController<LotteryChatPush>.broadcast();
  bool _drawHistoryPreloaded = false;
  Future<void>? _drawHistoryPreload;
  final Map<String, Future<void>> _drawLoadByGame = {};
  final Map<String, Future<void>> _gameTimelinePreloadByGame = {};
  final Map<String, List<HistoryDrawRow>> _apiDrawRowsByGame = {};
  Timer? _gamesRefreshDebounce;
  Future<void>? _gamesRefreshInflight;
  Timer? _drawCacheBumpDebounce;
  final Map<String, Timer> _reconcileDebounceByGame = {};
  int _uiInteractionPause = 0;
  Timer? _drawPollDebounce;
  Timer? _drawWatchdog;
  Completer<void>? _periodSyncCompleter;
  Set<String>? _periodSyncPending;
  /// 进聊天页装载中：禁止封盘抢先上屏。
  final Set<String> _chatBootstrapping = {};
  /// 防 SETTLE_RESULT 重复乐观加分（多实例/重推）
  final Set<String> _settleOptimisticApplied = {};
  /// WIN_LIST 若早于开奖卡片到达，先挂起，等 DRAW 上屏后再推，避免核对插在开奖上方闪一下。
  final Map<String, _PendingWinList> _pendingWinListByKey = {};

  Stream<LotteryChatPush> get chatPushes => _chatPushController.stream;

  bool get drawHistoryPreloaded => _drawHistoryPreloaded;

  bool get _interactionPaused => _uiInteractionPause > 0;

  // ── interaction pause ──

  void pauseForInteraction() {
    _uiInteractionPause++;
    ChatPushCache.instance.suspendPersist();
    if (_uiInteractionPause == 1) {
      state = state.copyWith(interactionPaused: true);
    }
  }

  void resumeFromInteraction() {
    if (_uiInteractionPause > 0) _uiInteractionPause--;
    if (_uiInteractionPause == 0) {
      ChatPushCache.instance.resumePersist();
      state = state.copyWith(interactionPaused: false);
      _ensureTickerRunning();
    }
  }

  // ── public period APIs ──

  int countdownFor(String gameId) =>
      _engine.countdownFor(gameId, DateTime.now());

  LotteryGameModel? displayGameFor(String gameId) {
    final named = state.gameById(gameId);
    final g = _engine.displayGame(gameId, DateTime.now());
    if (g.id.isEmpty && named == null) return null;
    return g.copyWith(
      name: named?.name.isNotEmpty == true ? named!.name : g.name,
    );
  }

  Future<void> ensureLoaded() {
    if (state.ready && state.loadError == null) {
      _ensureTickerRunning();
      if (!_wsConnected && !_wsDisposed) {
        unawaited(_reconnectIfNeeded());
      }
      return Future.value();
    }
    return _loading ??= _load();
  }

  Future<void> _reconnectIfNeeded() async {
    if (!mounted || _wsConnected || _wsDisposed || state.games.isEmpty) return;
    final isHost = _ref.read(authSessionProvider).isHostSide;
    await _connectWs(isHost: isHost, games: state.games, isReconnect: true);
  }

  /// 冷启动 / 重进房：等全部彩种 WS 首期 tick，避免 HTTP 整期秒数闪一下。
  Future<void> awaitPeriodLiveSync({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    if (_engine.allWsSynced) return;
    final deadline = DateTime.now().add(timeout);
    while (mounted && !_engine.allWsSynced) {
      if (DateTime.now().isAfter(deadline)) break;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }

  void _completePeriodSync() {
    _periodSyncPending = null;
    final c = _periodSyncCompleter;
    if (c != null && !c.isCompleted) c.complete();
    _periodSyncCompleter = null;
  }

  Future<void> _finishPeriodLiveSyncInBackground() async {
    await awaitPeriodLiveSync();
    _completePeriodSync();
  }

  bool isGameWsSynced(String gameId) => _engine.isGameWsSynced(gameId);

  Future<void> retryLoad() async {
    _loading = null;
    _drawHistoryPreload = null;
    _drawHistoryPreloaded = false;
    _gameTimelinePreloadByGame.clear();
    _engine.reset();
    state = const RoomLotteryLiveState();
    await ensureLoaded();
  }

  void debugInjectWsEvent(Map<String, dynamic> event) {
    _onWsEvent(event);
  }

  void applyServerPatch(LotteryGameModel patch, {DateTime? sealAt}) {
    if (!mounted) return;
    _engine.patchGame(patch, DateTime.now());
    _publishGames();
    _ensureTickerRunning();
  }

  Future<void> refreshWallet() async {
    if (!mounted) return;
    if (_ref.read(authSessionProvider).isHostSide) {
      try {
        final dash = await _ref.read(ownerRepositoryProvider).getDashboard();
        state = state.copyWith(
          points: _toInt(dash['balance']),
          turnover: _toInt(dash['turnover']),
          winLoss: _toInt(dash['todayProfitLoss']),
        );
      } catch (_) {}
      return;
    }
    try {
      final wallet = await _ref.read(walletRepositoryProvider).getSummary(roomId);
      state = state.copyWith(
        points: wallet.availablePoints.toInt(),
        turnover: wallet.todayTurnover.toInt(),
        winLoss: wallet.todayWinLoss.toInt(),
        rebate: wallet.pendingRebate.toInt(),
        isTrialAccount: wallet.isTrial,
      );
    } catch (_) {}
  }

  // ── draw history (chat cache only, never mutates engine) ──

  List<HistoryDrawRow> drawHistoryForGame(String gameId) {
    final api = _apiDrawRowsByGame[gameId] ?? const <HistoryDrawRow>[];
    final local = ChatPushCache.instance.historyDrawRowsForGame(
      roomId,
      gameId,
      maxRows: ChatPushCache.drawHistoryLimit,
    );
    return mergeHistorySources([api, local])
        .take(HistoryDrawPanel.maxRows)
        .toList(growable: false);
  }

  Future<void> refreshDrawHistoryRows(String gameId) async {
    if (gameId.isEmpty) return;
    final inflight = _drawLoadByGame[gameId];
    if (inflight != null) {
      await inflight;
      if (!_cacheNeedsDrawBackfill(gameId)) return;
    }
    final future = _fetchDrawHistoryRowsFromApi(gameId);
    _drawLoadByGame[gameId] = future;
    try {
      await future;
    } finally {
      _drawLoadByGame.remove(gameId);
    }
  }

  Future<void> _fetchDrawHistoryRowsFromApi(String gameId) async {
    try {
      final isHost = _ref.read(authSessionProvider).isHostSide;
      final raw = await _ref.read(lotteryRepositoryProvider).getDrawHistory(
            gameId: gameId,
            asOwner: isHost,
            pageSize: ChatPushCache.drawHistoryLimit,
          );
      if (!mounted) return;
      final rows = drawHistoryRowsFromApi(raw);
      if (rows.isEmpty) return;
      _apiDrawRowsByGame[gameId] = rows;
      applyServerDraws(
        gameId: gameId,
        draws: drawRowsToResultMessages(rows, gameId: gameId),
        bumpCache: false,
      );
      _bumpDrawCache();
    } catch (_) {}
  }

  void applyServerDraws({
    required String gameId,
    required List<ChatMessageModel> draws,
    bool bumpCache = true,
  }) {
    if (draws.isEmpty) return;
    ChatPushCache.instance.syncDrawsFromApi(
      roomId: roomId,
      gameId: gameId,
      draws: draws,
    );
    for (final d in draws) {
      final issue = extractIssue(d);
      if (issue != null && issue.isNotEmpty) {
        _flushPendingWinList(gameId, issue);
      }
    }
    if (bumpCache) _bumpDrawCache();
  }

  Future<void> ensureDrawHistoryForGame(String gameId) async {
    await refreshDrawHistoryRows(gameId);
  }

  int _maxDrawIssueKeyInCache(String gameId) {
    var maxKey = 0;
    for (final m in ChatPushCache.instance.bufferedForGame(roomId, gameId)) {
      if (m.type != ChatMessageType.resultCard) continue;
      final issue = extractIssue(m);
      if (issue == null || issue.isEmpty) continue;
      // 完整期号比大小，勿用后四位
      final n = int.tryParse(issue.trim()) ?? 0;
      if (n > maxKey) maxKey = n;
    }
    return maxKey;
  }

  bool _cacheNeedsDrawBackfill(String gameId) {
    final cache = ChatPushCache.instance;
    if (cache.hasDrawGap(roomId, gameId)) return true;
    final g = _engine.gameById(gameId) ?? state.gameById(gameId);
    if (g == null) return false;
    final prevIssue = g.previousIssue ?? '';
    if (prevIssue.isEmpty) return false;
    if (!cache.hasDrawForIssue(roomId, gameId, prevIssue)) return true;
    final prevKey = int.tryParse(prevIssue.trim()) ?? 0;
    if (prevKey <= 0) return false;
    final cacheMax = _maxDrawIssueKeyInCache(gameId);
    return prevKey > cacheMax;
  }

  /// 顶栏期号已前进但聊天缓存缺开奖时，用 engine 态 + HTTP 历史回补。
  Future<void> reconcileChatDraws(String gameId) async {
    if (gameId.isEmpty || !mounted) return;
    if (_engine.hasHeldDraws(gameId)) return;
    final g = _engine.gameById(gameId) ?? state.gameById(gameId);
    if (g == null) return;

    final prevIssue = g.previousIssue ?? '';
    final ranks = g.previousResults;
    if (prevIssue.isNotEmpty &&
        ranks.isNotEmpty &&
        !ChatPushCache.instance.hasDrawForIssue(roomId, gameId, prevIssue)) {
      _pushDrawChat(gameId, prevIssue, ranks);
    }

    if (!_cacheNeedsDrawBackfill(gameId)) return;
    await _fetchDrawHistoryRowsFromApi(gameId);
  }

  void scheduleReconcileChatDraws(String gameId) {
    if (gameId.isEmpty) return;
    _reconcileDebounceByGame[gameId]?.cancel();
    _reconcileDebounceByGame[gameId] = Timer(const Duration(milliseconds: 600), () {
      _reconcileDebounceByGame.remove(gameId);
      if (!mounted) return;
      unawaited(reconcileChatDraws(gameId));
    });
  }

  void _bumpDrawCache() {
    if (!mounted) return;
    _drawCacheBumpDebounce?.cancel();
    _drawCacheBumpDebounce = Timer(const Duration(milliseconds: 400), () {
      _drawCacheBumpDebounce = null;
      if (!mounted) return;
      state = state.copyWith(drawCacheEpoch: state.drawCacheEpoch + 1);
    });
  }

  // ── chat timeline ──

  Future<void> ensureDrawHistoryPreloaded() async {
    if (_drawHistoryPreloaded) return;
    if (!state.ready) await ensureLoaded();
    if (!mounted || !state.ready || state.games.isEmpty) return;
    try {
      await (_drawHistoryPreload ??= _preloadAllGameTimelines());
    } finally {
      if (!_drawHistoryPreloaded) {
        _drawHistoryPreload = null;
      }
    }
  }

  Future<void> ensureGameTimelinePreloaded(String gameId) async {
    if (gameId.isEmpty) return;
    await ensureChatBufferLoaded();
    await ensureDrawHistoryPreloaded();
    // 仍可能落后：单彩种再拉一次 15 期（暖也不能跳过历史核对）
    await _preloadGameTimeline(gameId);
  }

  Future<void> ensureChatBufferLoaded() =>
      ChatPushCache.instance.ensureRoomLoaded(roomId);

  List<ChatMessageModel> bufferedChatForGame(String gameId) {
    return ChatPushCache.instance.bufferedForGame(roomId, gameId);
  }

  List<ChatMessageModel> timelineForGame(String gameId) {
    return ChatPushCache.instance.timelineForGame(
      roomId,
      gameId,
      syntheticSeals: false,
    );
  }

  List<ChatMessageModel> freshTimelineForGame(String gameId) {
    return ChatPushCache.instance.freshTimelineForGame(
      roomId,
      gameId,
      syntheticSeals: false,
    );
  }

  Future<List<ChatMessageModel>> timelineForGameAsync(String gameId) {
    return ChatPushCache.instance.timelineForGameAsync(
      roomId,
      gameId,
      syntheticSeals: false,
    );
  }

  Future<void> prepareChatTimeline(
    String gameId, {
    bool forceNetwork = false,
  }) async {
    if (gameId.isEmpty) return;
    _chatBootstrapping.add(gameId);
    try {
      await ensureChatBufferLoaded();

      // 先开奖后消息：核对依赖开奖卡；HTTP 必须打，与本地缓存无关。
      await refreshDrawHistoryRows(gameId);
      if (!mounted) return;

      final cache = ChatPushCache.instance;
      if (!cache.hasDrawsForGame(roomId, gameId)) {
        cache.clearLiveDedupe(roomId, gameId);
        cache.purgeSystemMessagesForGame(roomId, gameId);
      }

      await loadChatMessagesFromServer(gameId);
      if (!mounted) return;

      if (forceNetwork && !isChatTimelineWarm(gameId)) {
        await refreshDrawHistoryRows(gameId);
        if (!mounted) return;
        await loadChatMessagesFromServer(gameId);
      }
    } finally {
      _chatBootstrapping.remove(gameId);
    }
  }

  bool isChatTimelineWarm(String gameId) {
    if (gameId.isEmpty) return false;
    final cache = ChatPushCache.instance;
    if (!cache.hasDrawsForGame(roomId, gameId)) return false;
    if (cache.hasDrawGap(roomId, gameId)) return false;
    // 相对顶栏 previousIssue 落后则不算暖，必须 HTTP 回补（防 3844 当 3952 用）。
    if (_cacheNeedsDrawBackfill(gameId)) return false;
    final timeline =
        cache.timelineForGame(roomId, gameId, syntheticSeals: false);
    final g = _engine.gameById(gameId) ?? state.gameById(gameId);
    if (g != null &&
        !isDrawTimelineFresh(
          timeline,
          g.currentIssue,
          previousIssue: g.previousIssue,
        )) {
      return false;
    }
    final drawCount =
        timeline.where((m) => m.type == ChatMessageType.resultCard).length;
    return drawCount >= 1;
  }

  Future<void> loadChatMessagesFromServer(String gameId) async {
    try {
      final isHost = _ref.read(authSessionProvider).isHostSide;
      final msgs = await _ref.read(lotteryRepositoryProvider).getChatMessages(
            roomId: roomId,
            gameId: gameId,
            asOwner: isHost,
            limit: ChatPushCache.chatHistoryIssueLimit,
          );
      if (!mounted) return;
      _ingestServerChatMessages(gameId, msgs);
      _bumpDrawCache();
    } catch (_) {}
  }

  Future<void> loadAllChatMessagesFromServer() async {
    try {
      final grouped = await _ref
          .read(lotteryRepositoryProvider)
          .getAllRoomDrawMessages(
            roomId: roomId,
            limit: ChatPushCache.chatHistoryIssueLimit,
          );
      if (!mounted) return;
      for (final entry in grouped.entries) {
        _ingestServerChatMessages(entry.key, entry.value);
      }
      _bumpDrawCache();
    } catch (_) {}
  }

  void _ingestServerChatMessages(
    String gameId,
    List<ChatMessageModel> msgs,
  ) {
    if (msgs.isEmpty) return;
    final cache = ChatPushCache.instance;
    // 先开奖卡、再其它、最后中奖核对：同批 HTTP 内也能 flush pending。
    final ordered = [...msgs]..sort((a, b) {
        int rank(ChatMessageModel m) {
          if (m.type == ChatMessageType.resultCard) return 0;
          if (m.type == ChatMessageType.winCheck) return 2;
          return 1;
        }

        return rank(a).compareTo(rank(b));
      });
    for (final m in ordered) {
      final issue = extractIssue(m);
      // 无对应开奖卡片的中奖核对先挂起，避免核对先于开奖上屏。
      if (m.type == ChatMessageType.winCheck &&
          issue != null &&
          issue.isNotEmpty &&
          !cache.hasDrawForIssue(roomId, gameId, issue)) {
        final key = winListChatMessageId(gameId, issue);
        final pendingKey = '$gameId|${issueCompareKey(issue)}';
        _pendingWinListByKey[pendingKey] = _PendingWinList(
          gameType: gameId,
          dedupeKey: key,
          message: m.id.isNotEmpty ? m : m.copyWith(id: key),
        );
        continue;
      }
      final String key;
      if (m.type == ChatMessageType.resultCard &&
          issue != null &&
          issue.isNotEmpty) {
        key = drawChatMessageId(gameId, issue);
      } else {
        key = m.id.isNotEmpty
            ? m.id
            : 'api-${m.type.name}-${issue ?? ''}-${m.content.hashCode}';
      }
      cache.pushOnce(
        roomId: roomId,
        dedupeKey: key,
        gameId: gameId,
        message: m,
      );
      if (m.type == ChatMessageType.resultCard &&
          issue != null &&
          issue.isNotEmpty) {
        _flushPendingWinList(gameId, issue);
      }
    }
    _dropChatOlderThanServerWindow(gameId, msgs);
  }

  /// 进房历史以服务器这批期号为准，丢掉更早的本地消息。
  void _dropChatOlderThanServerWindow(
    String gameId,
    List<ChatMessageModel> msgs,
  ) {
    String? oldest;
    for (final m in msgs) {
      final issue = extractIssue(m);
      if (issue == null || issue.isEmpty) continue;
      if (oldest == null || compareIssueNo(issue, oldest) < 0) {
        oldest = issue;
      }
    }
    if (oldest == null) return;
    ChatPushCache.instance.dropOlderThanIssue(
      roomId: roomId,
      gameId: gameId,
      oldestIssue: oldest,
    );
  }

  Future<void> _preloadGameTimeline(String gameId) async {
    if (gameId.isEmpty || !mounted) return;

    final inflight = _gameTimelinePreloadByGame[gameId];
    if (inflight != null) {
      await inflight;
      return;
    }

    final future = _preloadGameTimelineImpl(gameId);
    _gameTimelinePreloadByGame[gameId] = future;
    try {
      await future;
    } finally {
      if (identical(_gameTimelinePreloadByGame[gameId], future)) {
        _gameTimelinePreloadByGame.remove(gameId);
      }
    }
  }

  Future<void> _preloadGameTimelineImpl(String gameId) async {
    if (!mounted) return;
    // 开奖始终 HTTP 覆盖；消息也始终拉（暖只表示开奖够用，不能挡核对/下注）。
    await refreshDrawHistoryRows(gameId);
    if (!mounted) return;
    await loadChatMessagesFromServer(gameId);
  }

  Future<void> _preloadAllGameTimelines() async {
    if (!mounted) return;
    await ChatPushCache.instance.ensureRoomLoaded(roomId);
    final gameIds = state.games
        .map((g) => g.id)
        .where((id) => id.isNotEmpty)
        .toList(growable: false);
    if (gameIds.isEmpty) {
      if (mounted) _drawHistoryPreloaded = true;
      return;
    }

    try {
      final isHost = _ref.read(authSessionProvider).isHostSide;
      // 先开奖再消息，避免并行竞态把核对挂起后忘了 flush。
      await Future.wait(gameIds.map(refreshDrawHistoryRows));
      if (!mounted) return;
      if (isHost) {
        await Future.wait(gameIds.map(loadChatMessagesFromServer));
      } else {
        await loadAllChatMessagesFromServer();
      }
    } catch (_) {}

    if (mounted) {
      _drawHistoryPreloaded = true;
      _bumpDrawCache();
    }
  }

  // ── load / HTTP refresh ──

  Future<void> _load() async {
    final warm = _engine.hasLiveState;
    try {
      if (!warm) _engine.reset();
      final isHost = _ref.read(authSessionProvider).isHostSide;
      final games = await _ref
          .read(lotteryRepositoryProvider)
          .getGames(roomId, asOwner: isHost);
      if (!mounted) return;

      final now = DateTime.now();
      if (warm) {
        _engine.syncCatalog(games, now);
        if (!state.ready) {
          // 保留已有积分等字段，勿 new State 清零
          state = state.copyWith(games: _engine.games, ready: true, clearLoadError: true);
        } else {
          _publishGames();
        }
        _ensureTickerRunning();
        if (!_wsConnected) {
          unawaited(_loadMetaAndWs(isHost: isHost, games: games));
        } else if (!isHost) {
          // WS 已连时仍刷新钱包，避免顶栏积分过期
          unawaited(refreshWallet());
        }
        _syncWsSubscriptions();
        return;
      }

      _engine.bootstrap(games, now);
      _periodSyncPending = games
          .map((g) => g.id)
          .where((id) => id.isNotEmpty)
          .toSet();
      _periodSyncCompleter = Completer<void>();
      // 钱包/公告/仪表盘/WS 首 tick 全部后台；HTTP 彩种一到就 ready，避免登录后一直转圈
      unawaited(_loadMetaAndWs(isHost: isHost, games: games));
      if (!mounted) return;
      state = state.copyWith(
        games: _engine.games,
        ready: true,
        clearLoadError: true,
      );
      _ensureTickerRunning();
      if (!_ref.read(regressionSkipLiveWsProvider)) {
        unawaited(_finishPeriodLiveSyncInBackground());
      } else {
        _completePeriodSync();
      }
      if (games.any((g) => g.previousResults.isEmpty)) {
        _scheduleRefreshGamesFromServer();
      }
      _drawHistoryPreload = null;
      _drawHistoryPreloaded = false;
      unawaited(ensureDrawHistoryPreloaded());
      // member/owner games 常缺 seal 字段：公开期数对齐 web，避免假 10s 封盘窗
      unawaited(_enrichSealFromPublic(games));
    } catch (_) {
      if (!mounted) return;
      state = const RoomLotteryLiveState(
        ready: true,
        loadError: '彩种加载失败，请重试',
      );
    } finally {
      _loading = null;
    }
  }

  Future<void> _loadMetaAndWs({
    required bool isHost,
    required List<LotteryGameModel> games,
  }) async {
    if (!mounted) return;

    // 先连 WS（开奖/封盘推送）；倒计时以 HTTP openAt 锚定，WS 仅单调校正。
    unawaited(_connectWs(isHost: isHost, games: games));

    String announcement = state.announcement;
    var points = state.points;
    var turnover = state.turnover;
    var winLoss = state.winLoss;
    var rebate = state.rebate;
    var isTrialAccount = state.isTrialAccount;
    var betConfirm = state.betConfirm;

    if (isHost) {
      try {
        final notices = await _ref.read(ownerRepositoryProvider).getNotices();
        if (notices.isNotEmpty) {
          announcement = notices
              .map((e) => e['content']?.toString() ?? '')
              .where((s) => s.isNotEmpty)
              .join('  ');
          if (announcement.isEmpty) {
            announcement = '\u6b22\u8fce\u8fdb\u5165\u672c\u623f\u95f4';
          }
        }
      } catch (_) {}
      try {
        final dash = await _ref.read(ownerRepositoryProvider).getDashboard();
        points = _toInt(dash['balance']);
        turnover = _toInt(dash['turnover']);
        winLoss = _toInt(dash['todayProfitLoss']);
      } catch (_) {}
      try {
        final room = await _ref.read(ownerRepositoryProvider).getRoom();
        betConfirm = room['betConfirm'] == true || room['betConfirm'] == 1;
      } catch (_) {}
    } else {
      // 必须 await：若 unawaited 先写回积分，随后再用初始 0 的 copyWith 会覆盖掉真实余额
      final w = await _loadWalletSummary();
      points = w.$1;
      turnover = w.$2;
      winLoss = w.$3;
      rebate = w.$4;
      isTrialAccount = w.$5;
      try {
        final ann = await _ref.read(memberRepositoryProvider).getRoomAnnouncement();
        final c = ann['content']?.toString();
        if (c != null && c.isNotEmpty) announcement = c;
        if (ann.containsKey('betConfirm')) {
          betConfirm = ann['betConfirm'] == true || ann['betConfirm'] == 1;
          SessionStore.instance.betConfirm = betConfirm;
        }
      } catch (_) {
        betConfirm = SessionStore.instance.betConfirm;
      }
    }

    if (!mounted) return;
    state = state.copyWith(
      announcement: announcement,
      points: points,
      turnover: turnover,
      winLoss: winLoss,
      rebate: rebate,
      isTrialAccount: isTrialAccount,
      betConfirm: betConfirm,
    );
  }

  Future<(int, int, int, int, bool)> _loadWalletSummary() async {
    try {
      final wallet = await _ref.read(walletRepositoryProvider).getSummary(roomId);
      return (
        wallet.availablePoints.toInt(),
        wallet.todayTurnover.toInt(),
        wallet.todayWinLoss.toInt(),
        wallet.pendingRebate.toInt(),
        wallet.isTrial,
      );
    } catch (_) {
      return (
        state.points,
        state.turnover,
        state.winLoss,
        state.rebate,
        state.isTrialAccount,
      );
    }
  }

  void _scheduleRefreshGamesFromServer({bool immediate = false}) {
    _gamesRefreshDebounce?.cancel();
    if (immediate) {
      _gamesRefreshDebounce = null;
      unawaited(_refreshGamesFromServer());
      return;
    }
    _gamesRefreshDebounce = Timer(const Duration(milliseconds: 800), () {
      _gamesRefreshDebounce = null;
      unawaited(_refreshGamesFromServer());
    });
  }

  Future<void> _refreshGamesFromServer() async {
    if (_gamesRefreshInflight != null) {
      await _gamesRefreshInflight;
      return;
    }
    _gamesRefreshInflight = _refreshGamesFromServerImpl();
    try {
      await _gamesRefreshInflight;
    } finally {
      _gamesRefreshInflight = null;
    }
  }

  Future<void> _refreshGamesFromServerImpl() async {
    if (!mounted) return;
    try {
      final isHost = _ref.read(authSessionProvider).isHostSide;
      final games = await _ref
          .read(lotteryRepositoryProvider)
          .getGames(roomId, asOwner: isHost);
      if (!mounted) return;
      final now = DateTime.now();
      // 必须 syncCatalog：关则移除、开则加回（merge 不会删）
      _engine.syncCatalog(games, now);
      for (final g in games) {
        final cd = _engine.countdownFor(g.id, now);
        if (cd <= 0 && g.countdownSeconds > 0) {
          _engine.patchGame(g, now);
        }
      }
      _publishGames();
      // 全部关掉后再开启：games 从空变非空时可能 WS 已断，需重连才能订新彩种
      if (!_wsConnected && state.games.isNotEmpty) {
        unawaited(_reconnectIfNeeded());
      } else {
        _syncWsSubscriptions();
      }
      _ensureTickerRunning();
      for (final g in games) {
        scheduleReconcileChatDraws(g.id);
        unawaited(ensureGameTimelinePreloaded(g.id));
      }
      unawaited(_enrichSealFromPublic(games));
    } catch (_) {}
  }

  /// 用公开期数补 sealSeconds/sealAt（不改倒计时，不对齐会跳秒）。
  Future<void> _enrichSealFromPublic(List<LotteryGameModel> games) async {
    if (!mounted || games.isEmpty) return;
    final repo = _ref.read(lotteryRepositoryProvider);
    final now = DateTime.now();
    var touched = false;
    await Future.wait(games.map((g) async {
      if (g.id.isEmpty) return;
      if (LotteryPeriodRules.hasSealConfig(g)) return;
      final period = await repo.getPublicPeriod(g.id);
      if (!mounted || period == null) return;
      final sealSec = period.sealSeconds ?? 0;
      final sealAt = period.sealAt ?? 0;
      if (sealSec <= 0 && sealAt <= 0) return;
      _engine.applySealConfig(
        g.id,
        sealSeconds: sealSec > 0 ? sealSec : null,
        sealAtEpochMs: sealAt > 0 ? sealAt : null,
        now: now,
      );
      touched = true;
    }));
    if (mounted && touched) {
      _publishGames();
      _bumpUiTick();
    }
  }

  /// 彩种开关变更后立刻重拉目录（房主保存 / WS 推送）
  Future<void> reloadGamesCatalog() => _refreshGamesFromServer();

  void _publishGames() {
    if (!mounted) return;
    final next = _engine.games.map((g) {
      final named = state.gameById(g.id);
      return g.copyWith(
        name: named?.name.isNotEmpty == true ? named!.name : g.name,
      );
    }).toList();
    if (!listEquals(state.games, next)) {
      state = state.copyWith(games: next);
    }
  }

  // ── engine result → chat + state ──

  void _applyEngineResult(String gameId, PeriodTickResult result) {
    _markPeriodSynced(gameId);
    for (final draw in result.draws) {
      final gid = draw.gameId.isNotEmpty ? draw.gameId : gameId;
      // 回补只由 _finalizeDrawChatPush 负责，避免与 scheduleReconcile 双路 HTTP。
      _pushDrawChat(gid, draw.issue, draw.ranks);
    }
    if (result.changed) {
      _publishGames();
      _bumpUiTick();
    }
    // 开奖瞬间不刷钱包：避免与开奖卡上屏抢同一帧；余额以 SETTLE_RESULT 对齐。
    _ensureTickerRunning();
    _recoverStuckDrawingIfNeeded(gameId);
  }

  /// 球号已出但仍停在「开奖中」：WS 换期包可能 seconds=0，立刻 HTTP 补倒计时。
  void _recoverStuckDrawingIfNeeded(String gameId) {
    final g = _engine.displayGame(gameId, DateTime.now());
    if (!g.isDrawing || g.previousResults.isEmpty) return;
    _scheduleRefreshGamesFromServer(immediate: true);
  }

  void _applySecondTickResult(PeriodTickResult result) {
    for (final draw in result.draws) {
      _pushDrawChat(draw.gameId, draw.issue, draw.ranks);
    }
    if (result.changed) {
      _publishGames();
    }
    _bumpUiTick();
  }

  void _bumpUiTick() {
    if (!mounted) return;
    state = state.copyWith(uiTick: state.uiTick + 1);
  }

  void _markPeriodSynced(String gameId) {
    final pending = _periodSyncPending;
    if (pending == null || gameId.isEmpty) return;
    pending.remove(gameId);
    if (pending.isEmpty) {
      final c = _periodSyncCompleter;
      if (c != null && !c.isCompleted) c.complete();
    }
  }

  // ── WS ──

  Future<void> _connectWs({
    required bool isHost,
    required List<LotteryGameModel> games,
    bool isReconnect = false,
  }) {
    if (_wsDisposed) return Future.value();
    return _wsConnectInflight ??=
        _connectWsImpl(isHost: isHost, games: games, isReconnect: isReconnect)
            .whenComplete(() {
      _wsConnectInflight = null;
    });
  }

  Future<void> _connectWsImpl({
    required bool isHost,
    required List<LotteryGameModel> games,
    bool isReconnect = false,
  }) async {
    if (_ref.read(regressionSkipLiveWsProvider)) return;
    final gen = ++_wsConnectGen;
    _wsIsHost = isHost;
    try {
      await _wsSub?.cancel();
      _wsSub = null;
      _wsConnected = false;
      final old = _ws;
      _ws = null;
      if (old != null) {
        await old.dispose();
      }
      if (!mounted || _wsDisposed || gen != _wsConnectGen) return;

      final client = FlyroomWsClient(
        role: isHost ? FlyroomWsRole.owner : FlyroomWsRole.member,
        onDisconnected: () => _onWsTransportLost(gen),
      );
      await client.connect();
      if (!mounted || _wsDisposed || gen != _wsConnectGen) {
        await client.dispose();
        return;
      }

      _ws = client;
      _wsConnected = true;
      _wsReconnectAttempt = 0;
      _wsReconnectTimer?.cancel();
      _wsReconnectTimer = null;
      _wsSubscribedTopics.clear();

      _wsSub = client.events.listen(_onWsEvent);
      _syncWsSubscriptions();
      if (isReconnect) {
        unawaited(_refreshGamesFromServer());
      }
    } catch (_) {
      if (!mounted || _wsDisposed || gen != _wsConnectGen) return;
      _markWsTransportDown(gen);
      _scheduleRefreshGamesFromServer(immediate: true);
      _scheduleWsReconnect();
    }
  }

  void _onWsTransportLost(int gen) {
    if (!mounted || _wsDisposed || gen != _wsConnectGen) return;
    _markWsTransportDown(gen);
    _scheduleRefreshGamesFromServer(immediate: true);
    _scheduleWsReconnect();
    _ensureTickerRunning();
  }

  void _markWsTransportDown(int gen) {
    if (gen != _wsConnectGen) return;
    _wsConnected = false;
    _wsSub?.cancel();
    _wsSub = null;
    _wsSubscribedTopics.clear();
    final dead = _ws;
    _ws = null;
    if (dead != null) {
      unawaited(dead.dispose());
    }
  }

  void _scheduleWsReconnect() {
    if (_wsDisposed || _wsConnected || _wsConnectInflight != null) return;
    if (_wsReconnectTimer != null) return;
    final seconds = math.min(30, 1 << _wsReconnectAttempt);
    _wsReconnectTimer = Timer(Duration(seconds: seconds), () {
      _wsReconnectTimer = null;
      if (!mounted || _wsDisposed || _wsConnected || _wsConnectInflight != null) {
        return;
      }
      _wsReconnectAttempt = math.min(_wsReconnectAttempt + 1, 5);
      unawaited(
        _connectWs(
          isHost: _wsIsHost,
          games: state.games,
          isReconnect: true,
        ),
      );
    });
  }

  void _syncWsSubscriptions() {
    final client = _ws;
    if (!_wsConnected || client == null) return;
    final roomNumeric = SessionStore.instance.roomId ?? roomId;
    final desired = <String>{
      'room:$roomNumeric:sys',
      for (final g in state.games)
        if (g.id.isNotEmpty) 'room:$roomNumeric:game:${g.id}',
    };
    for (final t in _wsSubscribedTopics.difference(desired)) {
      client.unsubscribe(t);
    }
    for (final t in desired.difference(_wsSubscribedTopics)) {
      client.subscribe(t);
    }
    _wsSubscribedTopics
      ..clear()
      ..addAll(desired);
  }

  void _onWsEvent(Map<String, dynamic> event) {
    if (!mounted) return;
    final payload = _wsPayload(event);
    final type = (payload['event'] ?? payload['type'] ?? '').toString().toUpperCase();

    // 房间级：彩种开关变更 → 立刻重拉大厅目录
    if (type == 'ROOM_GAMES_CHANGED') {
      unawaited(reloadGamesCatalog());
      return;
    }

    final gameType = _gameTypeFromEvent(event, payload);
    if (gameType == null || gameType.isEmpty) return;

    if (type == 'PERIOD_TICK' || type == 'PERIOD_SNAPSHOT') {
      final issue = payload['issueNo']?.toString() ??
          payload['latestIssueNo']?.toString() ??
          '';
      final seconds = _toInt(payload['countdownSeconds']);
      final openAtMs = _toInt(payload['openAtEpochMs']);
      var sealAtMs = _toInt(payload['sealAtEpochMs']);
      var sealSeconds = _toInt(payload['sealSeconds']);
      // 包里没有 sealSeconds 时，用开奖/封盘时刻差补配置。不反过来用秒数改写 sealAt。
      if (sealSeconds <= 0 && openAtMs > 0 && sealAtMs > 0 && openAtMs > sealAtMs) {
        sealSeconds = ((openAtMs - sealAtMs) / 1000).round();
      }
      final lastRanks = _parseRanks(payload['lastRanks'] ?? payload['ranks']);
      final lastIssue = payload['lastIssueNo']?.toString() ?? '';
      final result = _engine.onPeriodTick(
        gameType,
        issue: issue,
        seconds: seconds,
        openAtEpochMs: openAtMs > 0 ? openAtMs : null,
        sealAtEpochMs: sealAtMs > 0 ? sealAtMs : null,
        sealSeconds: sealSeconds > 0 ? sealSeconds : null,
        lastIssue: lastIssue,
        lastRanks: lastRanks,
      );
      _applyEngineResult(gameType, result);
      return;
    }

    if (type == 'SEAL_WARN' || type == 'SEALED') {
      _applySealEvent(type, gameType, payload);
      return;
    }

    if (type == 'CHAT') {
      final issue = payload['issueNo']?.toString() ?? '';
      final content =
          (payload['content'] ?? payload['text'] ?? '').toString().trim();
      if (content.isEmpty) return;
      final sender = (payload['senderName'] ?? '会员').toString();
      final orderId = payload['orderId']?.toString() ?? '';
      final key = orderId.isNotEmpty
          ? 'bet-chat-$gameType-$orderId'
          : 'chat-$gameType-${DateTime.now().millisecondsSinceEpoch}';
      _pushChatOnce(
        key,
        gameType,
        ChatMessageModel(
          id: key,
          sender: sender,
          content: content,
          time: _nowTime(),
          type: ChatMessageType.text,
          isAdmin: false,
          issueNo: issue.isNotEmpty ? issue : null,
          avatarUrl: (payload['avatarUrl'] ?? payload['avatar'])?.toString(),
        ),
      );
      return;
    }

    // 封盘后竞猜列表核对（后端 RoomSealRankService → BET_RANK）
    if (type == 'BET_RANK' ||
        type == 'BET_LIST_CHECK' ||
        type == 'GUESS_LIST_CHECK' ||
        type == 'SEAL_BET_LIST') {
      _onBetRankWs(gameType, payload);
      return;
    }

    // 开奖后中奖列表核对（后端 SettleExecutor → WIN_LIST）
    if (type == 'WIN_LIST' || type == 'WIN_CHECK' || type == 'WIN_LIST_CHECK') {
      _onWinListWs(gameType, payload);
      return;
    }

    // 他人/本机机器人确认卡
    if (type == 'BET_RECEIPT') {
      _onBetReceiptWs(gameType, payload);
      return;
    }

    if (type == 'DRAW_RESULT') {
      final ranks = _parseRanks(payload['ranks'] ?? payload['lastRanks']);
      final issue = payload['issueNo']?.toString() ?? '';
      if (ranks.isEmpty) return;
      final result = _engine.onDrawResult(
        gameType,
        issue: issue,
        ranks: ranks,
      );
      _applyEngineResult(gameType, result);
      // 引擎若去重未产出 draw 事件，仍强制开奖卡上屏（后端已先于 WIN_LIST 推送）。
      if (issue.isNotEmpty &&
          !ChatPushCache.instance.hasDrawForIssue(roomId, gameType, issue)) {
        _pushDrawChat(gameType, issue, ranks);
      }
      if (_engine.isDrawingPhase(gameType, DateTime.now())) {
        _scheduleRefreshGamesFromServer(immediate: true);
      }
      return;
    }

    if (type == 'SETTLE_RESULT') {
      _onSettleResult(gameType, payload);
      return;
    }
  }

  void _onSettleResult(String gameType, Map<String, dynamic> payload) {
    final myIdStr = _ref.read(authSessionProvider).user?.id ?? '';
    final myId = int.tryParse(myIdStr);
    final issue = payload['issueNo']?.toString() ?? '';
    final accounts = payload['accounts'];
    final truncated = payload['accountsTruncated'] == true;
    var touched = false;
    final optKey = '$gameType|$issue|$myIdStr';
    final alreadyOptimistic = _settleOptimisticApplied.contains(optKey);
    if (!alreadyOptimistic && myId != null && accounts is List) {
      for (final raw in accounts) {
        if (raw is! Map) continue;
        final aid = raw['accountId'];
        final id = aid is num ? aid.toInt() : int.tryParse('$aid');
        if (id != myId) continue;
        final winLoss = _toInt(raw['winLoss']);
        final winAmount = _toInt(raw['winAmount']);
        if (winAmount != 0) {
          state = state.copyWith(points: state.points + winAmount);
        }
        if (winLoss != 0) {
          state = state.copyWith(winLoss: state.winLoss + winLoss);
        }
        touched = true;
        _settleOptimisticApplied.add(optKey);
        if (_settleOptimisticApplied.length > 64) {
          _settleOptimisticApplied.remove(_settleOptimisticApplied.first);
        }
        break;
      }
    }
    // 账本异步落库：单次短延迟对齐，避免 350+1200 双刷与中奖列表上屏抢帧。
    unawaited(() async {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      if (!mounted) return;
      await refreshWallet();
    }());
    if (touched || truncated || alreadyOptimistic) {
      _bumpUiTick();
    }
  }

  void _onBetRankWs(String gameType, Map<String, dynamic> payload) {
    final issue = (payload['issueNo'] ?? '').toString().trim();
    final content = (payload['content'] ?? payload['text'] ?? '').toString();
    final rankings = payload['rankings'] is List ? payload['rankings'] as List : null;
    final text = formatBetRankText(
      issue: issue,
      content: content,
      rankings: rankings,
    ).trim();
    if (text.isEmpty) return;
    final key = issue.isNotEmpty
        ? betRankChatMessageId(gameType, issue)
        : 'bet-rank-$gameType-${DateTime.now().millisecondsSinceEpoch}';
    var sender = (payload['senderName'] ?? '机器人').toString().trim();
    if (sender.isEmpty || sender == '管理员') sender = '机器人';
    _pushChatOnce(
      key,
      gameType,
      ChatMessageModel(
        id: key,
        sender: sender,
        content: text,
        time: _nowTime(),
        type: ChatMessageType.betListCheck,
        isAdmin: false,
        issueNo: issue.isNotEmpty ? issue : null,
      ),
    );
  }

  void _onWinListWs(String gameType, Map<String, dynamic> payload) {
    final issue = (payload['issueNo'] ?? '').toString().trim();
    final content = (payload['content'] ?? payload['text'] ?? '').toString();
    final winners = parseWinCheckWinners(
      payload['winners'] is List ? payload['winners'] as List : null,
    );
    final text = formatWinCheckText(
      issue: issue,
      content: content,
      winners: winners,
    ).trim();
    if (text.isEmpty) return;
    final key = issue.isNotEmpty
        ? winListChatMessageId(gameType, issue)
        : 'win-list-$gameType-${DateTime.now().millisecondsSinceEpoch}';
    var sender = (payload['senderName'] ?? '机器人').toString().trim();
    if (sender.isEmpty || sender == '管理员') sender = '机器人';
    final message = ChatMessageModel(
      id: key,
      sender: sender,
      content: text,
      time: _nowTime(),
      type: ChatMessageType.winCheck,
      isAdmin: false,
      issueNo: issue.isNotEmpty ? issue : null,
    );
    // 开奖卡片未到：挂起，避免「核对」先上屏、开奖再插到上面闪一下。
    if (issue.isNotEmpty &&
        !ChatPushCache.instance.hasDrawForIssue(roomId, gameType, issue)) {
      final pendingKey = '$gameType|${issueCompareKey(issue)}';
      _pendingWinListByKey[pendingKey] = _PendingWinList(
        gameType: gameType,
        dedupeKey: key,
        message: message,
      );
      if (_pendingWinListByKey.length > 32) {
        _pendingWinListByKey.remove(_pendingWinListByKey.keys.first);
      }
      return;
    }
    _pushChatOnce(key, gameType, message);
  }

  void _flushPendingWinList(String gameType, String issue) {
    final issueKey = issueCompareKey(issue);
    if (issueKey <= 0) return;
    final pendingKey = '$gameType|$issueKey';
    final pending = _pendingWinListByKey.remove(pendingKey);
    if (pending == null) return;
    _pushChatOnce(pending.dedupeKey, pending.gameType, pending.message);
  }

  void _onBetReceiptWs(String gameType, Map<String, dynamic> payload) {
    final orderId = (payload['orderId'] ?? '').toString().trim();
    final issue = (payload['issueNo'] ?? '').toString().trim();
    final content = formatBetReceiptText(
      mention: (payload['mentionName'] ?? '').toString(),
      issue: issue,
      total: payload['totalAmount'],
      items: payload['items'] is List ? payload['items'] as List : null,
      fallbackContent: (payload['content'] ?? payload['text'] ?? '').toString(),
    ).trim();
    if (content.isEmpty) return;
    final key = orderId.isNotEmpty
        ? 'bet-receipt-$gameType-$orderId'
        : (issue.isNotEmpty
            ? 'bet-receipt-$gameType-$issue-${content.hashCode}'
            : 'bet-receipt-$gameType-${DateTime.now().millisecondsSinceEpoch}');
    var sender = (payload['senderName'] ?? '机器人').toString().trim();
    if (sender.isEmpty || sender == '管理员') sender = '机器人';
    final avatar =
        (payload['avatarUrl'] ?? payload['avatar'])?.toString().trim();
    _pushChatOnce(
      key,
      gameType,
      ChatMessageModel(
        id: key,
        sender: sender,
        content: content,
        time: _nowTime(),
        type: ChatMessageType.betReceipt,
        isAdmin: false,
        issueNo: issue.isNotEmpty ? issue : null,
        avatarUrl: (avatar != null && avatar.isNotEmpty) ? avatar : null,
      ),
    );
  }

  Map<String, dynamic> _wsPayload(Map<String, dynamic> event) {
    final merged = Map<String, dynamic>.from(event);
    final data = event['data'];
    if (data is Map) {
      merged.addAll(Map<String, dynamic>.from(data));
    }
    return merged;
  }

  String? _gameTypeFromEvent(
    Map<String, dynamic> event,
    Map<String, dynamic> payload,
  ) {
    final direct = payload['gameType']?.toString();
    if (direct != null && direct.isNotEmpty) return direct;
    final topic = event['topic']?.toString();
    if (topic == null || topic.isEmpty) return null;
    const marker = ':game:';
    final idx = topic.indexOf(marker);
    if (idx >= 0) return topic.substring(idx + marker.length);
    if (topic.startsWith('game:')) return topic.substring(5);
    return topic.split(':').lastOrNull;
  }

  List<int> _parseRanks(dynamic ranks) {
    if (ranks is! List) return const [];
    return ranks.map((x) => int.tryParse('$x') ?? 0).where((x) => x > 0).toList();
  }

  // ── chat push ──

  void _applySealEvent(
    String type,
    String gameType,
    Map<String, dynamic> payload,
  ) {
    final text = (payload['text'] ?? payload['content'] ?? '').toString().trim();
    if (text.isEmpty) return;
    final issue = (payload['issueNo']?.toString() ?? '').trim();
    final key = issue.isEmpty
        ? '${type.toLowerCase()}-$gameType-0'
        : (type == 'SEAL_WARN'
            ? sealWarnChatMessageId(gameType, issue)
            : sealedChatMessageId(gameType, issue));
    final sender = (payload['senderName'] ?? '机器人').toString().trim();
    _pushChatOnce(
      key,
      gameType,
      ChatMessageModel(
        id: key,
        sender: sender.isEmpty || sender == '管理员' ? '机器人' : sender,
        content: text,
        time: _nowTime(),
        type: ChatMessageType.system,
        isAdmin: true,
        issueNo: issue.isNotEmpty ? issue : null,
      ),
    );
  }

  void _pushDrawChat(String gameType, String issue, List<int> ranks) {
    final fullIssue = issue.trim();
    final msgId = fullIssue.isNotEmpty
        ? drawChatMessageId(gameType, issue)
        : 'draw-$gameType-unknown';
    _pushChatOnce(
      msgId,
      gameType,
      ChatMessageModel(
        id: msgId,
        sender: '机器人',
        content: fullIssue.isNotEmpty ? '第$fullIssue期开奖' : '开奖结果',
        time: _nowTime(),
        type: ChatMessageType.resultCard,
        isAdmin: true,
        issueNo: fullIssue.isNotEmpty ? fullIssue : null,
        drawRanks: ranks,
      ),
    );
    // 开奖先落盘后再放行挂起的中奖核对，保证同帧顺序：开奖 → 核对。
    if (fullIssue.isNotEmpty) {
      _flushPendingWinList(gameType, fullIssue);
    }
  }

  bool _pushChatOnce(
    String key,
    String gameId,
    ChatMessageModel message, {
    bool persist = true,
  }) {
    final bool added;
    if (persist) {
      added = ChatPushCache.instance.pushOnce(
        roomId: roomId,
        dedupeKey: key,
        gameId: gameId,
        message: message,
      );
    } else {
      added = ChatPushCache.instance.emitLive(
        roomId: roomId,
        dedupeKey: key,
        gameId: gameId,
        message: message,
      );
    }
    if (!added) return false;
    // 开奖先立刻上屏，HTTP 缺口回补放到后台，避免等 reconcile 造成「开奖结果」晚闪/跳一下。
    if (!_chatPushController.isClosed) {
      _chatPushController.add(LotteryChatPush(gameId: gameId, message: message));
    }
    if (message.type == ChatMessageType.resultCard) {
      unawaited(_finalizeDrawChatPush(gameId, message));
    }
    return true;
  }

  Future<void> _finalizeDrawChatPush(
    String gameId,
    ChatMessageModel message,
  ) async {
    if (!mounted) return;
    final needsBackfill = ChatPushCache.instance.hasDrawGap(roomId, gameId) ||
        _cacheNeedsDrawBackfill(gameId);
    if (needsBackfill) {
      await reconcileChatDraws(gameId);
      if (!mounted) return;
    }
    _bumpDrawCache();
    // 仅在回补改写了缓存时再通知一次，避免无缺口时双刷 UI。
    if (needsBackfill && !_chatPushController.isClosed) {
      _chatPushController.add(
        LotteryChatPush(gameId: gameId, message: message),
      );
    }
  }

  String _nowTime() {
    final n = DateTime.now();
    return '${n.hour.toString().padLeft(2, '0')}:${n.minute.toString().padLeft(2, '0')}';
  }

  // ── ticker / recovery ──

  bool _gameNeedsRecovery(String gameId) {
    return _engine.isDrawingPhase(gameId, DateTime.now());
  }

  void _scheduleServerSync() {
    if (_wsConnected) {
      _scheduleDrawWatchdog();
      return;
    }
    _drawPollDebounce?.cancel();
    _drawPollDebounce = Timer(const Duration(milliseconds: 800), () {
      _drawPollDebounce = null;
      if (!mounted) return;
      if (state.games.any((g) => _gameNeedsRecovery(g.id))) {
        _scheduleRefreshGamesFromServer();
      }
    });
  }

  void _scheduleDrawWatchdog() {
    if (!state.games.any((g) => _gameNeedsRecovery(g.id))) {
      _drawWatchdog?.cancel();
      _drawWatchdog = null;
      return;
    }
    _drawWatchdog ??= Timer(const Duration(seconds: 1), () {
      _drawWatchdog = null;
      if (!mounted) return;
      if (state.games.any((g) => _gameNeedsRecovery(g.id))) {
        _scheduleRefreshGamesFromServer(immediate: true);
      }
    });
  }

  void _cancelDrawWatchdog() {
    _drawWatchdog?.cancel();
    _drawWatchdog = null;
  }

  void _ensureTickerRunning() {
    if (_ticker != null) return;
    if (!_engine.needsAnyTicker()) return;
    _startTicker();
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || !state.ready) return;
      if (!_engine.needsAnyTicker()) {
        _ticker?.cancel();
        _ticker = null;
        return;
      }

      if (_interactionPaused) {
        _bumpUiTick();
        return;
      }

      final now = DateTime.now();
      final result = _engine.onSecondTick(now);
      _applySecondTickResult(result);

      if (state.games.any((g) => _gameNeedsRecovery(g.id))) {
        _scheduleServerSync();
      } else {
        _cancelDrawWatchdog();
      }
    });
  }

  int _toInt(dynamic v) =>
      v is int ? v : (v is num ? v.toInt() : int.tryParse('$v') ?? 0);

  @override
  void dispose() {
    _wsDisposed = true;
    _wsConnectGen++;
    _wsReconnectTimer?.cancel();
    _wsReconnectTimer = null;
    _ticker?.cancel();
    _drawPollDebounce?.cancel();
    _drawWatchdog?.cancel();
    _gamesRefreshDebounce?.cancel();
    _drawCacheBumpDebounce?.cancel();
    for (final timer in _reconcileDebounceByGame.values) {
      timer.cancel();
    }
    _reconcileDebounceByGame.clear();
    _pendingWinListByKey.clear();
    _engine.reset();
    _chatBootstrapping.clear();
    _wsSub?.cancel();
    _wsSub = null;
    _wsConnected = false;
    final dead = _ws;
    _ws = null;
    unawaited(dead?.dispose() ?? Future.value());
    unawaited(_chatPushController.close());
    super.dispose();
  }
}

class _PendingWinList {
  const _PendingWinList({
    required this.gameType,
    required this.dedupeKey,
    required this.message,
  });

  final String gameType;
  final String dedupeKey;
  final ChatMessageModel message;
}

extension on List<String> {
  String? get lastOrNull => isEmpty ? null : last;
}

final roomLotteryLiveProvider = StateNotifierProvider.autoDispose
    .family<RoomLotteryLiveNotifier, RoomLotteryLiveState, String>((ref, roomId) {
  ref.keepAlive();
  return RoomLotteryLiveNotifier(ref, roomId);
});
