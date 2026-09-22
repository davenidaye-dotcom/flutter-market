import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../data/models/chat_message_model.dart';
import '../utils/chat_timeline.dart';
import '../utils/bet_repeat_helper.dart';
import '../utils/draw_history_rows.dart';
import '../widgets/history_draw_panel.dart';
import 'chat_timeline_codec.dart';
import 'chat_push_codec.dart';

/// WS 推送到聊天区的系统消息（封盘/开奖等）
class LotteryChatPush {
  const LotteryChatPush({required this.gameId, required this.message});

  final String gameId;
  final ChatMessageModel message;
}

class _CachedChatPush {
  const _CachedChatPush({required this.dedupeKey, required this.push});

  final String dedupeKey;
  final LotteryChatPush push;

  Map<String, dynamic> toJson() => {
        'k': dedupeKey,
        'g': push.gameId,
        'm': _messageToJson(push.message),
      };

  static _CachedChatPush? fromJson(Map<String, dynamic> json) {
    final gameId = json['g']?.toString();
    final messageRaw = json['m'];
    final dedupeKey = json['k']?.toString();
    if (gameId == null || gameId.isEmpty || dedupeKey == null || dedupeKey.isEmpty) {
      return null;
    }
    if (messageRaw is! Map) return null;
    final message = _messageFromJson(Map<String, dynamic>.from(messageRaw));
    if (message == null) return null;
    return _CachedChatPush(
      dedupeKey: dedupeKey,
      push: LotteryChatPush(gameId: gameId, message: message),
    );
  }
}

/// 封盘/开奖等聊天推送的本地缓存（内存 + SharedPreferences）。
/// 保留最近约 [chatHistoryIssueLimit] 期的开奖 + 下注/核对，勿用「总共 20 条」裁光核对。
class ChatPushCache {
  ChatPushCache._();

  static final ChatPushCache instance = ChatPushCache._();

  /// 聊天历史按期数（与后端 CHAT_HISTORY_ISSUE_COUNT 对齐）。
  static const chatHistoryIssueLimit = 15;
  /// 每彩种开奖卡片上限。
  static const maxDrawsPerGame = chatHistoryIssueLimit;
  /// 每彩种用户下注文案上限（多期合计）。
  static const maxUserBetsPerGame = 120;
  /// 确认卡 + 竞猜核对 + 中奖核对（约 15 期 × 数条）。
  static const maxRobotMsgsPerGame = 120;
  /// 兼容旧名：总预算仅作 others 配额参考，不再拿它裁掉核对。
  static const maxPerGame = maxDrawsPerGame + maxUserBetsPerGame + maxRobotMsgsPerGame;
  /// 聊天 ListView 最多渲染条数
  static const maxVisibleChatMessages = 220;
  /// 进房预拉、聊天同步：每彩种最新开奖条数
  static const drawHistoryLimit = maxDrawsPerGame;
  static const serverDrawLimit = drawHistoryLimit;
  static const _prefPrefix = 'flyroom_chat_cache_';

  final Map<String, Set<String>> _keysByRoom = {};
  final Map<String, List<_CachedChatPush>> _bufferByRoom = {};
  /// 实时封盘（不落盘）：必须参与 timeline，否则 sync/进页会丢，只剩开奖时 synthetic「一起出现」。
  final Map<String, List<_CachedChatPush>> _liveByRoom = {};
  final Set<String> _loadedRooms = {};
  final Map<String, Timer> _saveTimers = {};
  final Map<String, Future<void>> _roomLoadInflight = {};
  final Map<String, List<ChatMessageModel>> _timelineCache = {};
  final Map<String, List<HistoryDrawRow>> _historyRowsCache = {};
  int _persistSuspendCount = 0;

  /// 键盘/下注交互期间暂停磁盘写入，避免主线程卡顿。
  void suspendPersist() => _persistSuspendCount++;
  void resumePersist() {
    if (_persistSuspendCount > 0) _persistSuspendCount--;
  }

  Future<void> preload() async {
    // 懒加载：按房间在 ensureRoomLoaded 时读盘，避免启动阻塞。
  }

  bool hasMemoryRoom(String roomId) => _bufferByRoom.containsKey(roomId);

