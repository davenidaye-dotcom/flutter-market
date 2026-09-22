import 'package:flutter/foundation.dart';

import '../../../data/models/lottery_game_model.dart';
import '../utils/draw_history_rows.dart';
import '../utils/lottery_period_ui.dart';

/// 开奖露出事件：由 provider 推入聊天，引擎不碰 ChatPushCache。
class DrawRevealEvent {
  const DrawRevealEvent({
    required this.gameId,
    required this.issue,
    required this.ranks,
  });
  final String gameId;
  final String issue;
  final List<int> ranks;
}

/// 封盘聊天事件（warn=20s 预警，sealed=封盘线）。
class SealRevealEvent {
  const SealRevealEvent({
    required this.gameId,
    required this.kind,
    required this.issue,
  });
  final String gameId;
  final String kind;
  final String issue;
}

class PeriodTickResult {
  const PeriodTickResult({
    this.draws = const [],
    this.seals = const [],
    this.changed = false,
  });

  final List<DrawRevealEvent> draws;
  final List<SealRevealEvent> seals;
  final bool changed;

  static const none = PeriodTickResult();
}

class _GameSlot {
  _GameSlot(this.model);

  LotteryGameModel model;
  bool wsSynced = false;
  DateTime? openDeadline;
  int? prevCd;
}

/// 期态：距封盘用 sealAtEpochMs，封盘中用 openAtEpochMs，与 web `lotteryFeed` 同一套时刻。
/// 聊天封盘线不在这里生成，只消费后端 WS / 历史消息。
final class LotteryPeriodEngine {
  /// 兼容旧测试引用；开奖中最短展示由 WS 换期包到达决定，不再人为 hold。
  static const revealHold = Duration(milliseconds: 800);

  final Map<String, _GameSlot> _slots = {};

  List<LotteryGameModel> get games =>
      _slots.values.map(_toDisplay).toList(growable: false);

  LotteryGameModel? gameById(String id) {
    final s = _slots[id];
    return s == null ? null : _toDisplay(s);
  }

  bool needsTicker(String gameId) {
    final s = _slots[gameId];
    return s != null && _slotNeedsTicker(s);
  }

  bool needsAnyTicker() => _slots.values.any(_slotNeedsTicker);

  void reset() => _slots.clear();

  bool get hasLiveState => _slots.values.any((s) => s.wsSynced);

  bool get allWsSynced =>
      _slots.isNotEmpty && _slots.values.every((s) => s.wsSynced);

  bool isGameWsSynced(String gameId) {
    final s = _slots[gameId];
    return s != null && s.wsSynced;
  }

  bool hasHeldDraws(String gameId) => false;

  void bootstrap(List<LotteryGameModel> list, DateTime now) {
    _slots.clear();
    for (final g in list) {
      final slot = _GameSlot(g);
      slot.openDeadline = _deadlineFromModel(g, now);
      slot.prevCd = _secondsLeft(slot, now);
      _slots[g.id] = slot;
    }
  }

  void mergeHttpSnapshot(List<LotteryGameModel> list, DateTime now) {
    for (final g in list) {
      final existing = _slots[g.id];
      if (existing != null) {
        existing.model = existing.model.copyWith(
          name: g.name.isNotEmpty ? g.name : existing.model.name,
          currentIssue: g.currentIssue.isNotEmpty
              ? _pickNewer(g.currentIssue, existing.model.currentIssue)
              : existing.model.currentIssue,
          sealSeconds: g.sealSeconds ?? existing.model.sealSeconds,
          openAtEpochMs: g.openAtEpochMs ?? existing.model.openAtEpochMs,
          sealAtEpochMs: g.sealAtEpochMs ?? existing.model.sealAtEpochMs,
        );
        final openAt = g.openAtEpochMs;
        if (openAt != null && openAt > 0) {
          existing.openDeadline = DateTime.fromMillisecondsSinceEpoch(openAt);
          existing.model = existing.model.copyWith(openAtEpochMs: openAt);
        }
        _mergeHttpDraw(existing, g);
        _recoverStuckCountdown(existing, g, now);
        continue;
      }
      final slot = _GameSlot(g);
      slot.openDeadline = _deadlineFromModel(g, now);
      slot.prevCd = _secondsLeft(slot, now);
      _slots[g.id] = slot;
    }
  }

  /// 按服务端启用彩种对齐目录：合并期态，并移除已关闭彩种。
  void syncCatalog(List<LotteryGameModel> list, DateTime now) {
    final enabledIds = list.map((g) => g.id).where((id) => id.isNotEmpty).toSet();
    _slots.removeWhere((id, _) => !enabledIds.contains(id));
    mergeHttpSnapshot(list, now);
  }

