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

/// 期态（简单）：本地 openAt 递减 → cd>seal 距封盘 / cd≤seal 封盘 / cd=0 开奖中；
/// seal 取自后台 sealSeconds（默认 10）；WS 换期包一到立即结束开奖中并刷新球号、期号。
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
          sealSeconds: g.sealSeconds ?? existing.model.sealSeconds,
        );
        // sealAt 只跟已采纳 openAt 对齐，禁止 HTTP 把距封盘抬高。
        _alignSealAt(
          existing,
          preferredSealAtMs: null,
          now: now,
          allowSealIncrease: false,
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

    if (sealAtEpochMs != null || sealSeconds != null) {
      // 只先写入 sealSeconds 配置；sealAt 必须在 _syncCountdown 采纳 openAt 后再对齐，
      // 否则会用「未采纳的更远 openAt」算出更远 sealAt → 距封盘从 30s 跳回 50s。
      final sealSec = sealSeconds ?? slot.model.sealSeconds;
      if (sealSec != null && sealSec > 0) {
        slot.model = slot.model.copyWith(sealSeconds: sealSec);
      }
    }

    final first = !slot.wsSynced;
    if (first) slot.wsSynced = true;

    final cdBefore = _secondsLeft(slot, clock);
    final httpAnchored = first && slot.openDeadline != null;
    var allowWsIncrease = first &&
        (!httpAnchored || _wsMayCorrectHttpOnFirstTick(slot, seconds, clock));
    var issueChanged = false;

    if (issue.isNotEmpty) {
      final newer = _pickNewer(issue, slot.model.currentIssue);
      issueChanged = !_sameIssue(newer, slot.model.currentIssue);
      if (issueChanged || first) {
        // 与 PC mergePeriod 一致：PERIOD_TICK/SNAPSHOT 的 issueNo 以服务端为准。
        // 旧逻辑要求本地 CD≤0 才换期，开奖已出但本机倒计时未归零时会卡在旧期（顶栏 1598、聊天已开 1598）。
        slot.model = slot.model.copyWith(currentIssue: newer);
      }
      if (issueChanged) {
        // 换期后必须允许倒计时按新 openAt 抬升，否则仍停在旧 deadline。
        allowWsIncrease = true;
      }
    }

    _syncCountdown(
      slot,
      seconds: seconds,
      openAtMs: openAtEpochMs,
      now: clock,
      force: issueChanged ||
          (cdBefore <= 0 && seconds > 0) ||
          (first && slot.openDeadline == null && seconds > 0) ||
          (cdBefore <= 0 &&
              openAtEpochMs != null &&
              openAtEpochMs > clock.millisecondsSinceEpoch),
      allowIncrease: allowWsIncrease,
    );

    // 用「已采纳」的 openAt 对齐 sealAt（web: sealAt = openAt - sealGap）。
    _alignSealAt(
      slot,
      preferredSealAtMs: issueChanged || first ? sealAtEpochMs : null,
      now: clock,
      allowSealIncrease: issueChanged || first,
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

  List<SealRevealEvent> _emitSealChat(
    String gameId,
    _GameSlot slot,
    DateTime now,
  ) {
    final issue = slot.model.currentIssue;
    if (issue.isEmpty) return const [];

    final cd = _secondsLeft(slot, now);
    final sealLine = LotteryPeriodRules.sealSecondsOf(slot.model);
    final warnLine = sealLine * 2;
    final sealRemain = LotteryPeriodHelper.sealRemainSeconds(
      slot.model.copyWith(countdownSeconds: cd),
      now,
    );
    final out = <SealRevealEvent>[];

    // 预警：进入「封盘前 2×sealSeconds」窗口（与旧 20s/10s 比例一致）
    if (cd > 0 &&
        sealRemain > 0 &&
        sealRemain <= warnLine &&
        slot.sealWarnIssue != issue) {
      slot.sealWarnIssue = issue;
      out.add(SealRevealEvent(gameId: gameId, kind: 'warn', issue: issue));
    }
    if (cd > 0 && sealRemain <= 0 && slot.sealLineIssue != issue) {
      slot.sealLineIssue = issue;
      out.add(SealRevealEvent(gameId: gameId, kind: 'sealed', issue: issue));
    }
    return out;
  }

  /// 仅补 seal 配置（不碰倒计时锚点）。公开期数 HTTP 用这个，禁止走 onPeriodTick。
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
    _alignSealAt(
      slot,
      preferredSealAtMs: sealAtEpochMs,
      now: clock,
      allowSealIncrease: false,
    );
  }

  /// 用已采纳的 openAt 对齐 sealAt；禁止同期内把距封盘抬高。
  void _alignSealAt(
    _GameSlot slot, {
    int? preferredSealAtMs,
    required DateTime now,
    required bool allowSealIncrease,
  }) {
    final open = slot.model.openAtEpochMs ??
        slot.openDeadline?.millisecondsSinceEpoch;
    var sealSec = slot.model.sealSeconds;
    var sealAt = preferredSealAtMs ?? slot.model.sealAtEpochMs;

    if ((sealSec == null || sealSec <= 0) &&
        open != null &&
        open > 0 &&
        sealAt != null &&
        sealAt > 0 &&
        open > sealAt) {
      final gap = ((open - sealAt) / 1000).round();
      if (gap >= 1 && gap <= LotteryPeriodRules.maxSealSeconds) {
        sealSec = gap;
      }
    }

    if (open != null &&
        open > 0 &&
        sealSec != null &&
        sealSec > 0 &&
        (sealAt == null || sealAt <= 0)) {
      sealAt = open - sealSec * 1000;
    }

    // 有 open+gap 时，sealAt 必须以当前 open 为准（防 HTTP 带来更远 sealAt）。
    if (open != null && open > 0 && sealSec != null && sealSec > 0) {
      final derived = open - sealSec * 1000;
      if (sealAt == null || sealAt <= 0) {
        sealAt = derived;
      } else if (!allowSealIncrease && sealAt > derived + 1500) {
        sealAt = derived;
      } else if (allowSealIncrease) {
        // 换期：优先服务端 sealAt，否则 derived
        if (preferredSealAtMs == null || preferredSealAtMs <= 0) {
          sealAt = derived;
        }
      }
    }

    if (sealAt == null && sealSec == null) return;

    final prevSeal = slot.model.sealAtEpochMs ?? 0;
    if (!allowSealIncrease &&
        sealAt != null &&
        sealAt > 0 &&
        prevSeal > 0 &&
        sealAt > prevSeal + 1500) {
      // 同期内 sealAt 变远 → 距封盘回跳，拒绝
      sealAt = prevSeal;
    }

    slot.model = slot.model.copyWith(
      sealAtEpochMs: sealAt,
      sealSeconds: sealSec,
    );
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
    if (httpLeft <= LotteryPeriodRules.sealSecondsOf(slot.model) &&
        wsSeconds > LotteryPeriodRules.sealSecondsOf(slot.model) + 5) {
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
    final cmp = compareIssueNo(a, b);
    if (cmp > 0) return a;
    if (cmp < 0) return b;
    return preferFullIssueNo(a, b);
  }

  static int mathMax(int a, int b) => a > b ? a : b;
}