  Future<void> ensureRoomLoaded(String roomId) async {
    if (_loadedRooms.contains(roomId)) return;
    final inflight = _roomLoadInflight[roomId];
    if (inflight != null) {
      await inflight;
      return;
    }
    final future = _loadRoomFromDisk(roomId);
    _roomLoadInflight[roomId] = future;
    try {
      await future;
    } finally {
      _roomLoadInflight.remove(roomId);
    }
  }

  Future<void> _loadRoomFromDisk(String roomId) async {
    if (_loadedRooms.contains(roomId)) return;
    final prefs = await SharedPreferences.getInstance();
    await _loadRoom(roomId, prefs);
  }

  bool hasDedupeKey(String roomId, String dedupeKey) {
    return _keysByRoom[roomId]?.contains(dedupeKey) ?? false;
  }

  /// 缓存里是否已有该期开奖卡片。
  bool hasDrawForIssue(String roomId, String gameId, String issue) {
    final target = issueCompareKey(issue);
    if (target <= 0) return false;
    for (final m in bufferedForGame(roomId, gameId)) {
      if (m.type != ChatMessageType.resultCard) continue;
      final extracted = extractIssue(m);
      if (extracted != null &&
          extracted.isNotEmpty &&
          issueCompareKey(extracted) == target) {
        return true;
      }
    }
    return false;
  }

  /// 开奖期号是否不连续。
  bool hasDrawGap(String roomId, String gameId) {
    final nums = <int>{};
    for (final m in bufferedForGame(roomId, gameId)) {
      if (m.type != ChatMessageType.resultCard) continue;
      final issue = extractIssue(m);
      if (issue == null || issue.isEmpty) continue;
      final full = int.tryParse(issue.trim()) ?? 0;
      if (full > 0) {
        nums.add(full);
      } else {
        final key = issueCompareKey(issue);
        if (key > 0) nums.add(key);
      }
    }
    if (nums.length < 2) return false;
    final sorted = nums.toList()..sort();
    for (var i = 1; i < sorted.length; i++) {
      if (sorted[i] - sorted[i - 1] > 1) return true;
    }
    return false;
  }

  bool pushOnce({
    required String roomId,
    required String dedupeKey,
    required String gameId,
    required ChatMessageModel message,
  }) {
    final normalized = normalizeStoredChatMessage(message, gameId: gameId);
    final logicalKey = _logicalDedupeKey(gameId, normalized) ?? dedupeKey;
    _keysByRoom.putIfAbsent(roomId, () => <String>{});
    _bufferByRoom.putIfAbsent(roomId, () => <_CachedChatPush>[]);
    // 只清「同逻辑期」但旧长号 dedupeKey 的别名，不删已存在的 logicalKey 本身
    _purgeAliasDuplicates(roomId, gameId, normalized, logicalKey);
    final keys = _keysByRoom[roomId]!;
    if (keys.contains(logicalKey)) {
      if ((normalized.type == ChatMessageType.betReceipt ||
              normalized.type == ChatMessageType.betListCheck ||
              normalized.type == ChatMessageType.winCheck) &&
          _replaceIfRicher(roomId, logicalKey, normalized)) {
        _invalidateGameCache(roomId, gameId);
        _schedulePersist(roomId);
        return true;
      }
      final upgraded =
          _upgradeStoredIssueIfLonger(roomId, logicalKey, normalized);
      return upgraded;
    }
    keys.add(logicalKey);

    // purge 会替换 buffer list，必须重新取引用再 add
    _bufferByRoom[roomId]!.add(
      _CachedChatPush(
        dedupeKey: logicalKey,
        push: LotteryChatPush(gameId: gameId, message: normalized),
      ),
    );
    _trimRoom(roomId);
    _invalidateGameCache(roomId, gameId);
    _schedulePersist(roomId);
    return true;
  }

  /// 本地先插的确认卡文案较短时，用服务端 BET_RECEIPT 覆盖。
  bool _replaceIfRicher(
    String roomId,
    String logicalKey,
    ChatMessageModel incoming,
  ) {
    final buffer = _bufferByRoom[roomId];
    if (buffer == null || incoming.content.trim().isEmpty) return false;
    for (var i = 0; i < buffer.length; i++) {
      final entry = buffer[i];
      if (entry.dedupeKey != logicalKey) continue;
      final existing = entry.push.message.content;
      if (incoming.content.trim().length <= existing.trim().length) return false;
      buffer[i] = _CachedChatPush(
        dedupeKey: logicalKey,
        push: LotteryChatPush(gameId: entry.push.gameId, message: incoming),
      );
      return true;
    }
    return false;
  }

