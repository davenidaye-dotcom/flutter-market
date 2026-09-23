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

  /// 第一次进入开奖中的时刻。用来判断是不是停太久。
  DateTime? drawingSince;

  /// 本期还在未来的开奖时刻。过了封盘点后钉住，换期才放开。
  int? armedOpenAtMs;
  String armedIssue = '';
}

/// 期态：距封盘用 sealAtEpochMs，封盘中用 openAtEpochMs，与 web `lotteryFeed` 同一套时刻。
/// 聊天封盘线不在这里生成，只消费后端 WS / 历史消息。
final class LotteryPeriodEngine {
  /// 开奖中超过这段时间，才接受服务端仍在未来的同期开奖时刻。
  static const stuckDrawingGrace = Duration(seconds: 3);

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
      _arm(slot, now);
    }
  }

  void mergeHttpSnapshot(List<LotteryGameModel> list, DateTime now) {
    for (final g in list) {
      final existing = _slots[g.id];
      if (existing != null) {
        _noteDrawing(existing, now);
        final advances = _incomingIssueAdvances(existing, g.currentIssue);
        _arm(existing, now);
        final pinned = !advances && _epochsFrozen(existing, now);
        if (advances) _clearArm(existing);
        existing.model = existing.model.copyWith(
          name: g.name.isNotEmpty ? g.name : existing.model.name,
          currentIssue: g.currentIssue.isNotEmpty
              ? _pickNewer(g.currentIssue, existing.model.currentIssue)
              : existing.model.currentIssue,
          sealSeconds: g.sealSeconds ?? existing.model.sealSeconds,
        );
        if (!pinned) {
          _applyEpochs(
            existing,
            openAtMs: g.openAtEpochMs,
            sealAtMs: g.sealAtEpochMs,
            now: now,
          );
        } else {
          _maybeUnstickDrawing(existing, g.openAtEpochMs, now);
        }
        _mergeHttpDraw(existing, g);
        if (!pinned) _recoverStuckCountdown(existing, g, now);
        _noteDrawing(existing, now);
        _arm(existing, now);
        continue;
      }
      final slot = _GameSlot(g);
      slot.openDeadline = _deadlineFromModel(g, now);
      slot.prevCd = _secondsLeft(slot, now);
      _slots[g.id] = slot;
      _arm(slot, now);
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

    _noteDrawing(slot, clock);
    final advances = _incomingIssueAdvances(slot, issue);
    _arm(slot, clock);
    final pinned = !advances && _epochsFrozen(slot, clock);
    if (advances) _clearArm(slot);
    if (issue.isNotEmpty) {
      final newer = _pickNewer(issue, slot.model.currentIssue);
      if (advances || first) {
        // PERIOD_TICK/SNAPSHOT 的 issueNo 以服务端为准。
        slot.model = slot.model.copyWith(currentIssue: newer);
      }
    }

    // 封盘后钉死到换期。同期未封盘时，开奖时刻只允许提前，不能把剩余拉长。
    // 开奖中停过几秒后，服务端这一期的开奖时刻若还在未来，则采纳并退出开奖中。
    if (!pinned) {
      _applyEpochs(
        slot,
        openAtMs: openAtEpochMs,
        sealAtMs: sealAtEpochMs,
        now: clock,
      );
      if (openAtEpochMs == null || openAtEpochMs <= 0) {
        _syncCountdown(
          slot,
          seconds: seconds,
          openAtMs: null,
          now: clock,
          force: first && slot.openDeadline == null,
        );
      }
    } else {
      _maybeUnstickDrawing(slot, openAtEpochMs, clock);
    }
    _noteDrawing(slot, clock);
    _arm(slot, clock);

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
      _arm(slot, now);
      _noteDrawing(slot, now);
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
      _arm(s, now);
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
    final advances = _incomingIssueAdvances(slot, patch.currentIssue);
    _arm(slot, now);
    final pinned = !advances && _epochsFrozen(slot, now);
    if (advances) _clearArm(slot);
    slot.model = slot.model.copyWith(
      name: patch.name.isNotEmpty ? patch.name : slot.model.name,
      currentIssue: patch.currentIssue.isNotEmpty
          ? _pickNewer(patch.currentIssue, slot.model.currentIssue)
          : slot.model.currentIssue,
      previousIssue: nextPrevIssue,
      previousResults: nextResults,
      sealSeconds: patch.sealSeconds ?? slot.model.sealSeconds,
    );
    if (pinned) return;
    _applyEpochs(
      slot,
      openAtMs: patch.openAtEpochMs,
      sealAtMs: patch.sealAtEpochMs,
      now: now,
    );
    _arm(slot, now);
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
    _arm(slot, now);
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
    final phase = LotteryPeriodHelper.phaseOf(display, clock);
    return display.copyWith(
      status: switch (phase) {
        LotteryDisplayPhase.drawing => LotteryStatus.drawing,
        LotteryDisplayPhase.sealed => LotteryStatus.sealed,
        LotteryDisplayPhase.betting => LotteryStatus.open,
      },
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

  /// 写入服务端封盘配置。本期提前量已确定后不再改 sealAt。
  void applySealConfig(
    String gameId, {
    int? sealSeconds,
    int? sealAtEpochMs,
    DateTime? now,
  }) {
    final slot = _slots[gameId];
    if (slot == null) return;
    final clock = now ?? DateTime.now();
    if (sealSeconds != null && sealSeconds > 0) {
      slot.model = slot.model.copyWith(sealSeconds: sealSeconds);
    }
    _arm(slot, clock);
    if (_epochsFrozen(slot, clock) || _gapLocked(slot)) return;
    if (sealAtEpochMs != null && sealAtEpochMs > 0) {
      slot.model = slot.model.copyWith(sealAtEpochMs: sealAtEpochMs);
    }
  }

  void _clearArm(_GameSlot slot) {
    slot.armedOpenAtMs = null;
    slot.armedIssue = '';
  }

  /// 记下本期仍在未来的开奖时刻，供封盘后钉死。
  void _arm(_GameSlot slot, DateTime now) {
    final open = slot.model.openAtEpochMs ??
        slot.openDeadline?.millisecondsSinceEpoch ??
        0;
    final issue = slot.model.currentIssue;
    if (issue.isEmpty || open <= now.millisecondsSinceEpoch) return;
    slot.armedOpenAtMs = open;
    slot.armedIssue = issue;
  }

  /// 记下进入开奖中的时刻；倒计时恢复后清掉。
  void _noteDrawing(_GameSlot slot, DateTime now) {
    if (_secondsLeft(slot, now) <= 0) {
      slot.drawingSince ??= now;
    } else {
      slot.drawingSince = null;
    }
  }

  /// 开奖中已停满 [LotteryPeriodEngine.stuckDrawingGrace]，且服务端开奖时刻仍在未来。
  bool _shouldUnstickDrawing(_GameSlot slot, DateTime now, int? openAtMs) {
    if (openAtMs == null || openAtMs <= now.millisecondsSinceEpoch) return false;
    if (_secondsLeft(slot, now) > 0) return false;
    final since = slot.drawingSince;
    if (since == null) return false;
    return now.difference(since) >= LotteryPeriodEngine.stuckDrawingGrace;
  }

  void _maybeUnstickDrawing(_GameSlot slot, int? openAtMs, DateTime now) {
    if (!_shouldUnstickDrawing(slot, now, openAtMs)) return;
    _adoptFutureOpenWhileDrawing(slot, openAtMs!, now);
  }

  /// 退出卡住的开奖中。封盘时刻保持在当前或更早，继续显示「封盘中，距离开奖」。
  void _adoptFutureOpenWhileDrawing(
    _GameSlot slot,
    int openAtMs,
    DateTime now,
  ) {
    final nowMs = now.millisecondsSinceEpoch;
    if (openAtMs <= nowMs) return;
    final prevOpen = slot.model.openAtEpochMs ?? 0;
    final prevSeal = slot.model.sealAtEpochMs ?? 0;
    var sealAt = prevSeal;
    if (prevOpen > prevSeal && prevSeal > 0) {
      sealAt = openAtMs - (prevOpen - prevSeal);
    }
    if (sealAt <= 0 || sealAt > nowMs) {
      sealAt = nowMs;
    }
    slot.openDeadline = DateTime.fromMillisecondsSinceEpoch(openAtMs);
    slot.model = slot.model.copyWith(
      openAtEpochMs: openAtMs,
      sealAtEpochMs: sealAt,
    );
    slot.drawingSince = null;
    slot.prevCd = _secondsLeft(slot, now);
  }

  /// 本期开奖与封盘时刻都已在手：提前量固定，后到的 sealAt 不再改距封盘。
  bool _gapLocked(_GameSlot slot) {
    final open = slot.model.openAtEpochMs ?? 0;
    final seal = slot.model.sealAtEpochMs ?? 0;
    if (seal <= 0 || open <= seal) return false;
    if (slot.armedIssue.isEmpty) return false;
    return _sameIssue(slot.armedIssue, slot.model.currentIssue);
  }

  /// 本期已过封盘点：钉住 armed 的开奖时刻，开奖中也保持，直到期号前进。
  bool _epochsFrozen(_GameSlot slot, DateTime now) {
    final armedOpen = slot.armedOpenAtMs;
    if (armedOpen == null || slot.armedIssue.isEmpty) return false;
    if (!_sameIssue(slot.armedIssue, slot.model.currentIssue)) return false;
    final seal = slot.model.sealAtEpochMs ?? 0;
    if (seal <= 0 || armedOpen <= seal) return false;
    return now.millisecondsSinceEpoch >= seal;
  }

  bool _incomingIssueAdvances(_GameSlot slot, String issue) {
    if (issue.isEmpty || slot.model.currentIssue.isEmpty) return false;
    return !_sameIssue(issue, slot.model.currentIssue) &&
        compareIssueNo(issue, slot.model.currentIssue) > 0;
  }

  /// 写入开奖/封盘时刻。同一期已有开奖时刻时，更远的 openAt 整包丢弃。
  /// 只带更近的 openAt 时，按原提前量平移 sealAt，避免封盘段被拉成一期总长。
  void _applyEpochs(
    _GameSlot slot, {
    int? openAtMs,
    int? sealAtMs,
    required DateTime now,
  }) {
    final prevOpen = slot.model.openAtEpochMs ?? 0;
    final prevSeal = slot.model.sealAtEpochMs ?? 0;
    final sameIssue = slot.armedIssue.isNotEmpty &&
        _sameIssue(slot.armedIssue, slot.model.currentIssue);
    if (sameIssue &&
        openAtMs != null &&
        openAtMs > prevOpen &&
        prevOpen > 0) {
      return;
    }
    var sealAt = sealAtMs;
    final gapLocked = sameIssue && prevOpen > prevSeal && prevSeal > 0;
    if (gapLocked) {
      final baseOpen = (openAtMs != null && openAtMs > 0) ? openAtMs : prevOpen;
      sealAt = baseOpen - (prevOpen - prevSeal);
    } else if (openAtMs != null &&
        openAtMs > now.millisecondsSinceEpoch &&
        (sealAt == null || sealAt <= 0) &&
        prevOpen > prevSeal &&
        prevSeal > 0) {
      // 开奖时刻还在未来、包里又没带 sealAt：按原提前量平移。
      sealAt = openAtMs - (prevOpen - prevSeal);
    }
    if (openAtMs != null && openAtMs > 0) {
      slot.openDeadline = DateTime.fromMillisecondsSinceEpoch(openAtMs);
      slot.model = slot.model.copyWith(openAtEpochMs: openAtMs);
    }
    if (sealAt != null && sealAt > 0) {
      slot.model = slot.model.copyWith(sealAtEpochMs: sealAt);
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
