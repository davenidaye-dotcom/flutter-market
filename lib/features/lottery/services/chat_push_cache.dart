import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../../../data/models/chat_message_model.dart';
import '../../../data/models/check_card_model.dart';
import '../utils/chat_timeline.dart';
import '../utils/check_card_format.dart';
import '../utils/bet_repeat_helper.dart';
import '../utils/draw_history_rows.dart';
import '../widgets/history_draw_panel.dart';
import 'chat_timeline_codec.dart';
import 'chat_cache_store.dart';
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

/// 封盘/开奖等聊天推送的本地缓存（内存 + 文件）。
/// 开奖/封盘/核对卡按期数保留（不按条数裁剪）；下注原文、回执等其余消息
/// 每房间每彩种最多留 [chatWindowSize] 条，超出时从最旧的开始淘汰。
/// 进房时由 [dropOlderThanIssue] 丢掉服务器窗口之外的更早期号。
class ChatPushCache {
  ChatPushCache._();

  static final ChatPushCache instance = ChatPushCache._();

  /// 聊天历史按期数（与后端 CHAT_HISTORY_ISSUE_COUNT 对齐，只用于请求窗口）。
  static const chatHistoryIssueLimit = 15;
  /// 进房预拉、开奖历史表：每彩种向服务器要的最新开奖条数。
  static const drawHistoryLimit = chatHistoryIssueLimit;
  static const serverDrawLimit = drawHistoryLimit;

  /// 每房间每彩种内存里最多保留的非卡片消息条数。
  static const chatWindowSize = 500;

  /// 落盘节流间隔：每个房间 5s 内最多写一次（不是可重置的防抖）。
  @visibleForTesting
  static Duration persistInterval = const Duration(seconds: 5);

  final Map<String, Set<String>> _keysByRoom = {};
  final Map<String, List<_CachedChatPush>> _bufferByRoom = {};
  /// 实时封盘（不落盘）：必须参与 timeline，否则 sync/进页会丢，只剩开奖时 synthetic「一起出现」。
  final Map<String, List<_CachedChatPush>> _liveByRoom = {};
  final Set<String> _loadedRooms = {};
  final Map<String, Timer> _saveTimers = {};
  final Set<String> _dirtyRooms = {};
  final Map<String, Future<void>> _roomLoadInflight = {};
  final Map<String, _TimelineEntry> _timelineCache = {};
  /// roomId → gameId → 窗口内非卡片消息，旧在前。淘汰只动队首。
  final Map<String, Map<String, ListQueue<_CachedChatPush>>> _tailOrder = {};
  /// 已淘汰、但 buffer 里还没物理删除的 dedupeKey（读取/落盘前批量压缩）。
  final Map<String, Set<String>> _evictedPending = {};
  /// roomId:gameId → 变更计数，供页面做廉价签名。
  final Map<String, int> _versions = {};
  final Map<String, List<HistoryDrawRow>> _historyRowsCache = {};
  int _persistSuspendCount = 0;