  /// 同逻辑期已存在时：若新消息期号更长，升级展示文案（短号→长号）。
  /// 返回 true 表示缓存已改写，调用方应通知 UI。
  bool _upgradeStoredIssueIfLonger(
    String roomId,
    String logicalKey,
    ChatMessageModel incoming,
  ) {
    final incomingIssue = extractIssue(incoming);
    if (incomingIssue == null || incomingIssue.isEmpty) return false;
    final buffer = _bufferByRoom[roomId];
    if (buffer == null) return false;
    for (var i = 0; i < buffer.length; i++) {
      final entry = buffer[i];
      if (entry.dedupeKey != logicalKey) continue;
      final existing = entry.push.message;
      final existingIssue = extractIssue(existing) ?? '';
      final preferred = preferFullIssueNo(incomingIssue, existingIssue);
      if (preferred == existingIssue.trim()) return false;
      final upgraded = existing.type == ChatMessageType.resultCard
          ? ChatMessageModel(
              id: existing.id,
              sender: existing.sender,
              content: '第$preferred期开奖',
              time: existing.time,
              type: existing.type,
              isAdmin: existing.isAdmin,
              issueNo: preferred,
              drawRanks: existing.drawRanks ?? incoming.drawRanks,
              avatarUrl: existing.avatarUrl ?? incoming.avatarUrl,
            )
          : ChatMessageModel(
              id: existing.id,
              sender: existing.sender,
              content: existing.content,
              time: existing.time,
              type: existing.type,
              isAdmin: existing.isAdmin,
              issueNo: preferred,
              drawRanks: existing.drawRanks,
              avatarUrl: existing.avatarUrl ?? incoming.avatarUrl,
            );
      buffer[i] = _CachedChatPush(
        dedupeKey: logicalKey,
        push: LotteryChatPush(gameId: entry.push.gameId, message: upgraded),
      );
      _invalidateGameCache(roomId, entry.push.gameId);
      _schedulePersist(roomId);
      return true;
    }
    return false;
  }

  String? _logicalDedupeKey(String gameId, ChatMessageModel message) {
    final issue = extractIssue(message);
    if (issue == null || issue.isEmpty) return null;
    if (message.type == ChatMessageType.resultCard) {
      return drawChatMessageId(gameId, issue);
    }
    if (message.type == ChatMessageType.winCheck) {
      return winListChatMessageId(gameId, issue);
    }
    if (message.type == ChatMessageType.betListCheck) {
      return betRankChatMessageId(gameId, issue);
    }
    if (message.type == ChatMessageType.system) {
      if (message.content.contains('封盘线') ||
          message.content.contains('停止战斗')) {
        return sealedChatMessageId(gameId, issue);
      }
      if (message.content.contains('封盘')) {
        return sealWarnChatMessageId(gameId, issue);
      }
    }
    return null;
  }

  /// 磁盘/HTTP 可能残留 draw-JS_SC-34135299，与 draw-JS_SC-5299 同逻辑期并存。
  void _purgeAliasDuplicates(
    String roomId,
    String gameId,
    ChatMessageModel incoming,
    String logicalKey,
  ) {
    final keys = _keysByRoom[roomId];
    final buffer = _bufferByRoom[roomId];
    if (keys == null || buffer == null) return;
    final issueKey = issueCompareKey(extractIssue(incoming) ?? '');
    if (issueKey <= 0) return;
    final kept = <_CachedChatPush>[];
    for (final entry in buffer) {
      if (entry.push.gameId != gameId) {
        kept.add(entry);
        continue;
      }
      if (entry.dedupeKey == logicalKey) {
        kept.add(entry);
        continue;
      }
      final m = entry.push.message;
      if (m.type != incoming.type) {
        kept.add(entry);
        continue;
      }
      // 只合并开奖卡 / 封盘提示的长短号别名。玩家指令和机器人确认卡按单保留。
      if (incoming.type != ChatMessageType.resultCard &&
          incoming.type != ChatMessageType.system) {
        kept.add(entry);
        continue;
      }
      final otherIssue = extractIssue(m);
      final otherKey = otherIssue != null && otherIssue.isNotEmpty
          ? issueCompareKey(otherIssue)
          : 0;
      final sameLogic = otherKey == issueKey &&
          (incoming.type != ChatMessageType.system ||
              _sameSealPhase(incoming, m));
      if (sameLogic) {
        keys.remove(entry.dedupeKey);
        continue;
      }
      kept.add(entry);
    }
    _bufferByRoom[roomId] = kept;
  }