  void _recoverStuckCountdown(
    _GameSlot slot,
    LotteryGameModel g,
    DateTime now,
  ) {
    if (_secondsLeft(slot, now) > 0) return;
    final httpDeadline = _deadlineFromModel(g, now);
    if (httpDeadline == null) return;
    final httpLeft = mathMax(0, httpDeadline.difference(now).inSeconds);
    if (httpLeft <= 0) return;

    if (g.currentIssue.isNotEmpty) {
      final newer = _pickNewer(g.currentIssue, slot.model.currentIssue);
      if (!_sameIssue(newer, slot.model.currentIssue)) {
        slot.model = slot.model.copyWith(currentIssue: newer);
      }
    }

    _syncCountdown(
      slot,
      seconds: httpLeft,
      openAtMs: g.openAtEpochMs,
      now: now,
      force: true,
    );
  }

  void _mergeHttpDraw(_GameSlot slot, LotteryGameModel g) {
    final httpPrev = g.previousIssue ?? '';
    if (httpPrev.isEmpty || g.previousResults.isEmpty) return;

    if (slot.model.currentIssue.isNotEmpty &&
        compareIssueNo(httpPrev, slot.model.currentIssue) >= 0) {
      return;
    }

    final prev = slot.model.previousIssue ?? '';
    final cmp = prev.isEmpty ? 1 : compareIssueNo(httpPrev, prev);
    if (cmp > 0) {
      slot.model = slot.model.copyWith(
        previousIssue: preferFullIssueNo(httpPrev, prev),
        previousResults: g.previousResults,
      );
    } else if (cmp == 0) {
      final local = slot.model.previousResults;
      if (local.isEmpty && g.previousResults.isNotEmpty) {
        slot.model = slot.model.copyWith(previousResults: g.previousResults);
      }
    }
  }

  int countdownFor(String gameId, DateTime now) {
    final s = _slots[gameId];
    if (s == null) return 0;
    return _secondsLeft(s, now);
  }

  bool isDrawingPhase(String gameId, DateTime now) {
    final s = _slots[gameId];
    if (s == null) return false;
    return _secondsLeft(s, now) <= 0;
  }

  LotteryGameModel displayGame(String gameId, DateTime now) {
    final s = _slots[gameId];
    if (s == null) {
      return const LotteryGameModel(id: '', name: '', currentIssue: '');
    }
    return _toDisplay(s, now);
  }

  PeriodTickResult onPeriodTick(
    String gameId, {
    required String issue,
    required int seconds,
    int? openAtEpochMs,
    int? sealAtEpochMs,
    int? sealSeconds,
    String? lastIssue,
    List<int> lastRanks = const [],
    DateTime? now,
  }) {
    // 已从大厅目录移除的彩种：忽略 WS，禁止 putIfAbsent 把关掉的玩法加回来
    final existing = _slots[gameId];
    if (existing == null) return PeriodTickResult.none;

    final clock = now ?? DateTime.now();
    final slot = existing;

    if (sealSeconds != null && sealSeconds > 0) {
      slot.model = slot.model.copyWith(sealSeconds: sealSeconds);
    }

    final first = !slot.wsSynced;
    if (first) slot.wsSynced = true;

    if (issue.isNotEmpty) {
      final newer = _pickNewer(issue, slot.model.currentIssue);
      final issueChanged = !_sameIssue(newer, slot.model.currentIssue);
      if (issueChanged || first) {
        // 与 PC mergePeriod 一致：PERIOD_TICK/SNAPSHOT 的 issueNo 以服务端为准。
        slot.model = slot.model.copyWith(currentIssue: newer);
      }
    }

    // 时刻以本包为准，与 web mergePeriod 一样后来的包覆盖。不用 sealSeconds 回写 sealAt。
    _syncCountdown(
      slot,
      seconds: seconds,
      openAtMs: openAtEpochMs,
      now: clock,
      force: first && slot.openDeadline == null,
    );
    if (sealAtEpochMs != null && sealAtEpochMs > 0) {
      slot.model = slot.model.copyWith(sealAtEpochMs: sealAtEpochMs);
    }

    var draws = const <DrawRevealEvent>[];
    final resolvedLastIssue = lastIssue ?? '';
    if (resolvedLastIssue.isNotEmpty && lastRanks.isNotEmpty) {
      draws = _ingestDraw(
        gameId,
        slot,
        resolvedLastIssue,
        lastRanks,
        clock,
        force: first,
      );
    }

    return PeriodTickResult(draws: draws, changed: true);
  }