  /// 键盘/下注交互期间暂停磁盘写入，避免主线程卡顿。
  void suspendPersist() => _persistSuspendCount++;
  void resumePersist() {
    if (_persistSuspendCount > 0) _persistSuspendCount--;
    if (_persistSuspendCount == 0) {
      for (final roomId in _dirtyRooms.toList()) {
        _schedulePersist(roomId);
      }
    }
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
    final future = _loadRoom(roomId);
    _roomLoadInflight[roomId] = future;
    try {
      await future;
    } finally {
      _roomLoadInflight.remove(roomId);
    }
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
    final logicalKey = _logicalDedupeKey(gameId, normalized) ??
        _sealLogicalId(gameId, normalized.id.isNotEmpty ? normalized.id : dedupeKey) ??
        dedupeKey;
    if (_evictedPending[roomId]?.contains(logicalKey) ?? false) {
      _compactRoom(roomId);
    }
    _keysByRoom.putIfAbsent(roomId, () => <String>{});
    _bufferByRoom.putIfAbsent(roomId, () => <_CachedChatPush>[]);
    final tailKind = normalized.type == ChatMessageType.text ||
        normalized.type == ChatMessageType.betReceipt;
    // 只清「同逻辑期」但旧长号 dedupeKey 的别名，不删已存在的 logicalKey 本身。
    // 下注原文和回执没有长短号别名，跳过整表扫描。
    if (!tailKind) {
      _purgeAliasDuplicates(roomId, gameId, normalized, logicalKey);
    }
    final keys = _keysByRoom[roomId]!;
    if (keys.contains(logicalKey)) {
      if (_isSealDedupeKey(logicalKey) &&
          _replaceStoredContent(roomId, logicalKey, normalized)) {
        _invalidateGameCache(roomId, gameId);
        _schedulePersist(roomId);
        return true;
      }
      if ((normalized.type == ChatMessageType.betReceipt ||
              normalized.type == ChatMessageType.betListCheck ||
              normalized.type == ChatMessageType.winCheck) &&
          _replaceIfRicher(roomId, logicalKey, normalized)) {
        _invalidateGameCache(roomId, gameId);
        _schedulePersist(roomId);
        return true;
      }
      if (_upgradeStoredIssueIfLonger(roomId, logicalKey, normalized)) {
        return true;
      }
      return _fillStoredAvatarIfMissing(roomId, logicalKey, normalized);
    }
    keys.add(logicalKey);

    // purge 会替换 buffer list，必须重新取引用再 add
    final entry = _CachedChatPush(
      dedupeKey: logicalKey,
      push: LotteryChatPush(gameId: gameId, message: normalized),
    );
    _bufferByRoom[roomId]!.add(entry);
    if (_isWindowed(normalized)) _trackTail(roomId, gameId, entry);
    if (_appendTimelineTail(roomId, gameId, normalized)) {
      _bumpVersion(roomId, gameId);
    } else {
      _invalidateGameCache(roomId, gameId);
    }
    _schedulePersist(roomId);
    return true;
  }

  /// 下注原文/回执/失败卡等占 [chatWindowSize] 窗口；开奖、封盘、核对卡不占，按期数留。
  bool _isWindowed(ChatMessageModel m) =>
      m.type == ChatMessageType.text ||
      m.type == ChatMessageType.betReceipt ||
      m.type == ChatMessageType.image;

  ListQueue<_CachedChatPush> _tailQueue(String roomId, String gameId) =>
      (_tailOrder.putIfAbsent(roomId, () => {}))
          .putIfAbsent(gameId, () => ListQueue<_CachedChatPush>());

  /// 窗口内条数（供历史翻页判断是否已到 500 上限）。
  int windowedCount(String roomId, String gameId) =>
      _tailOrder[roomId]?[gameId]?.length ?? 0;

  void _trackTail(String roomId, String gameId, _CachedChatPush entry) {
    final queue = _tailQueue(roomId, gameId)..addLast(entry);
    if (queue.length > chatWindowSize) _evictOverflow(roomId, gameId);
  }

  /// 只淘汰最旧的；dedupe key 同步移除，buffer/timeline 里的残留批量清理。
  void _evictOverflow(String roomId, String gameId) {
    final queue = _tailOrder[roomId]?[gameId];
    if (queue == null) return;
    final keys = _keysByRoom[roomId];
    final pending = _evictedPending.putIfAbsent(roomId, () => <String>{});
    final timeline = _timelineCache['$roomId:$gameId:syn=true'];
    while (queue.length > chatWindowSize) {
      final old = queue.removeFirst();
      keys?.remove(old.dedupeKey);
      pending.add(old.dedupeKey);
      timeline?.evict.add(old.push.message.id);
    }
    _timelineCache.remove('$roomId:$gameId:syn=false');
    _bumpVersion(roomId, gameId);
  }

  /// 物理删除 buffer 里已淘汰的条目（O(N)，只在读取/落盘/重复键回流时做）。
  void _compactRoom(String roomId) {
    final pending = _evictedPending[roomId];
    if (pending == null || pending.isEmpty) return;
    _bufferByRoom[roomId]?.removeWhere(
      (e) => pending.contains(e.dedupeKey) && _isWindowed(e.push.message),
    );
    pending.clear();
  }

  /// buffer 被整体重建后（丢旧期/API 覆盖/清系统消息）重算窗口队列，并按窗口淘汰。
  void _rebuildTailIndex(String roomId) {
    _compactRoom(roomId);
    final buffer = _bufferByRoom[roomId];
    _tailOrder.remove(roomId);
    if (buffer == null) return;
    final games = <String>{};
    for (final e in buffer) {
      if (!_isWindowed(e.push.message)) continue;
      _tailQueue(roomId, e.push.gameId).addLast(e);
      games.add(e.push.gameId);
    }
    for (final g in games) {
      if ((_tailOrder[roomId]?[g]?.length ?? 0) > chatWindowSize) {
        _evictOverflow(roomId, g);
      }
    }
    _compactRoom(roomId);
  }