  bool _sameSealPhase(ChatMessageModel a, ChatMessageModel b) {
    final aLine =
        a.content.contains('封盘线') || a.content.contains('停止战斗');
    final bLine =
        b.content.contains('封盘线') || b.content.contains('停止战斗');
    if (aLine || bLine) return aLine == bLine;
    final aWarn = a.content.contains('封盘');
    final bWarn = b.content.contains('封盘');
    return aWarn == bWarn;
  }

  /// 封盘写入内存 live 区（不占开奖 trim 配额、不落盘），并参与 timeline。
  /// 仅记 dedupe 不存消息会导致：大厅已 emit → 进聊天 dedupe 挡住 → 只能等开奖 synthetic。
  bool emitLive({
    required String roomId,
    required String dedupeKey,
    required String gameId,
    required ChatMessageModel message,
  }) {
    final normalized = normalizeStoredChatMessage(message, gameId: gameId);
    final logicalKey = _logicalDedupeKey(gameId, normalized) ?? dedupeKey;
    final keys = _keysByRoom.putIfAbsent(roomId, () => <String>{});
    final live = _liveByRoom.putIfAbsent(roomId, () => <_CachedChatPush>[]);
    final alreadyLive = live.any((e) => e.dedupeKey == logicalKey);
    if (keys.contains(logicalKey)) {
      // key 已有：只补 live 体给 timeline，返回 false 避免每秒重推闪屏
      if (!alreadyLive) {
        live.add(
          _CachedChatPush(
            dedupeKey: logicalKey,
            push: LotteryChatPush(gameId: gameId, message: normalized),
          ),
        );
        _trimLiveRoom(roomId, gameId);
        _timelineCache.remove('$roomId:$gameId');
      }
      return false;
    }
    keys.add(logicalKey);
    live.add(
      _CachedChatPush(
        dedupeKey: logicalKey,
        push: LotteryChatPush(gameId: gameId, message: normalized),
      ),
    );
    _trimLiveRoom(roomId, gameId);
    _timelineCache.remove('$roomId:$gameId');
    return true;
  }

  void clearLiveDedupe(String roomId, String gameId) {
    final keys = _keysByRoom[roomId];
    if (keys != null) {
      keys.removeWhere(
        (k) =>
            (k.startsWith('local-seal-') ||
                k.startsWith('seal-warn-') ||
                k.startsWith('sealed-')) &&
            k.contains('-$gameId-'),
      );
    }
    final live = _liveByRoom[roomId];
    if (live != null) {
      live.removeWhere((e) => e.push.gameId == gameId);
    }
    _timelineCache.remove('$roomId:$gameId');
  }

  List<ChatMessageModel> liveForGame(String roomId, String gameId) {
    final live = _liveByRoom[roomId];
    if (live == null || live.isEmpty) return const [];
    return live
        .where((e) => e.push.gameId == gameId)
        .map((e) => e.push.message)
        .toList(growable: false);
  }

  List<ChatMessageModel> bufferedForGame(String roomId, String gameId) {
    final buffer = _bufferByRoom[roomId];
    if (buffer == null || buffer.isEmpty) return const [];
    return List<_CachedChatPush>.from(buffer)
        .where((e) => e.push.gameId == gameId)
        .map((e) => e.push.message)
        .toList(growable: false);
  }

  /// buffer 开奖 + live 封盘，供时间线使用。
  List<ChatMessageModel> messagesForGameTimeline(String roomId, String gameId) {
    final persisted = bufferedForGame(roomId, gameId);
    final live = liveForGame(roomId, gameId);
    if (live.isEmpty) return persisted;
    if (persisted.isEmpty) return live;
    return [...persisted, ...live];
  }

  void _trimLiveRoom(String roomId, String gameId) {
    final live = _liveByRoom[roomId];
    if (live == null) return;
    final forGame = live.where((e) => e.push.gameId == gameId).toList();
    // 每彩种最多留最近 6 条实时封盘（约 3 期 × warn+line）
    const maxLive = 6;
    if (forGame.length <= maxLive) return;
    final drop = forGame.take(forGame.length - maxLive).toList();
    final dropKeys = drop.map((e) => e.dedupeKey).toSet();
    live.removeWhere((e) => dropKeys.contains(e.dedupeKey));
    _keysByRoom[roomId]?.removeWhere(dropKeys.contains);
  }