  PeriodTickResult onDrawResult(
    String gameId, {
    required String issue,
    required List<int> ranks,
    DateTime? now,
  }) {
    if (issue.isEmpty || ranks.isEmpty) return PeriodTickResult.none;
    final slot = _slots[gameId];
    if (slot == null) return PeriodTickResult.none;
    final clock = now ?? DateTime.now();
    if (!slot.wsSynced) slot.wsSynced = true;

    // DRAW_RESULT 是服务端权威：本地 CD 未归零也必须立刻出号（勿等 tick，否则 WIN_LIST 先上屏）。
    final draws = _ingestDraw(gameId, slot, issue, ranks, clock, force: true);
    return PeriodTickResult(draws: draws, changed: draws.isNotEmpty);
  }

  PeriodTickResult onSecondTick(DateTime now) {
    var changed = false;

    for (final slot in _slots.values) {
      final cd = _secondsLeft(slot, now);
      if (slot.prevCd != cd) {
        slot.prevCd = cd;
        changed = true;
      }
    }

    return PeriodTickResult(changed: changed);
  }

  void patchGame(LotteryGameModel patch, DateTime now) {
    final slot = _slots[patch.id];
    if (slot == null) {
      final s = _GameSlot(patch);
      s.openDeadline = _deadlineFromModel(patch, now);
      s.prevCd = _secondsLeft(s, now);
      _slots[patch.id] = s;
      return;
    }
    final localPrev = slot.model.previousIssue ?? '';
    var nextPrevIssue = slot.model.previousIssue;
    var nextResults = slot.model.previousResults;
    if (patch.previousIssue != null && patch.previousIssue!.isNotEmpty) {
      final cmp = localPrev.isEmpty
          ? 1
          : compareIssueNo(patch.previousIssue!, localPrev);
      if (cmp > 0) {
        nextPrevIssue = preferFullIssueNo(patch.previousIssue!, localPrev);
        if (patch.previousResults.isNotEmpty) {
          nextResults = patch.previousResults;
        }
      } else if (cmp == 0) {
        nextPrevIssue = preferFullIssueNo(patch.previousIssue!, localPrev);
        if (nextResults.isEmpty && patch.previousResults.isNotEmpty) {
          nextResults = patch.previousResults;
        }
      }
    }
    slot.model = slot.model.copyWith(
      name: patch.name.isNotEmpty ? patch.name : slot.model.name,
      currentIssue: patch.currentIssue.isNotEmpty
          ? _pickNewer(patch.currentIssue, slot.model.currentIssue)
          : slot.model.currentIssue,
      previousIssue: nextPrevIssue,
      previousResults: nextResults,
      openAtEpochMs: patch.openAtEpochMs ?? slot.model.openAtEpochMs,
      sealAtEpochMs: patch.sealAtEpochMs ?? slot.model.sealAtEpochMs,
      sealSeconds: patch.sealSeconds ?? slot.model.sealSeconds,
    );
    final cdBefore = _secondsLeft(slot, now);
    if (slot.wsSynced && cdBefore > 0) return;
    final openAtMs = patch.openAtEpochMs ?? slot.model.openAtEpochMs;
    final openAtFuture =
        openAtMs != null && openAtMs > now.millisecondsSinceEpoch;
    if (patch.countdownSeconds > 0 || openAtFuture) {
      _syncCountdown(
        slot,
        seconds: patch.countdownSeconds > 0
            ? patch.countdownSeconds
            : ((openAtMs! - now.millisecondsSinceEpoch) / 1000).ceil(),
        openAtMs: openAtMs,
        now: now,
        force: cdBefore <= 0,
      );
    }
  }

  // ── internal ──

  bool _slotNeedsTicker(_GameSlot s) {
    if (_secondsLeft(s, DateTime.now()) > 0) return true;
    return s.wsSynced;
  }

  LotteryGameModel _toDisplay(_GameSlot s, [DateTime? now]) {
    final clock = now ?? DateTime.now();
    final cd = _secondsLeft(s, clock);
    final drawing = cd <= 0;
    final openAt = s.model.openAtEpochMs ??
        s.openDeadline?.millisecondsSinceEpoch;
    final display = s.model.copyWith(
      countdownSeconds: cd,
      isDrawing: drawing,
      openAtEpochMs: openAt,
    );
    final sealed = !drawing &&
        LotteryPeriodHelper.sealRemainSeconds(display, clock) <= 0;

    return display.copyWith(
      status: drawing
          ? LotteryStatus.drawing
          : (sealed ? LotteryStatus.sealed : LotteryStatus.open),
    );
  }