  /// 历史翻页：older（旧→新）插到窗口最前面，只收窗口剩余容量内最新的那些，
  /// 不会挤掉已在窗口里的新消息。返回实际收下的条数。
  int prependHistory({
    required String roomId,
    required String gameId,
    required List<ChatMessageModel> older,
  }) {
    if (older.isEmpty) return 0;
    _compactRoom(roomId);
    final keys = _keysByRoom.putIfAbsent(roomId, () => <String>{});
    final buffer = _bufferByRoom.putIfAbsent(roomId, () => <_CachedChatPush>[]);
    final queue = _tailQueue(roomId, gameId);
    var room = chatWindowSize - queue.length;
    final accepted = <_CachedChatPush>[];
    final cards = <ChatMessageModel>[];
    for (var i = older.length - 1; i >= 0; i--) {
      final m = normalizeStoredChatMessage(older[i], gameId: gameId);
      if (!_isWindowed(m)) {
        cards.add(m);
        continue;
      }
      if (room <= 0) continue;
      final key = m.id.isNotEmpty ? m.id : 'api-${m.type.name}-${m.content.hashCode}';
      if (keys.contains(key)) continue;
      keys.add(key);
      accepted.add(_CachedChatPush(
        dedupeKey: key,
        push: LotteryChatPush(gameId: gameId, message: m),
      ));
      room--;
    }
    // accepted 是新→旧；队首要旧的，所以逐个 addFirst（最旧最后加）。
    for (final e in accepted) {
      queue.addFirst(e);
    }
    buffer.insertAll(0, accepted.reversed);
    for (final card in cards.reversed) {
      pushOnce(
        roomId: roomId,
        dedupeKey: card.id,
        gameId: gameId,
        message: card,
      );
    }
    if (accepted.isNotEmpty) {
      _invalidateGameCache(roomId, gameId);
      _schedulePersist(roomId);
    }
    return accepted.length;
  }

  /// 把 CHECK_SELF（自己的名次/未中奖）并进已有核对卡；卡不存在返回 null（调用方先缓冲）。
  ChatMessageModel? applyCheckSelf({
    required String roomId,
    required String gameId,
    required List<String> cardIds,
    int? rank,
    Map<String, dynamic>? row,
    bool lost = false,
  }) {
    final buffer = _bufferByRoom[roomId];
    if (buffer == null) return null;
    for (var i = 0; i < buffer.length; i++) {
      final entry = buffer[i];
      final message = entry.push.message;
      if (entry.push.gameId != gameId) continue;
      if (message.type != ChatMessageType.betListCheck &&
          message.type != ChatMessageType.winCheck) {
        continue;
      }
      if (!cardIds.contains(entry.dedupeKey) && !cardIds.contains(message.id)) {
        continue;
      }
      final card = message.checkCard ??
          CheckCardData(isWin: message.type == ChatMessageType.winCheck);
      final next = card.withSelf(
        rank: rank,
        row: row == null ? null : CheckRow(row),
        lost: lost,
      );
      final updated = message.copyWith(
        checkCard: next,
        content: composeCheckCardText(
          data: next,
          issue: extractIssue(message) ?? '',
        ),
      );
      buffer[i] = _CachedChatPush(
        dedupeKey: entry.dedupeKey,
        push: LotteryChatPush(gameId: gameId, message: updated),
      );
      _invalidateGameCache(roomId, gameId);
      _schedulePersist(roomId);
      return updated;
    }
    return null;
  }

  /// 该房间彩种的变更计数；任何缓存内容变化都会递增。
  int timelineVersion(String roomId, String gameId) =>
      _versions['$roomId:$gameId'] ?? 0;

  void _bumpVersion(String roomId, String gameId) {
    final k = '$roomId:$gameId';
    _versions[k] = (_versions[k] ?? 0) + 1;
  }

  /// `sealed-JS_SC-34163647` 与 `sealed-JS_SC-3647` 视为同一条封盘。
  String? _sealLogicalId(String gameId, String id) {
    final warn = 'seal-warn-$gameId-';
    final line = 'sealed-$gameId-';
    final String issue;
    final String prefix;
    if (id.startsWith(warn)) {
      issue = id.substring(warn.length);
      prefix = warn;
    } else if (id.startsWith(line)) {
      issue = id.substring(line.length);
      prefix = line;
    } else {
      return null;
    }
    final key = issueCompareKey(issue);
    if (key <= 0) return id;
    return '$prefix$key';
  }