  bool hasDrawsForGame(String roomId, String gameId) {
    return bufferedForGame(roomId, gameId)
        .any((m) => m.type == ChatMessageType.resultCard);
  }

  /// 从本地缓存（WS + 进房预拉）生成历史开奖列表，最新在前。
  List<HistoryDrawRow> historyDrawRowsForGame(
    String roomId,
    String gameId, {
    int maxRows = drawHistoryLimit,
  }) {
    final cacheKey = '$roomId:$gameId:$maxRows';
    final cached = _historyRowsCache[cacheKey];
    if (cached != null) return cached;

    final draws = bufferedForGame(roomId, gameId)
        .where((m) => m.type == ChatMessageType.resultCard)
        .toList();
    draws.sort((a, b) {
      final ai = issueCompareKey(extractIssue(a) ?? '');
      final bi = issueCompareKey(extractIssue(b) ?? '');
      if (ai != bi) return bi.compareTo(ai);
      return b.id.compareTo(a.id);
    });

    final rows = <HistoryDrawRow>[];
    final seenIssueKeys = <int>{};
    for (final draw in draws) {
      final issue = extractIssue(draw);
      final ranks = draw.drawRanks ?? const <int>[];
      if (issue == null || issue.isEmpty || ranks.isEmpty) continue;
      final issueKey = issueCompareKey(issue);
      if (issueKey <= 0 || seenIssueKeys.contains(issueKey)) continue;
      seenIssueKeys.add(issueKey);
      rows.add(
        HistoryDrawRow(
          issue: issue.trim(),
          numbers: ranks,
          summary: ranks.length >= 2 ? '${ranks[0] + ranks[1]}' : '',
        ),
      );
      if (rows.length >= maxRows) break;
    }
    _historyRowsCache[cacheKey] = rows;
    return rows;
  }

  /// 用服务端开奖记录刷新缓存：同逻辑期以 API 重写；丢弃窗口之前的旧期；
  /// 窗口内 API 缺期但本地/WS 已有的开奖保留（可补洞，gap 检测另算）。
  void syncDrawsFromApi({
    required String roomId,
    required String gameId,
    required List<ChatMessageModel> draws,
  }) {
    if (draws.isEmpty) return;
    _ensureMemoryRoom(roomId);
    final keys = _keysByRoom[roomId]!;
    final buffer = _bufferByRoom[roomId]!;

    var minFull = 1 << 62;
    var minKey = 1 << 62;
    final apiIssueKeys = <int>{};
    for (final draw in draws) {
      final issue = extractIssue(draw);
      if (issue != null && issue.isNotEmpty) {
        final key = issueCompareKey(issue);
        final full = int.tryParse(issue.trim()) ?? 0;
        if (key > 0) {
          apiIssueKeys.add(key);
          if (key < minKey) minKey = key;
        }
        if (full >= 10000 && full < minFull) minFull = full;
      }
    }
    if (apiIssueKeys.isEmpty) return;
    if (minFull == 1 << 62) minFull = 0;
    if (minKey == 1 << 62) minKey = 0;

    final kept = <_CachedChatPush>[];
    for (final entry in List<_CachedChatPush>.from(buffer)) {
      if (entry.push.gameId == gameId &&
          entry.push.message.type == ChatMessageType.resultCard) {
        final issue = extractIssue(entry.push.message);
        final issueKey =
            issue != null && issue.isNotEmpty ? issueCompareKey(issue) : 0;
        final full = issue != null ? (int.tryParse(issue.trim()) ?? 0) : 0;
        // 同逻辑期：丢掉本地副本，后面用 API 重写（长号升级）。
        if (issueKey > 0 && apiIssueKeys.contains(issueKey)) {
          keys.remove(entry.dedupeKey);
          continue;
        }
        // 长号：早于 API 最旧一期 → 丢。
        if (minFull > 0 && full >= 10000 && full < minFull) {
          keys.remove(entry.dedupeKey);
          continue;
        }
        // 短号：逻辑期早于 API 窗口 → 丢；窗口内缺期保留（WS 补洞）。
        if (issueKey > 0 && minKey > 0 && issueKey < minKey) {
          keys.remove(entry.dedupeKey);
          continue;
        }
        kept.add(entry);
        continue;
      }
      // 用户下注仅本地缓存：开奖窗口已前移时丢弃更旧期号，避免重启后沉底
      if (entry.push.gameId == gameId &&
          isUserBetChatMessage(entry.push.message)) {
        final issue = extractIssue(entry.push.message);
        if (issue == null || issue.isEmpty) {
          keys.remove(entry.dedupeKey);
          continue;
        }
        final issueKey = issueCompareKey(issue);
        final full = int.tryParse(issue.trim()) ?? 0;
        if (issueKey <= 0 || (minFull > 0 && full >= 10000 && full < minFull)) {
          keys.remove(entry.dedupeKey);
          continue;
        }
        kept.add(entry);
        continue;
      }
      kept.add(entry);
    }

    for (final draw in draws) {
      if (draw.type != ChatMessageType.resultCard) continue;
      final normalized = normalizeStoredChatMessage(draw, gameId: gameId);
      final issue = extractIssue(normalized);
      final key = issue != null && issue.isNotEmpty
          ? drawChatMessageId(gameId, issue)
          : 'api-draw-${normalized.id}';
      if (keys.contains(key)) continue;
      keys.add(key);
      kept.add(
        _CachedChatPush(
          dedupeKey: key,
          push: LotteryChatPush(gameId: gameId, message: normalized),
        ),
      );
    }

    _bufferByRoom[roomId] = kept;
    _trimRoom(roomId);
    _invalidateGameCache(roomId, gameId);
    _schedulePersist(roomId);
  }