  List<DrawRevealEvent> _ingestDraw(
    String gameId,
    _GameSlot slot,
    String issue,
    List<int> ranks,
    DateTime now, {
    bool force = false,
  }) {
    final prev = slot.model.previousIssue ?? '';
    if (_sameIssue(issue, prev) && listEquals(slot.model.previousResults, ranks)) {
      return const [];
    }

    final cd = _secondsLeft(slot, now);
    final olderThanCurrent = slot.model.currentIssue.isNotEmpty &&
        compareIssueNo(issue, slot.model.currentIssue) < 0;
    final prevIssue = slot.model.previousIssue ?? '';
    final olderThanPrev =
        prevIssue.isNotEmpty && compareIssueNo(issue, prevIssue) < 0;

    // 历史补期：仅当比当前上期更新时才写入，禁止 WS 旧包把上一期刷回去。
    if (!force && cd > 0 && olderThanCurrent) {
      if (olderThanPrev) return const [];
      return _applyDrawNow(gameId, slot, issue, ranks);
    }

    // 当期未封盘：等服务端在 CD=0 的 tick 再带结果。
    if (!force && cd > 0) return const [];

    return _applyDrawNow(gameId, slot, issue, ranks);
  }

  List<DrawRevealEvent> _applyDrawNow(
    String gameId,
    _GameSlot slot,
    String issue,
    List<int> ranks,
  ) {
    final current = slot.model.currentIssue;
    if (current.isNotEmpty &&
        !_sameIssue(issue, current) &&
        compareIssueNo(issue, current) >= 0) {
      return const [];
    }

    final prev = slot.model.previousIssue ?? '';
    if (prev.isNotEmpty && compareIssueNo(issue, prev) < 0) {
      return const [];
    }

    slot.model = slot.model.copyWith(
      previousIssue: preferFullIssueNo(issue, slot.model.previousIssue ?? ''),
      previousResults: ranks,
    );
    return [DrawRevealEvent(gameId: gameId, issue: issue, ranks: ranks)];
  }

  /// 写入服务端封盘配置。有 sealAt 就用该时刻，不用 sealSeconds 回写。
  void applySealConfig(
    String gameId, {
    int? sealSeconds,
    int? sealAtEpochMs,
    DateTime? now,
  }) {
    final slot = _slots[gameId];
    if (slot == null) return;
    if (sealSeconds != null && sealSeconds > 0) {
      slot.model = slot.model.copyWith(sealSeconds: sealSeconds);
    }
    if (sealAtEpochMs != null && sealAtEpochMs > 0) {
      slot.model = slot.model.copyWith(sealAtEpochMs: sealAtEpochMs);
    }
  }

  /// 有 openAt 就改开奖终点（允许变远）。没有时刻时，仅在本地还没有终点时用秒数播种。
  void _syncCountdown(
    _GameSlot slot, {
    required int seconds,
    int? openAtMs,
    required DateTime now,
    bool force = false,
  }) {
    if (openAtMs != null && openAtMs > 0) {
      slot.openDeadline = DateTime.fromMillisecondsSinceEpoch(openAtMs);
      slot.model = slot.model.copyWith(openAtEpochMs: openAtMs);
      return;
    }
    if (seconds <= 0) return;
    if (!force && slot.openDeadline != null) return;
    slot.openDeadline = now.add(Duration(seconds: seconds));
  }

  int _secondsLeft(_GameSlot slot, DateTime now) {
    final d = slot.openDeadline;
    if (d == null) return 0;
    return mathMax(0, d.difference(now).inSeconds);
  }

  DateTime? _deadlineFromModel(LotteryGameModel g, DateTime now) {
    if (g.openAtEpochMs != null && g.openAtEpochMs! > 0) {
      return DateTime.fromMillisecondsSinceEpoch(g.openAtEpochMs!);
    }
    if (g.countdownSeconds > 0) {
      return now.add(Duration(seconds: g.countdownSeconds));
    }
    return null;
  }

  static bool _sameIssue(String a, String b) {
    if (a.isEmpty || b.isEmpty) return false;
    return issueCompareKey(a) == issueCompareKey(b);
  }

  static String _pickNewer(String a, String b) {
    if (b.isEmpty) return a;
    if (a.isEmpty) return b;
    final cmp = compareIssueNo(a, b);
    if (cmp > 0) return a;
    if (cmp < 0) return b;
    return preferFullIssueNo(a, b);
  }

  static int mathMax(int a, int b) => a > b ? a : b;
}