  bool _isSealDedupeKey(String key) =>
      key.startsWith('seal-warn-') ||
      key.startsWith('sealed-') ||
      key.startsWith('hist-seal-');

  /// 同一封盘键已在缓存时，用后端新正文覆盖（本地旧文案不再占坑）。
  bool _replaceStoredContent(
    String roomId,
    String logicalKey,
    ChatMessageModel incoming,
  ) {
    if (incoming.content.trim().isEmpty) return false;
    var changed = false;

    bool patch(List<_CachedChatPush>? list) {
      if (list == null) return false;
      var found = false;
      for (var i = 0; i < list.length; i++) {
        final entry = list[i];
        if (entry.dedupeKey != logicalKey) continue;
        found = true;
        final existing = entry.push.message;
        if (existing.content == incoming.content) continue;
        list[i] = _CachedChatPush(
          dedupeKey: logicalKey,
          push: LotteryChatPush(
            gameId: entry.push.gameId,
            message: existing.copyWith(
              content: incoming.content,
              issueNo: incoming.issueNo ?? existing.issueNo,
              time: incoming.time.isNotEmpty ? incoming.time : existing.time,
            ),
          ),
        );
        changed = true;
      }
      return found;
    }

    patch(_bufferByRoom[roomId]);
    patch(_liveByRoom[roomId]);
    return changed;
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
      final incomingCard = incoming.checkCard;
      if (incomingCard != null) {
        // 核对卡：以结构化信息为准（带自己名次的、行更多的更全）
        final existingCard = entry.push.message.checkCard;
        if (existingCard != null && !incomingCard.richerThan(existingCard)) {
          return false;
        }
      } else if (incoming.content.trim().length <= existing.trim().length) {
        return false;
      }
      buffer[i] = _CachedChatPush(
        dedupeKey: logicalKey,
        push: LotteryChatPush(gameId: entry.push.gameId, message: incoming),
      );
      return true;
    }
    return false;
  }

  /// 进房历史补上的头像：本地已有同一条、但当时接口没带头像时，补上并刷新。
  bool _fillStoredAvatarIfMissing(
    String roomId,
    String logicalKey,
    ChatMessageModel incoming,
  ) {
    final incomingAvatar = incoming.avatarUrl?.trim();
    if (incomingAvatar == null || incomingAvatar.isEmpty) return false;
    final buffer = _bufferByRoom[roomId];
    if (buffer == null) return false;
    for (var i = 0; i < buffer.length; i++) {
      final entry = buffer[i];
      if (entry.dedupeKey != logicalKey) continue;
      final existing = entry.push.message;
      final existingAvatar = existing.avatarUrl?.trim();
      if (existingAvatar != null && existingAvatar.isNotEmpty) return false;
      buffer[i] = _CachedChatPush(
        dedupeKey: logicalKey,
        push: LotteryChatPush(
          gameId: entry.push.gameId,
          message: existing.copyWith(avatarUrl: incomingAvatar),
        ),
      );
      _invalidateGameCache(roomId, entry.push.gameId);
      _schedulePersist(roomId);
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
      final upgraded = existing.copyWith(
        content: existing.type == ChatMessageType.resultCard
            ? '第$preferred期开奖'
            : existing.content,
        issueNo: preferred,
        drawRanks: existing.drawRanks ?? incoming.drawRanks,
        avatarUrl: existing.avatarUrl ?? incoming.avatarUrl,
        seq: existing.seq > 0 ? existing.seq : incoming.seq,
        pair: existing.seq > 0 ? existing.pair : incoming.pair,
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
  bool emitLive({
    required String roomId,
    required String dedupeKey,
    required String gameId,
    required ChatMessageModel message,
  }) {
    final normalized = normalizeStoredChatMessage(message, gameId: gameId);
    final logicalKey = _logicalDedupeKey(gameId, normalized) ??
        _sealLogicalId(gameId, normalized.id.isNotEmpty ? normalized.id : dedupeKey) ??
        dedupeKey;
    final keys = _keysByRoom.putIfAbsent(roomId, () => <String>{});
    final live = _liveByRoom.putIfAbsent(roomId, () => <_CachedChatPush>[]);
    final alreadyLive = live.any((e) => e.dedupeKey == logicalKey);
    if (keys.contains(logicalKey)) {
      if (_isSealDedupeKey(logicalKey) &&
          _replaceStoredContent(roomId, logicalKey, normalized)) {
        _invalidateGameCache(roomId, gameId);
        return true;
      }
      // key 已有：只补 live 体给 timeline，返回 false 避免每秒重推闪屏
      if (!alreadyLive) {
        live.add(
          _CachedChatPush(
            dedupeKey: logicalKey,
            push: LotteryChatPush(gameId: gameId, message: normalized),
          ),
        );
        _trimLiveRoom(roomId, gameId);
        _invalidateGameCache(roomId, gameId);
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
    _invalidateGameCache(roomId, gameId);
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
    _invalidateGameCache(roomId, gameId);
  }

  List<ChatMessageModel> liveForGame(String roomId, String gameId) {
    final live = _liveByRoom[roomId];
    if (live == null || live.isEmpty) return const [];
    return live
        .where((e) => e.push.gameId == gameId)
        .map((e) => e.push.message)
        .toList(growable: false);
  }

  /// 丢掉该彩种比 [oldestIssue] 更早的消息，以及没有期号也没有球号的空开奖卡。
  void dropOlderThanIssue({
    required String roomId,
    required String gameId,
    required String oldestIssue,
  }) {
    final floor = oldestIssue.trim();
    if (gameId.isEmpty || floor.isEmpty) return;
    final keys = _keysByRoom[roomId];
    var changed = false;

    bool shouldDrop(ChatMessageModel message) {
      if (message.type == ChatMessageType.resultCard) {
        final issue = extractIssue(message);
        final ranks = message.drawRanks ?? const <int>[];
        if ((issue == null || issue.isEmpty) &&
            ranks.isEmpty &&
            message.content.trim().isEmpty) {
          return true;
        }
      }
      final issue = extractIssue(message);
      if (issue == null || issue.isEmpty) return false;
      return compareIssueNo(issue, floor) < 0;
    }

    final buffer = _bufferByRoom[roomId];
    if (buffer != null) {
      final kept = <_CachedChatPush>[];
      for (final entry in buffer) {
        if (entry.push.gameId == gameId && shouldDrop(entry.push.message)) {
          keys?.remove(entry.dedupeKey);
          changed = true;
          continue;
        }
        kept.add(entry);
      }
      _bufferByRoom[roomId] = kept;
      _rebuildTailIndex(roomId);
    }

    final live = _liveByRoom[roomId];
    if (live != null) {
      live.removeWhere((entry) {
        if (entry.push.gameId != gameId || !shouldDrop(entry.push.message)) {
          return false;
        }
        keys?.remove(entry.dedupeKey);
        changed = true;
        return true;
      });
    }

    if (!changed) return;
    _invalidateGameCache(roomId, gameId);
    _schedulePersist(roomId);
  }

  List<ChatMessageModel> bufferedForGame(String roomId, String gameId) {
    _compactRoom(roomId);
    final buffer = _bufferByRoom[roomId];
    if (buffer == null || buffer.isEmpty) return const [];
    return [
      for (final e in buffer)
        if (e.push.gameId == gameId) e.push.message,
    ];
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

    _compactRoom(roomId);
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
    _rebuildTailIndex(roomId);
    _invalidateGameCache(roomId, gameId);
    _schedulePersist(roomId);
  }

  void _ensureMemoryRoom(String roomId) {
    _keysByRoom.putIfAbsent(roomId, () => <String>{});
    _bufferByRoom.putIfAbsent(roomId, () => <_CachedChatPush>[]);
  }

  void _invalidateGameCache(String roomId, String gameId) {
    final prefix = '$roomId:$gameId';
    _versions[prefix] = (_versions[prefix] ?? 0) + 1;
    _timelineCache.removeWhere((k, _) => k == prefix || k.startsWith('$prefix:'));
    _historyRowsCache.removeWhere((k, _) => k.startsWith('$roomId:$gameId:'));
  }

  /// 新消息能排在当前时间线最后时直接接上（原地 add，不复制整表）。
  /// 返回 false 表示需要整表重排。
  bool _appendTimelineTail(
    String roomId,
    String gameId,
    ChatMessageModel message,
  ) {
    // 与 timelineForGame 默认 syntheticSeals=true 的缓存键一致。
    final entry = _timelineCache['$roomId:$gameId:syn=true'];
    if (entry == null) return false;
    if (entry.ids.contains(message.id)) return true;
    if (!appendsAtTimelineTail(entry.list, message)) return false;
    entry.list.add(message);
    entry.ids.add(message.id);
    _timelineCache.remove('$roomId:$gameId:syn=false');
    return true;
  }

  void dropMessage({
    required String roomId,
    required String gameId,
    required String dedupeKey,
  }) {
    _keysByRoom[roomId]?.remove(dedupeKey);
    _bufferByRoom[roomId]?.removeWhere((e) => e.dedupeKey == dedupeKey);
    _tailOrder[roomId]?[gameId]?.removeWhere((e) => e.dedupeKey == dedupeKey);
    _invalidateGameCache(roomId, gameId);
  }

  /// 本地点发送的下注，在拿到注单号后改成和服务端同一条，避免回声再插一条。
  void adoptLocalBet({
    required String roomId,
    required String gameId,
    required String localId,
    required String orderId,
  }) {
    final serverId = 'bet-chat-$gameId-$orderId';
    final keys = _keysByRoom[roomId];
    final buffer = _bufferByRoom[roomId];
    if (keys == null || buffer == null) return;
    ChatMessageModel? local;
    buffer.removeWhere((e) {
      if (e.dedupeKey != localId) return false;
      local = e.push.message;
      return true;
    });
    keys.remove(localId);
    _tailOrder[roomId]?[gameId]?.removeWhere((e) => e.dedupeKey == localId);
    if (keys.contains(serverId)) {
      // WS 已占 serverId：把本地头像/isSelf 补上去，避免开确认后头像丢失。
      final fromLocal = local;
      if (fromLocal != null) {
        for (var i = 0; i < buffer.length; i++) {
          final entry = buffer[i];
          if (entry.dedupeKey != serverId) continue;
          final existing = entry.push.message;
          final existingAv = existing.avatarUrl?.trim() ?? '';
          final localAv = fromLocal.avatarUrl?.trim() ?? '';
          buffer[i] = _CachedChatPush(
            dedupeKey: serverId,
            push: LotteryChatPush(
              gameId: entry.push.gameId,
              message: existing.copyWith(
                isSelf: existing.isSelf || fromLocal.isSelf,
                avatarUrl: existingAv.isNotEmpty
                    ? existing.avatarUrl
                    : (localAv.isEmpty ? existing.avatarUrl : fromLocal.avatarUrl),
                accountId: existing.accountId ?? fromLocal.accountId,
              ),
            ),
          );
          break;
        }
      }
      _invalidateGameCache(roomId, gameId);
      _schedulePersist(roomId);
      return;
    }
    final kept = local;
    if (kept == null) {
      _invalidateGameCache(roomId, gameId);
      return;
    }
    final adopted = kept.copyWith(id: serverId);
    keys.add(serverId);
    final entry = _CachedChatPush(
      dedupeKey: serverId,
      push: LotteryChatPush(gameId: gameId, message: adopted),
    );
    buffer.add(entry);
    if (_isWindowed(adopted)) _trackTail(roomId, gameId, entry);
    _invalidateGameCache(roomId, gameId);
  }

  void _invalidateRoomCache(String roomId) {
    for (final k in _versions.keys.where((k) => k.startsWith('$roomId:')).toList()) {
      _versions[k] = (_versions[k] ?? 0) + 1;
    }
    _timelineCache.removeWhere((k, _) => k.startsWith('$roomId:'));
    _historyRowsCache.removeWhere((k, _) => k.startsWith('$roomId:'));
  }

  /// 强制从 buffer 重建（WS 推送后聊天同步用，避免命中旧缓存）。
  List<ChatMessageModel> freshTimelineForGame(
    String roomId,
    String gameId, {
    bool syntheticSeals = true,
  }) {
    _invalidateGameCache(roomId, gameId);
    return timelineForGame(roomId, gameId, syntheticSeals: syntheticSeals);
  }

  /// 封盘 + 开奖合并后的聊天时间线（旧→新）。
  /// [syntheticSeals]：历史开奖缺封盘推送时补预警/封盘线快照。
  List<ChatMessageModel> timelineForGame(
    String roomId,
    String gameId, {
    bool syntheticSeals = true,
  }) {
    final cacheKey = '$roomId:$gameId:syn=$syntheticSeals';
    final cached = _timelineCache[cacheKey];
    if (cached != null) return cached.snapshot();

    final timeline = buildChatTimeline(
      messagesForGameTimeline(roomId, gameId),
      gameId: gameId,
      syntheticSeals: syntheticSeals,
    );
    final entry = _timelineCache[cacheKey] = _TimelineEntry(timeline);
    return entry.snapshot();
  }

  /// 消息较多时在 isolate 构建时间线，避免进聊天首帧卡死。
  Future<List<ChatMessageModel>> timelineForGameAsync(
    String roomId,
    String gameId, {
    bool syntheticSeals = true,
  }) async {
    final cacheKey = '$roomId:$gameId:syn=$syntheticSeals';
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
    final entry = _timelineCache[cacheKey] = _TimelineEntry(timeline);
    return entry.snapshot();
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
    _rebuildTailIndex(roomId);
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
    _dirtyRooms.remove(roomId);
    _tailOrder.remove(roomId);
    _evictedPending.remove(roomId);
    _invalidateRoomCache(roomId);
    await ChatCacheStore.delete(roomId);
  }

  Future<void> _loadRoom(String roomId) async {
    if (_loadedRooms.contains(roomId)) return;
    _loadedRooms.add(roomId);

    final stored = await ChatCacheStore.read(roomId);
    final raw = stored.payload;
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
      // 读盘期间已经收到的实时推送不能丢
      final liveBuffer = _bufferByRoom[roomId];
      if (liveBuffer != null) {
        for (final e in liveBuffer) {
          if (keys.add(e.dedupeKey)) buffer.add(e);
        }
      }
      _keysByRoom[roomId] = keys;
      _bufferByRoom[roomId] = buffer;
      _rebuildTailIndex(roomId);
      _invalidateRoomCache(roomId);
      if (stored.migrated) _schedulePersist(roomId);
    } catch (_) {
      _keysByRoom.putIfAbsent(roomId, () => <String>{});
      _bufferByRoom.putIfAbsent(roomId, () => <_CachedChatPush>[]);
    }
  }

  /// 节流落盘：房间脏了就排一个 [persistInterval] 后的写入；已排上则不再顺延。
  void _schedulePersist(String roomId) {
    _dirtyRooms.add(roomId);
    if (_persistSuspendCount > 0) return;
    if (_saveTimers.containsKey(roomId)) return;
    _saveTimers[roomId] = Timer(persistInterval, () {
      _saveTimers.remove(roomId);
      unawaited(_persistRoom(roomId));
    });
  }

  /// 只写窗口内消息（每彩种 ≤500）+ 各类卡片。
  Future<void> _persistRoom(String roomId) async {
    if (_persistSuspendCount > 0) return;
    _compactRoom(roomId);
    final buffer = _bufferByRoom[roomId];
    if (buffer == null) return;
    _dirtyRooms.remove(roomId);
    final items = buffer.map((e) => e.toJson()).toList(growable: false);
    final payload = items.length > 200
        ? await compute(encodeChatCachePayload, items)
        : encodeChatCachePayload(items);
    await ChatCacheStore.write(roomId, payload);
  }
}

/// 时间线缓存：原地追加，淘汰的 id 先记账，读取时批量清除。
class _TimelineEntry {
  _TimelineEntry(List<ChatMessageModel> source)
      : list = List<ChatMessageModel>.of(source),
        ids = {for (final m in source) m.id};

  final List<ChatMessageModel> list;
  final Set<String> ids;
  final Set<String> evict = {};

  /// 返回给外部的快照：缓存内部列表会被原地追加，外部不能持有它。
  List<ChatMessageModel> snapshot() {
    if (evict.isNotEmpty) {
      list.removeWhere((m) => evict.contains(m.id));
      ids.removeAll(evict);
      evict.clear();
    }
    return List<ChatMessageModel>.of(list);
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
      if (message.accountId != null) 'accountId': message.accountId,
      if (message.seq > 0) 'seq': message.seq,
      if (message.pair > 0) 'pair': message.pair,
      if (message.checkCard != null) 'chk': message.checkCard!.toJson(),
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
  final accountId = json['accountId']?.toString().trim();
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
    accountId: (accountId == null || accountId.isEmpty) ? null : accountId,
    seq: int.tryParse('${json['seq']}') ?? 0,
    pair: int.tryParse('${json['pair']}') ?? 0,
    checkCard: CheckCardData.fromJson(json['chk']),
  );
}