  void _ensureMemoryRoom(String roomId) {
    _keysByRoom.putIfAbsent(roomId, () => <String>{});
    _bufferByRoom.putIfAbsent(roomId, () => <_CachedChatPush>[]);
  }

  void _invalidateGameCache(String roomId, String gameId) {
    _timelineCache.remove('$roomId:$gameId');
    _historyRowsCache.removeWhere((k, _) => k.startsWith('$roomId:$gameId:'));
  }

  void _invalidateRoomCache(String roomId) {
    _timelineCache.removeWhere((k, _) => k.startsWith('$roomId:'));
    _historyRowsCache.removeWhere((k, _) => k.startsWith('$roomId:'));
  }

  /// 强制从 buffer 重建（WS 推送后聊天同步用，避免命中旧缓存）。
  List<ChatMessageModel> freshTimelineForGame(
    String roomId,
    String gameId, {
    bool syntheticSeals = true,
  }) {
    _timelineCache.remove('$roomId:$gameId');
    return timelineForGame(roomId, gameId, syntheticSeals: syntheticSeals);
  }

  /// 封盘 + 开奖合并后的聊天时间线（旧→新）。
  /// 默认按历史开奖补封盘（仅展示，不写 buffer）。
  List<ChatMessageModel> timelineForGame(
    String roomId,
    String gameId, {
    bool syntheticSeals = true,
  }) {
    final cacheKey = '$roomId:$gameId';
    final cached = _timelineCache[cacheKey];
    if (cached != null) return cached;

    final timeline = buildChatTimeline(
      messagesForGameTimeline(roomId, gameId),
      gameId: gameId,
      syntheticSeals: syntheticSeals,
    );
    _timelineCache[cacheKey] = timeline;
    return timeline;
  }

  /// 消息较多时在 isolate 构建时间线，避免进聊天首帧卡死。
  Future<List<ChatMessageModel>> timelineForGameAsync(
    String roomId,
    String gameId, {
    bool syntheticSeals = true,
  }) async {
    final cacheKey = '$roomId:$gameId';
    _timelineCache.remove(cacheKey);
    var messages = messagesForGameTimeline(roomId, gameId);
    if (messages.length > 40) {
      final payload = {
        'gameId': gameId,
        'messages': messages.map(_messageToJson).toList(growable: false),
      };
      await compute(buildTimelinePayload, payload);
      messages = messagesForGameTimeline(roomId, gameId);
    }
    final timeline = buildChatTimeline(
      messages,
      gameId: gameId,
      syntheticSeals: syntheticSeals,
    );
    _timelineCache[cacheKey] = timeline;
    return timeline;
  }

