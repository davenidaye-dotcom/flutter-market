import 'package:flutter_test/flutter_test.dart';
import 'package:letou_app/data/models/lottery_game_model.dart';
import 'package:letou_app/features/lottery/engine/lottery_period_engine.dart';
import 'package:letou_app/features/lottery/utils/lottery_period_ui.dart';

void main() {
  late LotteryPeriodEngine engine;
  late DateTime t0;

  setUp(() {
    engine = LotteryPeriodEngine();
    t0 = DateTime(2026, 8, 30, 12, 0, 0);
    engine.bootstrap(
      [
        LotteryGameModel(
          id: 'JS_SC',
          name: '极速赛车',
          currentIssue: '34136341',
          previousIssue: '34136340',
          countdownSeconds: 75,
          status: LotteryPeriodHelper.statusFromCountdown(75),
          previousResults: const [1, 2, 3, 4, 5, 6, 7, 8, 9, 10],
          openAtEpochMs: t0.add(const Duration(seconds: 75)).millisecondsSinceEpoch,
        ),
      ],
      t0,
    );
  });

  test('bootstrap exposes betting phase with correct countdown', () {
    expect(engine.countdownFor('JS_SC', t0), 75);
    final g = engine.displayGame('JS_SC', t0);
    expect(g.isDrawing, isFalse);
    expect(LotteryPeriodHelper.phaseOf(g), LotteryDisplayPhase.betting);
  });

  test('sealed phase when countdown <= 10', () {
    final t = t0.add(const Duration(seconds: 66));
    expect(engine.countdownFor('JS_SC', t), 9);
    final g = engine.displayGame('JS_SC', t);
    expect(LotteryPeriodHelper.phaseOf(g), LotteryDisplayPhase.sealed);
  });

  test('first period tick with lastIssue adopts draw on sync', () {
    engine.onPeriodTick(
      'JS_SC',
      issue: '34136341',
      seconds: 75,
      openAtEpochMs: t0.add(const Duration(seconds: 75)).millisecondsSinceEpoch,
      lastIssue: '34136341',
      lastRanks: const [9, 8, 7, 6, 5, 4, 3, 2, 1, 10],
      now: t0,
    );
    final g = engine.gameById('JS_SC')!;
    expect(g.previousIssue, '34136341');
  });

  test('early draw while betting is ignored until cd zero', () {
    engine.onPeriodTick(
      'JS_SC',
      issue: '34136341',
      seconds: 75,
      openAtEpochMs: t0.add(const Duration(seconds: 75)).millisecondsSinceEpoch,
      now: t0,
    );
    engine.onDrawResult(
      'JS_SC',
      issue: '34136341',
      ranks: const [9, 8, 7, 6, 5, 4, 3, 2, 1, 10],
      now: t0.add(const Duration(seconds: 1)),
    );
    var g = engine.gameById('JS_SC')!;
    expect(g.previousIssue, '34136340');

    final atZero = t0.add(const Duration(seconds: 75));
    final tick = engine.onPeriodTick(
      'JS_SC',
      issue: '34136342',
      seconds: 75,
      openAtEpochMs: atZero.add(const Duration(seconds: 75)).millisecondsSinceEpoch,
      lastIssue: '34136341',
      lastRanks: const [9, 8, 7, 6, 5, 4, 3, 2, 1, 10],
      now: atZero,
    );
    expect(tick.draws, isNotEmpty);
    g = engine.gameById('JS_SC')!;
    expect(g.previousIssue, '34136341');
    expect(g.previousResults, const [9, 8, 7, 6, 5, 4, 3, 2, 1, 10]);
    expect(g.isDrawing, isFalse);
  });

  test('draw for closing current issue adopts after rollover tick', () {
    engine.onPeriodTick(
      'JS_SC',
      issue: '34136341',
      seconds: 75,
      openAtEpochMs: t0.add(const Duration(seconds: 75)).millisecondsSinceEpoch,
      now: t0,
    );

    final atZero = t0.add(const Duration(seconds: 75));
    engine.onPeriodTick(
      'JS_SC',
      issue: '34136342',
      seconds: 75,
      openAtEpochMs: atZero.add(const Duration(seconds: 75)).millisecondsSinceEpoch,
      lastIssue: '34136341',
      lastRanks: const [2, 3, 4, 5, 6, 7, 8, 9, 10, 1],
      now: atZero,
    );

    final g = engine.gameById('JS_SC')!;
    expect(g.previousIssue, '34136341');
    expect(g.currentIssue, '34136342');
    expect(g.isDrawing, isFalse);
  });

  test('period tick does not reset countdown when openAt unchanged', () {
    final openAt = t0.add(const Duration(seconds: 75)).millisecondsSinceEpoch;
    engine.onPeriodTick(
      'JS_SC',
      issue: '34136341',
      seconds: 75,
      openAtEpochMs: openAt,
      now: t0,
    );
    expect(engine.countdownFor('JS_SC', t0.add(const Duration(seconds: 5))), 70);

    engine.onPeriodTick(
      'JS_SC',
      issue: '34136341',
      seconds: 75,
      openAtEpochMs: openAt,
      now: t0.add(const Duration(seconds: 5)),
    );
    expect(engine.countdownFor('JS_SC', t0.add(const Duration(seconds: 5))), 70);
    expect(engine.countdownFor('JS_SC', t0.add(const Duration(seconds: 10))), 65);
  });

  test('repeated period tick with stale seconds does not jump countdown up', () {
    engine.onPeriodTick(
      'JS_SC',
      issue: '34136341',
      seconds: 75,
      openAtEpochMs: t0.add(const Duration(seconds: 75)).millisecondsSinceEpoch,
      now: t0,
    );
    final t5 = t0.add(const Duration(seconds: 5));
    expect(engine.countdownFor('JS_SC', t5), 70);

    engine.onPeriodTick(
      'JS_SC',
      issue: '34136341',
      seconds: 75,
      now: t5,
    );
    expect(engine.countdownFor('JS_SC', t5), 70);
  });

  test('exits drawing when rollover ws tick restores countdown', () {
    engine.onPeriodTick(
      'JS_SC',
      issue: '34136341',
      seconds: 75,
      openAtEpochMs: t0.add(const Duration(seconds: 75)).millisecondsSinceEpoch,
      now: t0,
    );

    final atZero = t0.add(const Duration(seconds: 75));
    expect(engine.isDrawingPhase('JS_SC', atZero), isTrue);

    engine.onPeriodTick(
      'JS_SC',
      issue: '34136342',
      seconds: 60,
      openAtEpochMs: atZero.add(const Duration(seconds: 60)).millisecondsSinceEpoch,
      lastIssue: '34136341',
      lastRanks: const [2, 3, 4, 5, 6, 7, 8, 9, 10, 1],
      now: atZero,
    );
    final g = engine.displayGame('JS_SC', atZero);
    expect(g.isDrawing, isFalse);
    expect(g.countdownSeconds, greaterThan(0));
    expect(g.currentIssue, '34136342');
  });

  test('stale historical draw adopts immediately during betting', () {
    engine.onPeriodTick(
      'JS_SC',
      issue: '34136343',
      seconds: 200,
      openAtEpochMs: t0.add(const Duration(seconds: 200)).millisecondsSinceEpoch,
      now: t0,
    );
    final r = engine.onPeriodTick(
      'JS_SC',
      issue: '34136343',
      seconds: 198,
      lastIssue: '34136341',
      lastRanks: const [1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
      now: t0.add(const Duration(seconds: 2)),
    );
    expect(r.draws, isNotEmpty);
    final g = engine.gameById('JS_SC')!;
    expect(g.previousIssue, '34136341');
    expect(g.isDrawing, isFalse);
  });

  test('stale openAt with positive seconds restores countdown after reveal', () {
    engine.onPeriodTick(
      'JS_SC',
      issue: '34136341',
      seconds: 75,
      openAtEpochMs: t0.add(const Duration(seconds: 75)).millisecondsSinceEpoch,
      now: t0,
    );

    final atZero = t0.add(const Duration(seconds: 75));
    final pastOpenAt = t0.add(const Duration(seconds: 75)).millisecondsSinceEpoch;
    engine.onPeriodTick(
      'JS_SC',
      issue: '34136342',
      seconds: 8,
      openAtEpochMs: pastOpenAt,
      lastIssue: '34136341',
      lastRanks: const [2, 3, 4, 5, 6, 7, 8, 9, 10, 1],
      now: atZero,
    );
    expect(engine.countdownFor('JS_SC', atZero), 8);
    final g = engine.displayGame('JS_SC', atZero);
    expect(LotteryPeriodHelper.phaseOf(g), LotteryDisplayPhase.sealed);
    expect(g.isDrawing, isFalse);
  });

  test('cd zero waits for draw then exits on rollover tick', () {
    engine.bootstrap(
      [
        LotteryGameModel(
          id: 'JS_SC',
          name: '极速赛车',
          currentIssue: '34136361',
          previousIssue: '34136360',
          countdownSeconds: 5,
          status: LotteryPeriodHelper.statusFromCountdown(5),
          previousResults: const [8, 2, 1, 7, 10, 5, 4, 6, 9, 3],
          openAtEpochMs:
              t0.add(const Duration(seconds: 5)).millisecondsSinceEpoch,
        ),
      ],
      t0,
    );

    final atZero = t0.add(const Duration(seconds: 5));
    expect(engine.isDrawingPhase('JS_SC', atZero), isTrue);

    engine.onPeriodTick(
      'JS_SC',
      issue: '34136362',
      seconds: 75,
      openAtEpochMs: atZero.add(const Duration(seconds: 75)).millisecondsSinceEpoch,
      lastIssue: '34136361',
      lastRanks: const [1, 2, 3, 4, 5, 6, 7, 8, 9, 10],
      now: atZero,
    );
    final g = engine.displayGame('JS_SC', atZero);
    expect(g.previousIssue, '34136361');
    expect(g.currentIssue, '34136362');
    expect(g.isDrawing, isFalse);
  });

  test('screenshot scenario: 6360 revealed 6361 not stuck drawing', () {
    engine.bootstrap(
      [
        LotteryGameModel(
          id: 'JS_SC',
          name: '极速赛车',
          currentIssue: '34136361',
          previousIssue: '34136360',
          countdownSeconds: 8,
          status: LotteryPeriodHelper.statusFromCountdown(8),
          previousResults: const [8, 2, 1, 7, 10, 5, 4, 6, 9, 3],
          openAtEpochMs:
              t0.add(const Duration(seconds: 8)).millisecondsSinceEpoch,
        ),
      ],
      t0,
    );

    final g = engine.displayGame('JS_SC', t0);
    expect(g.currentIssue, '34136361');
    expect(g.previousIssue, '34136360');
    expect(g.isDrawing, isFalse);
    expect(LotteryPeriodHelper.phaseOf(g), LotteryDisplayPhase.sealed);

    engine.onPeriodTick(
      'JS_SC',
      issue: '34136361',
      seconds: 60,
      openAtEpochMs:
          t0.add(const Duration(seconds: 60)).millisecondsSinceEpoch,
      now: t0,
    );
    final betting = engine.displayGame('JS_SC', t0);
    expect(LotteryPeriodHelper.phaseOf(betting), LotteryDisplayPhase.betting);
    expect(betting.countdownSeconds, 60);
  });

  test('countdown does not jump when ws advances issue while cd positive', () {
    final openAt = t0.add(const Duration(seconds: 75)).millisecondsSinceEpoch;
    engine.onPeriodTick(
      'JS_SC',
      issue: '34136341',
      seconds: 75,
      openAtEpochMs: openAt,
      now: t0,
    );
    final t13 = t0.add(const Duration(seconds: 13));
    expect(engine.countdownFor('JS_SC', t13), 62);

    engine.onPeriodTick(
      'JS_SC',
      issue: '34136342',
      seconds: 75,
      openAtEpochMs: openAt,
      now: t13,
    );
    expect(engine.countdownFor('JS_SC', t13), 62);
    expect(engine.displayGame('JS_SC', t13).currentIssue, '34136341');

    final t14 = t0.add(const Duration(seconds: 14));
    engine.onSecondTick(t14);
    expect(engine.countdownFor('JS_SC', t14), 61);
  });

  test('repeated ws ticks with stale seconds never increase countdown', () {
    final openAt = t0.add(const Duration(seconds: 75)).millisecondsSinceEpoch;
    engine.onPeriodTick(
      'JS_SC',
      issue: '34136341',
      seconds: 75,
      openAtEpochMs: openAt,
      now: t0,
    );
    for (var i = 1; i <= 13; i++) {
      final t = t0.add(Duration(seconds: i));
      engine.onPeriodTick(
        'JS_SC',
        issue: '34136341',
        seconds: 75,
        openAtEpochMs: openAt,
        now: t,
      );
      engine.onSecondTick(t);
      final cd = engine.countdownFor('JS_SC', t);
      expect(cd, 75 - i, reason: 'tick at +${i}s');
    }
  });

  test('mergeHttpSnapshot does not reset ws-synced countdown', () {
    final openAt = t0.add(const Duration(seconds: 75)).millisecondsSinceEpoch;
    engine.bootstrap(
      [
        LotteryGameModel(
          id: 'JS_SC',
          name: '极速赛车',
          currentIssue: '34136341',
          countdownSeconds: 75,
          openAtEpochMs: openAt,
        ),
      ],
      t0,
    );
    engine.onPeriodTick(
      'JS_SC',
      issue: '34136341',
      seconds: 75,
      openAtEpochMs: openAt,
      now: t0,
    );
    final t26 = t0.add(const Duration(seconds: 26));
    expect(engine.countdownFor('JS_SC', t26), 49);

    engine.mergeHttpSnapshot(
      [
        LotteryGameModel(
          id: 'JS_SC',
          name: '极速赛车',
          currentIssue: '34136341',
          countdownSeconds: 75,
          openAtEpochMs: openAt,
        ),
      ],
      t26,
    );
    expect(engine.countdownFor('JS_SC', t26), 49);
  });

  test('mergeHttpSnapshot does not set previous issue >= current', () {
    final openAt = t0.add(const Duration(seconds: 75)).millisecondsSinceEpoch;
    engine.bootstrap(
      [
        LotteryGameModel(
          id: 'JS_SC',
          name: '极速赛车',
          currentIssue: '34136377',
          previousIssue: '34136376',
          countdownSeconds: 50,
          openAtEpochMs: openAt,
          previousResults: const [1, 2, 3, 4, 5, 6, 7, 8, 9, 10],
        ),
      ],
      t0,
    );
    engine.onPeriodTick(
      'JS_SC',
      issue: '34136377',
      seconds: 50,
      openAtEpochMs: openAt,
      now: t0,
    );

    engine.mergeHttpSnapshot(
      [
        LotteryGameModel(
          id: 'JS_SC',
          name: '极速赛车',
          currentIssue: '34136377',
          previousIssue: '34136377',
          countdownSeconds: 75,
          openAtEpochMs: openAt,
          previousResults: const [9, 8, 7, 6, 5, 4, 3, 2, 1, 10],
        ),
      ],
      t0,
    );

    final g = engine.displayGame('JS_SC', t0);
    expect(g.currentIssue, '34136377');
    expect(g.previousIssue, '34136376');
    expect(g.previousResults, const [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]);
  });

  test('bootstrap now+seconds then ws openAt does not jump countdown up', () {
    engine.bootstrap(
      [
        LotteryGameModel(
          id: 'JS_SC',
          name: '极速赛车',
          currentIssue: '34136341',
          countdownSeconds: 75,
        ),
      ],
      t0,
    );
    final t5 = t0.add(const Duration(seconds: 5));
    expect(engine.countdownFor('JS_SC', t5), 70);

    final openAt = t0.add(const Duration(seconds: 75)).millisecondsSinceEpoch;
    engine.onPeriodTick(
      'JS_SC',
      issue: '34136341',
      seconds: 75,
      openAtEpochMs: openAt,
      now: t5,
    );
    expect(engine.countdownFor('JS_SC', t5), 70);
    expect(
      LotteryPeriodHelper.bettingCountdownSeconds(
        engine.displayGame('JS_SC', t5),
      ),
      60,
    );
  });

  test('repeated stale ws seconds never oscillates 75↔70 (01:05↔01:00)', () {
    final openAt = t0.add(const Duration(seconds: 75)).millisecondsSinceEpoch;
    engine.onPeriodTick(
      'JS_SC',
      issue: '34136341',
      seconds: 75,
      openAtEpochMs: openAt,
      now: t0,
    );
    var lastCd = 75;
    for (var i = 1; i <= 15; i++) {
      final t = t0.add(Duration(seconds: i));
      engine.onPeriodTick(
        'JS_SC',
        issue: '34136341',
        seconds: 75,
        openAtEpochMs: openAt,
        now: t,
      );
      engine.onSecondTick(t);
      final cd = engine.countdownFor('JS_SC', t);
      expect(cd, lessThanOrEqualTo(lastCd), reason: 'tick +${i}s must not jump up');
      expect(cd, 75 - i);
      lastCd = cd;
    }
  });

  test('http refresh with stale full period does not reset local countdown', () {
    final openAt = t0.add(const Duration(seconds: 75)).millisecondsSinceEpoch;
    engine.bootstrap(
      [
        LotteryGameModel(
          id: 'JS_SC',
          name: '极速赛车',
          currentIssue: '34136341',
          countdownSeconds: 75,
          openAtEpochMs: openAt,
        ),
      ],
      t0,
    );
    engine.onPeriodTick(
      'JS_SC',
      issue: '34136341',
      seconds: 75,
      openAtEpochMs: openAt,
      now: t0,
    );
    final t8 = t0.add(const Duration(seconds: 8));
    expect(engine.countdownFor('JS_SC', t8), 67);

    engine.mergeHttpSnapshot(
      [
        LotteryGameModel(
          id: 'JS_SC',
          name: '极速赛车',
          currentIssue: '34136341',
          countdownSeconds: 75,
          openAtEpochMs: openAt,
        ),
      ],
      t8,
    );
    expect(engine.countdownFor('JS_SC', t8), 67);
  });

  test('rollover period tick at cd zero adopts draw and restores betting', () {
    engine.onPeriodTick(
      'JS_SC',
      issue: '34136341',
      seconds: 75,
      openAtEpochMs: t0.add(const Duration(seconds: 75)).millisecondsSinceEpoch,
      now: t0,
    );
    final atZero = t0.add(const Duration(seconds: 75));
    expect(engine.isDrawingPhase('JS_SC', atZero), isTrue);

    engine.onPeriodTick(
      'JS_SC',
      issue: '34136342',
      seconds: 75,
      openAtEpochMs: atZero.add(const Duration(seconds: 75)).millisecondsSinceEpoch,
      lastIssue: '34136341',
      lastRanks: const [9, 8, 7, 6, 5, 4, 3, 2, 1, 10],
      now: atZero,
    );
    final g = engine.displayGame('JS_SC', atZero);
    expect(g.isDrawing, isFalse);
    expect(LotteryPeriodHelper.phaseOf(g), LotteryDisplayPhase.betting);
    expect(g.currentIssue, '34136342');
    expect(g.previousIssue, '34136341');
    expect(g.countdownSeconds, greaterThan(0));
  });

  test('rollover with same issue field advances on next issue tick', () {
    engine.onPeriodTick(
      'JS_SC',
      issue: '34136341',
      seconds: 75,
      openAtEpochMs: t0.add(const Duration(seconds: 75)).millisecondsSinceEpoch,
      now: t0,
    );
    final atZero = t0.add(const Duration(seconds: 75));
    engine.onPeriodTick(
      'JS_SC',
      issue: '34136342',
      seconds: 290,
      openAtEpochMs: atZero.add(const Duration(seconds: 290)).millisecondsSinceEpoch,
      lastIssue: '34136341',
      lastRanks: const [8, 1, 5, 10, 4, 9, 2, 6, 3, 7],
      now: atZero,
    );
    final g = engine.displayGame('JS_SC', atZero);
    expect(g.previousIssue, '34136341');
    expect(g.currentIssue, '34136342');
    expect(g.previousIssue, isNot(g.currentIssue));
  });

  test('stale lastRanks during betting updates previous once', () {
    engine.onPeriodTick(
      'JS_SC',
      issue: '34136341',
      seconds: 75,
      openAtEpochMs: t0.add(const Duration(seconds: 75)).millisecondsSinceEpoch,
      now: t0,
    );
    final atZero = t0.add(const Duration(seconds: 75));
    engine.onPeriodTick(
      'JS_SC',
      issue: '34136342',
      seconds: 75,
      openAtEpochMs: atZero.add(const Duration(seconds: 75)).millisecondsSinceEpoch,
      lastIssue: '34136341',
      lastRanks: const [1, 2, 3, 4, 5, 6, 7, 8, 9, 10],
      now: atZero,
    );
    final mid = atZero.add(const Duration(milliseconds: 500));
    engine.onPeriodTick(
      'JS_SC',
      issue: '34136342',
      seconds: 74,
      lastIssue: '34136341',
      lastRanks: const [9, 8, 7, 6, 5, 4, 3, 2, 1, 10],
      now: mid,
    );
    final g = engine.displayGame('JS_SC', mid);
    expect(g.previousResults, const [9, 8, 7, 6, 5, 4, 3, 2, 1, 10]);
    expect(g.isDrawing, isFalse);
  });

  test('http openAt anchor wins over stale ws first tick (live probe)', () {
    final httpOpenAt =
        t0.add(const Duration(seconds: 47)).millisecondsSinceEpoch;
    engine.bootstrap(
      [
        LotteryGameModel(
          id: 'JS_SC',
          name: '极速赛车',
          currentIssue: '34136420',
          countdownSeconds: 47,
          openAtEpochMs: httpOpenAt,
        ),
      ],
      t0,
    );
    final staleWsOpenAt =
        t0.add(const Duration(seconds: 64)).millisecondsSinceEpoch;
    engine.onPeriodTick(
      'JS_SC',
      issue: '34136420',
      seconds: 64,
      openAtEpochMs: staleWsOpenAt,
      now: t0,
    );
    expect(engine.countdownFor('JS_SC', t0), 47);
    final t5 = t0.add(const Duration(seconds: 5));
    engine.onPeriodTick(
      'JS_SC',
      issue: '34136420',
      seconds: 74,
      openAtEpochMs: staleWsOpenAt + 6000,
      now: t5,
    );
    expect(engine.countdownFor('JS_SC', t5), 42);
  });

  test('ws synced stuck drawing recovers from http snapshot', () {
    final openAt = t0.add(const Duration(seconds: 75)).millisecondsSinceEpoch;
    engine.onPeriodTick(
      'JS_SC',
      issue: '34136567',
      seconds: 75,
      openAtEpochMs: openAt,
      now: t0,
    );

    final atZero = t0.add(const Duration(seconds: 75));
    engine.onPeriodTick(
      'JS_SC',
      issue: '34136568',
      seconds: 0,
      openAtEpochMs: openAt,
      lastIssue: '34136567',
      lastRanks: const [1, 2, 3, 4, 5, 6, 7, 8, 9, 10],
      now: atZero,
    );
    final stuck = engine.displayGame('JS_SC', atZero);
    expect(stuck.isDrawing, isTrue);
    expect(stuck.currentIssue, '34136568');
    expect(stuck.previousIssue, '34136567');

    final httpOpenAt =
        atZero.add(const Duration(seconds: 60)).millisecondsSinceEpoch;
    engine.mergeHttpSnapshot(
      [
        LotteryGameModel(
          id: 'JS_SC',
          name: '极速赛车',
          currentIssue: '34136568',
          previousIssue: '34136567',
          countdownSeconds: 60,
          openAtEpochMs: httpOpenAt,
          previousResults: const [1, 2, 3, 4, 5, 6, 7, 8, 9, 10],
        ),
      ],
      atZero,
    );
    final recovered = engine.displayGame('JS_SC', atZero);
    expect(recovered.isDrawing, isFalse);
    expect(recovered.countdownSeconds, 60);
    expect(
      LotteryPeriodHelper.phaseOf(recovered),
      LotteryDisplayPhase.betting,
    );
  });

  test('patchGame restores countdown when ws synced and cd zero', () {
    engine.onPeriodTick(
      'AZXY10',
      issue: '21355057',
      seconds: 300,
      openAtEpochMs: t0.add(const Duration(seconds: 300)).millisecondsSinceEpoch,
      now: t0,
    );
    final atZero = t0.add(const Duration(seconds: 300));
    engine.onPeriodTick(
      'AZXY10',
      issue: '21355058',
      seconds: 0,
      openAtEpochMs: t0.add(const Duration(seconds: 300)).millisecondsSinceEpoch,
      lastIssue: '21355057',
      lastRanks: const [5, 3, 8, 1, 10, 2, 7, 4, 6, 9],
      now: atZero,
    );
    expect(engine.isDrawingPhase('AZXY10', atZero), isTrue);

    engine.patchGame(
      LotteryGameModel(
        id: 'AZXY10',
        name: '澳洲幸运10',
        currentIssue: '21355058',
        previousIssue: '21355057',
        countdownSeconds: 280,
        openAtEpochMs:
            atZero.add(const Duration(seconds: 280)).millisecondsSinceEpoch,
        previousResults: const [5, 3, 8, 1, 10, 2, 7, 4, 6, 9],
      ),
      atZero,
    );
    final g = engine.displayGame('AZXY10', atZero);
    expect(g.isDrawing, isFalse);
    expect(g.countdownSeconds, 280);
  });

  test('onSecondTick unchanged when countdown already at zero', () {
    final openAt = t0.add(const Duration(seconds: 75)).millisecondsSinceEpoch;
    engine.onPeriodTick(
      'JS_SC',
      issue: '34136341',
      seconds: 75,
      openAtEpochMs: openAt,
      now: t0,
    );
    final atZero = t0.add(const Duration(seconds: 75));
    engine.onPeriodTick(
      'JS_SC',
      issue: '34136342',
      seconds: 0,
      openAtEpochMs: openAt,
      lastIssue: '34136341',
      lastRanks: const [1, 2, 3, 4, 5, 6, 7, 8, 9, 10],
      now: atZero,
    );
    expect(engine.countdownFor('JS_SC', atZero), 0);

    engine.onSecondTick(atZero);
    final r1 = engine.onSecondTick(atZero.add(const Duration(seconds: 1)));
    expect(r1.changed, isFalse);

    final r2 = engine.onSecondTick(atZero.add(const Duration(seconds: 2)));
    expect(r2.changed, isFalse);
  });

  test('mergeHttpSnapshot keeps ws results for same previous issue', () {
    final openAt = t0.add(const Duration(seconds: 75)).millisecondsSinceEpoch;
    engine.onPeriodTick(
      'JS_SC',
      issue: '34136341',
      seconds: 75,
      openAtEpochMs: openAt,
      lastIssue: '34136340',
      lastRanks: const [1, 2, 3, 4, 5, 6, 7, 8, 9, 10],
      now: t0,
    );
    expect(
      engine.displayGame('JS_SC', t0).previousResults,
      const [1, 2, 3, 4, 5, 6, 7, 8, 9, 10],
    );

    engine.mergeHttpSnapshot(
      [
        LotteryGameModel(
          id: 'JS_SC',
          name: '极速赛车',
          currentIssue: '34136341',
          previousIssue: '34136340',
          countdownSeconds: 75,
          openAtEpochMs: openAt,
          previousResults: const [10, 9, 8, 7, 6, 5, 4, 3, 2, 1],
        ),
      ],
      t0,
    );
    expect(
      engine.displayGame('JS_SC', t0).previousResults,
      const [1, 2, 3, 4, 5, 6, 7, 8, 9, 10],
    );
  });

  test('stale older lastIssue during betting does not regress previous', () {
    final openAt = t0.add(const Duration(seconds: 75)).millisecondsSinceEpoch;
    engine.onPeriodTick(
      'AZXY10',
      issue: '21355068',
      seconds: 75,
      openAtEpochMs: openAt,
      lastIssue: '21355067',
      lastRanks: const [3, 5, 6, 7, 4, 8, 9, 10, 2, 1],
      now: t0,
    );
    expect(engine.displayGame('AZXY10', t0).previousIssue, '21355067');

    final mid = t0.add(const Duration(seconds: 3));
    engine.onPeriodTick(
      'AZXY10',
      issue: '21355068',
      seconds: 72,
      openAtEpochMs: openAt,
      lastIssue: '21355066',
      lastRanks: const [1, 2, 3, 4, 5, 6, 7, 8, 9, 10],
      now: mid,
    );
    final g = engine.displayGame('AZXY10', mid);
    expect(g.previousIssue, '21355067');
    expect(g.previousResults, const [3, 5, 6, 7, 4, 8, 9, 10, 2, 1]);
  });

  test('patchGame does not regress previous issue from http snapshot', () {
    final openAt = t0.add(const Duration(seconds: 75)).millisecondsSinceEpoch;
    engine.onPeriodTick(
      'AZXY10',
      issue: '21355068',
      seconds: 75,
      openAtEpochMs: openAt,
      lastIssue: '21355067',
      lastRanks: const [3, 5, 6, 7, 4, 8, 9, 10, 2, 1],
      now: t0,
    );
    engine.patchGame(
      LotteryGameModel(
        id: 'AZXY10',
        name: '澳洲幸运10',
        currentIssue: '21355068',
        previousIssue: '21355066',
        countdownSeconds: 60,
        openAtEpochMs: t0.add(const Duration(seconds: 60)).millisecondsSinceEpoch,
        previousResults: const [9, 8, 7, 6, 5, 4, 3, 2, 1, 10],
      ),
      t0,
    );
    final g = engine.displayGame('AZXY10', t0);
    expect(g.previousIssue, '21355067');
    expect(g.previousResults, const [3, 5, 6, 7, 4, 8, 9, 10, 2, 1]);
  });

  test('future openAt on ws tick ends drawing even when seconds is zero', () {
    final openAt = t0.add(const Duration(seconds: 75)).millisecondsSinceEpoch;
    engine.onPeriodTick(
      'AZXY10',
      issue: '21355068',
      seconds: 75,
      openAtEpochMs: openAt,
      now: t0,
    );
    final atZero = t0.add(const Duration(seconds: 75));
    engine.onPeriodTick(
      'AZXY10',
      issue: '21355069',
      seconds: 0,
      openAtEpochMs: openAt,
      lastIssue: '21355068',
      lastRanks: const [6, 10, 8, 2, 5, 1, 4, 7, 3, 9],
      now: atZero,
    );
    expect(engine.displayGame('AZXY10', atZero).isDrawing, isTrue);

    final nextOpen =
        atZero.add(const Duration(seconds: 300)).millisecondsSinceEpoch;
    engine.onPeriodTick(
      'AZXY10',
      issue: '21355069',
      seconds: 0,
      openAtEpochMs: nextOpen,
      lastIssue: '21355068',
      lastRanks: const [6, 10, 8, 2, 5, 1, 4, 7, 3, 9],
      now: atZero.add(const Duration(seconds: 2)),
    );
    final g = engine.displayGame('AZXY10', atZero.add(const Duration(seconds: 2)));
    expect(g.isDrawing, isFalse);
    expect(g.currentIssue, '21355069');
    expect(g.countdownSeconds, greaterThan(290));
  });
}
