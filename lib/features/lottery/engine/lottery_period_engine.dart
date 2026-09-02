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
  String? sealWarnIssue;
  String? sealLineIssue;
}

/// 期态（简单）：本地 openAt 递减 → cd>10 距封盘 / cd≤10 封盘 / cd=0 开奖中；
/// WS 换期包（seconds>0 + 新 issue）一到立即结束开奖中并刷新球号、期号。
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
      if (existing != null && existing.wsSynced) {
        existing.model = existing.model.copyWith(
          name: g.name.isNotEmpty ? g.name : existing.model.name,
        );
        _mergeHttpDraw(existing, g);
        _recoverStuckCountdown(existing, g, now);
        continue;
      }
      if (existing != null && existing.openDeadline != null) {
        final httpDeadline = _deadlineFromModel(g, now);
        if (httpDeadline != null) {
          final curLeft = _secondsLeft(existing, now);
          final httpLeft = mathMax(0, httpDeadline.difference(now).inSeconds);
          if (curLeft > 0 && httpLeft > curLeft) {
            existing.model = existing.model.copyWith(
              name: g.name.isNotEmpty ? g.name : existing.model.name,
              currentIssue: g.currentIssue.isNotEmpty
                  ? _pickNewer(g.currentIssue, existing.model.currentIssue)
                  : existing.model.currentIssue,
            );
            _mergeHttpDraw(existing, g);
            continue;
          }
        }
      }
      final slot = _GameSlot(g);
      slot.openDeadline = _deadlineFromModel(g, now);
      slot.prevCd = _secondsLeft(slot, now);
      _slots[g.id] = slot;
    }
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

    final curK = issueCompareKey(slot.model.currentIssue);
    final httpK = issueCompareKey(httpPrev);
    if (curK > 0 && httpK >= curK) return;

    final prevK = issueCompareKey(slot.model.previousIssue ?? '');
    if (httpK > prevK) {
      slot.model = slot.model.copyWith(
        previousIssue: preferFullIssueNo(httpPrev, slot.model.previousIssue ?? ''),
        previousResults: g.previousResults,
      );
    } else if (httpK == prevK) {
      // 同期已有 WS 球号时保留本地，避免 HTTP 回补把顶栏球闪来闪去。
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
    String? lastIssue,
    List<int> lastRanks = const [],
    DateTime? now,
  }) {
    final clock = now ?? DateTime.now();
    final slot = _slots.putIfAbsent(
      gameId,
      () => _GameSlot(
        LotteryGameModel(id: gameId, name: gameId, currentIssue: issue),
      ),
    );

    final first = !slot.wsSynced;
    if (first) slot.wsSynced = true;

    final cdBefore = _secondsLeft(slot, clock);
    final httpAnchored = first && slot.openDeadline != null;
    final allowWsIncrease = first &&
        (!httpAnchored || _wsMayCorrectHttpOnFirstTick(slot, seconds, clock));

    if (issue.isNotEmpty) {
      final newer = _pickNewer(issue, slot.model.currentIssue);
      if (!_sameIssue(newer, slot.model.currentIssue)) {
        // 下注中不提前换期号，避免倒计时与期号错位；封盘/开奖后 WS 换期包再切。
        if (_secondsLeft(slot, clock) <= 0 || first) {
          slot.model = slot.model.copyWith(currentIssue: newer);
        }
      } else if (first) {
        slot.model = slot.model.copyWith(currentIssue: newer);
      }
    }

    _syncCountdown(
      slot,
      seconds: seconds,
      openAtMs: openAtEpochMs,
      now: clock,
      force: (cdBefore <= 0 && seconds > 0) ||
          (first && slot.openDeadline == null && seconds > 0) ||
          (cdBefore <= 0 &&
              openAtEpochMs != null &&
              openAtEpochMs > clock.millisecondsSinceEpoch),
      allowIncrease: allowWsIncrease,
    );

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

    final seals = _emitSealChat(gameId, slot, clock);
    return PeriodTickResult(draws: draws, seals: seals, changed: true);
  }

  PeriodTickResult onDrawResult(
    String gameId, {
    required String issue,
    required List<int> ranks,
    DateTime? now,
  }) {
    if (issue.isEmpty || ranks.isEmpty) return PeriodTickResult.none;
    final clock = now ?? DateTime.now();
    final slot = _slots.putIfAbsent(
      gameId,
      () => _GameSlot(
        LotteryGameModel(id: gameId, name: gameId, currentIssue: ''),
      ),
    );
    if (!slot.wsSynced) slot.wsSynced = true;

    final draws = _ingestDraw(gameId, slot, issue, ranks, clock);
    return PeriodTickResult(draws: draws, changed: draws.isNotEmpty);
  }

  PeriodTickResult onSecondTick(DateTime now) {
    var changed = false;
    final seals = <SealRevealEvent>[];

    for (final entry in _slots.entries) {
      final gameId = entry.key;
      final slot = entry.value;
      final cd = _secondsLeft(slot, now);
      if (slot.prevCd != cd) {
        slot.prevCd = cd;
        changed = true;
      }

      final s = _emitSealChat(gameId, slot, now);
      if (s.isNotEmpty) {
        seals.addAll(s);
        changed = true;
      }
    }

    return PeriodTickResult(seals: seals, changed: changed);
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
    final localPrevK = issueCompareKey(slot.model.previousIssue ?? '');
    final patchPrevK = patch.previousIssue != null && patch.previousIssue!.isNotEmpty
        ? issueCompareKey(patch.previousIssue!)
        : 0;
    var nextPrevIssue = slot.model.previousIssue;
    var nextResults = slot.model.previousResults;
    if (patch.previousIssue != null && patch.previousIssue!.isNotEmpty) {
      if (patchPrevK >= localPrevK) {
        nextPrevIssue = preferFullIssueNo(
          patch.previousIssue!,
          nextPrevIssue ?? '',
        );
      }
    }
    if (patch.previousResults.isNotEmpty) {
      if (patchPrevK > localPrevK) {
        nextResults = patch.previousResults;
      } else if (patchPrevK == localPrevK && nextResults.isEmpty) {
        nextResults = patch.previousResults;
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

    return s.model.copyWith(
      countdownSeconds: cd,
      isDrawing: drawing,
      status: drawing
          ? LotteryStatus.drawing
          : (cd <= LotteryPeriodRules.sealWarnSeconds
              ? LotteryStatus.sealed
              : LotteryStatus.open),
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
    final drawK = issueCompareKey(issue);
    final curK = issueCompareKey(slot.model.currentIssue);
    final prevK = issueCompareKey(slot.model.previousIssue ?? '');

    // 历史补期：仅当比当前上期更新时才写入，禁止 WS 旧包把 567 刷回 566。
    if (!force && cd > 0 && drawK > 0 && curK > 0 && drawK < curK) {
      if (drawK < prevK) return const [];
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
        issueCompareKey(issue) >= issueCompareKey(current)) {
      return const [];
    }

    final prevK = issueCompareKey(slot.model.previousIssue ?? '');
    final drawK = issueCompareKey(issue);
    if (prevK > 0 && drawK > 0 && drawK < prevK) {
      return const [];
    }

    slot.model = slot.model.copyWith(
      previousIssue: preferFullIssueNo(issue, slot.model.previousIssue ?? ''),
      previousResults: ranks,
    );
    return [DrawRevealEvent(gameId: gameId, issue: issue, ranks: ranks)];
  }

  List<SealRevealEvent> _emitSealChat(
    String gameId,
    _GameSlot slot,
    DateTime now,
  ) {
    final issue = slot.model.currentIssue;
    if (issue.isEmpty) return const [];

    final cd = _secondsLeft(slot, now);
    const warnLine = LotteryPeriodRules.sealWarnSeconds * 2;
    const sealLine = LotteryPeriodRules.sealWarnSeconds;
    final out = <SealRevealEvent>[];

    if (cd > 0 && cd <= warnLine && slot.sealWarnIssue != issue) {
      slot.sealWarnIssue = issue;
      out.add(SealRevealEvent(gameId: gameId, kind: 'warn', issue: issue));
    }
    if (cd > 0 && cd <= sealLine && slot.sealLineIssue != issue) {
      slot.sealLineIssue = issue;
      out.add(SealRevealEvent(gameId: gameId, kind: 'sealed', issue: issue));
    }
    return out;
  }

  void _syncCountdown(
    _GameSlot slot, {
    required int seconds,
    int? openAtMs,
    required DateTime now,
    required bool force,
    bool allowIncrease = false,
  }) {
    final prevOpenAt = slot.model.openAtEpochMs;
    final openAtChanged =
        openAtMs != null && openAtMs > 0 && prevOpenAt != openAtMs;

    if (openAtMs != null &&
        openAtMs > 0 &&
        !force &&
        !openAtChanged &&
        slot.openDeadline != null &&
        slot.model.openAtEpochMs == openAtMs) {
      final expired = openAtMs <= now.millisecondsSinceEpoch;
      if (!expired) return;
    }

    DateTime? target;
    if (openAtMs != null && openAtMs > 0) {
      final fromOpenAt = DateTime.fromMillisecondsSinceEpoch(openAtMs);
      final openAtLeft = mathMax(0, fromOpenAt.difference(now).inSeconds);
      if (openAtLeft > 0) {
        target = fromOpenAt;
      } else if (seconds > 0) {
        final localLeft = _secondsLeft(slot, now);
        if (force || localLeft <= 0 || seconds <= localLeft + 2) {
          target = now.add(Duration(seconds: seconds));
        } else {
          return;
        }
      } else {
        return;
      }
    } else if (seconds > 0) {
      if (!force) {
        final prev = slot.openDeadline;
        if (prev != null) return;
      }
      target = now.add(Duration(seconds: seconds));
    } else {
      return;
    }

    final prev = slot.openDeadline;
    if (force || prev == null || openAtChanged) {
      if (_applyDeadlineIfMonotonic(
        slot,
        target,
        now,
        allowIncrease: allowIncrease,
      )) {
        if (openAtMs != null && openAtMs > 0) {
          slot.model = slot.model.copyWith(openAtEpochMs: openAtMs);
        }
      }
      return;
    }

    final prevLeft = mathMax(0, prev.difference(now).inSeconds);
    final newLeft = mathMax(0, target.difference(now).inSeconds);
    if (newLeft > prevLeft + 1) return;
    if (prevLeft > newLeft + 2) {
      if (_applyDeadlineIfMonotonic(slot, target, now) &&
          openAtMs != null &&
          openAtMs > 0) {
        slot.model = slot.model.copyWith(openAtEpochMs: openAtMs);
      }
    }
  }

  bool _wsMayCorrectHttpOnFirstTick(
    _GameSlot slot,
    int wsSeconds,
    DateTime now,
  ) {
    final httpLeft = _secondsLeft(slot, now);
    if (httpLeft <= 0) return wsSeconds > 0;
    if (wsSeconds <= httpLeft) return false;
    if (httpLeft <= LotteryPeriodRules.sealWarnSeconds &&
        wsSeconds > LotteryPeriodRules.sealWarnSeconds + 5) {
      return true;
    }
    return wsSeconds <= httpLeft + 3;
  }

  bool _applyDeadlineIfMonotonic(
    _GameSlot slot,
    DateTime target,
    DateTime now, {
    bool allowIncrease = false,
  }) {
    final newLeft = mathMax(0, target.difference(now).inSeconds);
    final prev = slot.openDeadline;
    if (prev != null) {
      final prevLeft = mathMax(0, prev.difference(now).inSeconds);
      if (prevLeft > 0 && newLeft > prevLeft && !allowIncrease) return false;
    }
    slot.openDeadline = target;
    return true;
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
    final ak = issueCompareKey(a);
    final bk = issueCompareKey(b);
    if (ak > bk) return a;
    if (bk > ak) return b;
    return preferFullIssueNo(a, b);
  }

  static int mathMax(int a, int b) => a > b ? a : b;
}