  /// 清掉 buffer 里该彩种的封盘系统消息（展示改由 buildChatTimeline 按开奖补全）。
  void purgeSystemMessagesForGame(String roomId, String gameId) {
    final buffer = _bufferByRoom[roomId];
    final keys = _keysByRoom[roomId];
    if (buffer == null || keys == null) return;
    final kept = <_CachedChatPush>[];
    for (final entry in buffer) {
      if (entry.push.gameId == gameId &&
          entry.push.message.type == ChatMessageType.system) {
        keys.remove(entry.dedupeKey);
        continue;
      }
      kept.add(entry);
    }
    _bufferByRoom[roomId] = kept;
    _invalidateGameCache(roomId, gameId);
  }

  /// 兼容旧调用；展示封盘由 [buildChatTimeline] 动态补全，此处仅失效缓存。
  void ensureHistoricalSeals(String roomId, String gameId) {
    _invalidateGameCache(roomId, gameId);
  }

  Future<void> clearRoom(String roomId) async {
    _keysByRoom.remove(roomId);
    _bufferByRoom.remove(roomId);
    _liveByRoom.remove(roomId);
    _loadedRooms.remove(roomId);
    _saveTimers.remove(roomId)?.cancel();
    _invalidateRoomCache(roomId);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_prefPrefix$roomId');
  }

  Future<void> _loadRoom(String roomId, SharedPreferences prefs) async {
    if (_loadedRooms.contains(roomId)) return;
    _loadedRooms.add(roomId);

    final raw = prefs.getString('$_prefPrefix$roomId');
    if (raw == null || raw.isEmpty) {
      _keysByRoom.putIfAbsent(roomId, () => <String>{});
      _bufferByRoom.putIfAbsent(roomId, () => <_CachedChatPush>[]);
      return;
    }

    try {
      final decoded = await compute(decodeChatCachePayload, raw);
      final keys = <String>{};
      final buffer = <_CachedChatPush>[];
      for (final item in decoded) {
        final cached = _CachedChatPush.fromJson(item);
        if (cached == null) continue;
        final gameId = cached.push.gameId;
        final normalized = normalizeStoredChatMessage(
          cached.push.message,
          gameId: gameId,
        );
        final logicalKey =
            _logicalDedupeKey(gameId, normalized) ?? cached.dedupeKey;
        if (keys.contains(logicalKey)) continue;
        keys.add(logicalKey);
        buffer.add(
          _CachedChatPush(
            dedupeKey: logicalKey,
            push: LotteryChatPush(gameId: gameId, message: normalized),
          ),
        );
      }
      _keysByRoom[roomId] = keys;
      _bufferByRoom[roomId] = buffer;
      _trimRoom(roomId);
      _invalidateRoomCache(roomId);
    } catch (_) {
      _keysByRoom.putIfAbsent(roomId, () => <String>{});
      _bufferByRoom.putIfAbsent(roomId, () => <_CachedChatPush>[]);
    }
  }

  void _trimRoom(String roomId) {
    final buffer = _bufferByRoom[roomId];
    final keys = _keysByRoom[roomId];
    if (buffer == null || keys == null || buffer.isEmpty) return;

    final byGame = <String, List<_CachedChatPush>>{};
    for (final entry in buffer) {
      byGame.putIfAbsent(entry.push.gameId, () => []).add(entry);
    }

    final newBuffer = <_CachedChatPush>[];
    final newKeys = <String>{};

    for (final list in byGame.values) {
      final kept = _trimGameEntries(list, keys);
      newBuffer.addAll(kept);
      newKeys.addAll(kept.map((e) => e.dedupeKey));
    }

    newBuffer.sort((a, b) {
      final ai = buffer.indexOf(a);
      final bi = buffer.indexOf(b);
      return ai.compareTo(bi);
    });

    keys.removeWhere((k) {
      if (newKeys.contains(k)) return false;
      // 封盘只占 dedupe、可不在 buffer：trim 后 key 仍必须留下
      if (k.startsWith('seal-warn-') ||
          k.startsWith('sealed-') ||
          k.startsWith('hist-seal-')) {
        return false;
      }
      return true;
    });
    _bufferByRoom[roomId] = newBuffer;
  }

  /// 按类型分别限额：开奖 15、核对/确认卡、下注各自保留，禁止 20 条总配额把核对裁光。
  List<_CachedChatPush> _trimGameEntries(
    List<_CachedChatPush> entries,
    Set<String> keys,
  ) {
    final draws = entries
        .where((e) => e.push.message.type == ChatMessageType.resultCard)
        .toList();
    final userBets = entries
        .where((e) => isUserBetChatMessage(e.push.message))
        .toList();
    final robotMsgs = entries
        .where((e) =>
            e.push.message.type == ChatMessageType.betReceipt ||
            e.push.message.type == ChatMessageType.winCheck ||
            e.push.message.type == ChatMessageType.betListCheck)
        .toList();
    final others = entries
        .where((e) =>
            e.push.message.type != ChatMessageType.resultCard &&
            e.push.message.type != ChatMessageType.betReceipt &&
            e.push.message.type != ChatMessageType.winCheck &&
            e.push.message.type != ChatMessageType.betListCheck &&
            !isUserBetChatMessage(e.push.message))
        .toList();

    final keptDraws = draws.length > maxDrawsPerGame
        ? draws.sublist(draws.length - maxDrawsPerGame)
        : draws;
    final keptUserBets = userBets.length > maxUserBetsPerGame
        ? userBets.sublist(userBets.length - maxUserBetsPerGame)
        : userBets;
    final keptRobot = robotMsgs.length > maxRobotMsgsPerGame
        ? robotMsgs.sublist(robotMsgs.length - maxRobotMsgsPerGame)
        : robotMsgs;
    const maxOthers = 40;
    final keptOthers = others.length > maxOthers
        ? others.sublist(others.length - maxOthers)
        : others;

    final keptSet = <_CachedChatPush>{
      ...keptDraws,
      ...keptUserBets,
      ...keptRobot,
      ...keptOthers,
    };
    for (final e in entries) {
      if (keptSet.contains(e)) continue;
      // 封盘 dedupe key 必须保留：否则 PERIOD_TICK 会每秒重推 → 聊天闪屏
      final k = e.dedupeKey;
      if (k.startsWith('seal-warn-') ||
          k.startsWith('sealed-') ||
          k.startsWith('hist-seal-')) {
        continue;
      }
      keys.remove(k);
    }

    final merged = [...keptDraws, ...keptUserBets, ...keptRobot, ...keptOthers];
    merged.sort((a, b) => entries.indexOf(a).compareTo(entries.indexOf(b)));
    return merged;
  }

  void _schedulePersist(String roomId) {
    if (_persistSuspendCount > 0) return;
    _saveTimers[roomId]?.cancel();
    _saveTimers[roomId] = Timer(const Duration(seconds: 3), () {
      unawaited(_persistRoom(roomId));
    });
  }

  Future<void> _persistRoom(String roomId) async {
    if (_persistSuspendCount > 0) return;
    final buffer = _bufferByRoom[roomId];
    if (buffer == null) return;
    final items = buffer.map((e) => e.toJson()).toList(growable: false);
    final payload = await compute(encodeChatCachePayload, items);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_prefPrefix$roomId', payload);
  }
}

Map<String, dynamic> _messageToJson(ChatMessageModel message) => {
      'id': message.id,
      'sender': message.sender,
      'content': message.content,
      'time': message.time,
      'type': message.type.name,
      'isAdmin': message.isAdmin,
      'isSelf': message.isSelf,
      if (message.issueNo != null) 'issueNo': message.issueNo,
      if (message.drawRanks != null) 'drawRanks': message.drawRanks,
      if (message.avatarUrl != null) 'avatarUrl': message.avatarUrl,
    };

ChatMessageModel? _messageFromJson(Map<String, dynamic> json) {
  final id = json['id']?.toString();
  if (id == null || id.isEmpty) return null;
  final typeName = json['type']?.toString() ?? 'text';
  final type = ChatMessageType.values.firstWhere(
    (t) => t.name == typeName,
    orElse: () => ChatMessageType.text,
  );
  final ranksRaw = json['drawRanks'];
  final List<int>? drawRanks = ranksRaw is List
      ? ranksRaw.map((e) => int.tryParse('$e') ?? 0).where((e) => e > 0).toList()
      : null;
  return ChatMessageModel(
    id: id,
    sender: json['sender']?.toString() == '管理员'
        ? '机器人'
        : (json['sender']?.toString() ?? '机器人'),
    content: json['content']?.toString() ?? '',
    time: json['time']?.toString() ?? '',
    type: type,
    isAdmin: json['isAdmin'] == true,
    isSelf: json['isSelf'] == true,
    issueNo: json['issueNo']?.toString(),
    drawRanks: drawRanks == null || drawRanks.isEmpty ? null : drawRanks,
    avatarUrl: json['avatarUrl']?.toString(),
  );
}
