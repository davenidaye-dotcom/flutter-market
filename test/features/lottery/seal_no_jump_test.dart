
import 'package:flutter_test/flutter_test.dart';
import 'package:letou_app/data/models/lottery_game_model.dart';
import 'package:letou_app/features/lottery/engine/lottery_period_engine.dart';
import 'package:letou_app/features/lottery/utils/lottery_period_ui.dart';

void main() {
  test('同期更远的开奖时刻不采用，已确定的提前量不再被后到的 sealAt 改掉', () {
    final engine = LotteryPeriodEngine();
    final t0 = DateTime(2099, 6, 1, 12, 0, 0);
    final openAt = t0.add(const Duration(seconds: 75)).millisecondsSinceEpoch;
    engine.bootstrap(
      [
        LotteryGameModel(
          id: 'JS_SC',
          name: '极速赛车',
          currentIssue: '34136341',
          countdownSeconds: 75,
          openAtEpochMs: openAt,
          sealSeconds: 30,
          sealAtEpochMs: t0.add(const Duration(seconds: 45)).millisecondsSinceEpoch,
        ),
      ],
      t0,
    );
    engine.onPeriodTick(
      'JS_SC',
      issue: '34136341',
      seconds: 75,
      openAtEpochMs: openAt,
      sealSeconds: 30,
      sealAtEpochMs: t0.add(const Duration(seconds: 45)).millisecondsSinceEpoch,
      now: t0,
    );

    final t15 = t0.add(const Duration(seconds: 15));
    final mid = engine.displayGame('JS_SC', t15);
    final midSeal = LotteryPeriodHelper.bettingCountdownSeconds(mid, t15);
    expect(midSeal, 30);

    // 同期更远的 openAt 不采用，剩余保持原来的 75 秒钟。
    final laterOpen = t0.add(const Duration(seconds: 95)).millisecondsSinceEpoch;
    engine.onPeriodTick(
      'JS_SC',
      issue: '34136341',
      seconds: 80,
      openAtEpochMs: laterOpen,
      sealSeconds: 30,
      sealAtEpochMs: t0.add(const Duration(seconds: 65)).millisecondsSinceEpoch,
      now: t15,
    );
    final after = engine.displayGame('JS_SC', t15);
    expect(LotteryPeriodHelper.bettingCountdownSeconds(after, t15), 30);
    expect(LotteryPeriodHelper.openRemainSeconds(after, t15), 60);

    engine.applySealConfig(
      'JS_SC',
      sealSeconds: 10,
      sealAtEpochMs: t0.add(const Duration(seconds: 70)).millisecondsSinceEpoch,
      now: t15,
    );
    final afterEnrich = engine.displayGame('JS_SC', t15);
    // 本期提前量已经是 30 秒，后到的 sealAt 不再把距封盘改掉。
    expect(LotteryPeriodHelper.bettingCountdownSeconds(afterEnrich, t15), 30);
    expect(LotteryPeriodHelper.openRemainSeconds(afterEnrich, t15), 60);
  });

  test('封盘窗口内更远 openAt 不把封盘中抬成一整期，换期后才采用', () {
    final engine = LotteryPeriodEngine();
    final t0 = DateTime(2099, 6, 1, 12, 0, 0);
    final openAt = t0.add(const Duration(seconds: 40)).millisecondsSinceEpoch;
    final sealAt = t0.add(const Duration(seconds: 10)).millisecondsSinceEpoch;
    engine.bootstrap(
      [
        LotteryGameModel(
          id: 'JS_SC',
          name: '极速赛车',
          currentIssue: '34136341',
          countdownSeconds: 40,
          openAtEpochMs: openAt,
          sealSeconds: 30,
          sealAtEpochMs: sealAt,
        ),
      ],
      t0,
    );
    final sealedAt = t0.add(const Duration(seconds: 15));
    final sealed = engine.displayGame('JS_SC', sealedAt);
    expect(LotteryPeriodHelper.phaseOf(sealed, sealedAt), LotteryDisplayPhase.sealed);
    expect(LotteryPeriodHelper.openRemainSeconds(sealed, sealedAt), 25);

    engine.onPeriodTick(
      'JS_SC',
      issue: '34136341',
      seconds: 75,
      openAtEpochMs: sealedAt.add(const Duration(seconds: 75)).millisecondsSinceEpoch,
      sealAtEpochMs: sealedAt.add(const Duration(seconds: 45)).millisecondsSinceEpoch,
      sealSeconds: 30,
      now: sealedAt,
    );
    final held = engine.displayGame('JS_SC', sealedAt);
    expect(LotteryPeriodHelper.phaseOf(held, sealedAt), LotteryDisplayPhase.sealed);
    expect(LotteryPeriodHelper.openRemainSeconds(held, sealedAt), 25);

    engine.mergeHttpSnapshot(
      [
        LotteryGameModel(
          id: 'JS_SC',
          name: '极速赛车',
          currentIssue: '34136341',
          countdownSeconds: 75,
          openAtEpochMs: sealedAt.add(const Duration(seconds: 75)).millisecondsSinceEpoch,
          sealSeconds: 10,
          sealAtEpochMs: sealedAt.add(const Duration(seconds: 65)).millisecondsSinceEpoch,
        ),
      ],
      sealedAt,
    );
    engine.applySealConfig(
      'JS_SC',
      sealSeconds: 10,
      sealAtEpochMs: sealedAt.add(const Duration(seconds: 60)).millisecondsSinceEpoch,
      now: sealedAt,
    );
    final afterRefresh = engine.displayGame('JS_SC', sealedAt);
    expect(LotteryPeriodHelper.phaseOf(afterRefresh, sealedAt), LotteryDisplayPhase.sealed);
    expect(LotteryPeriodHelper.openRemainSeconds(afterRefresh, sealedAt), 25);

    final nextOpen = sealedAt.add(const Duration(seconds: 75)).millisecondsSinceEpoch;
    engine.onPeriodTick(
      'JS_SC',
      issue: '34136342',
      seconds: 75,
      openAtEpochMs: nextOpen,
      sealAtEpochMs: sealedAt.add(const Duration(seconds: 45)).millisecondsSinceEpoch,
      sealSeconds: 30,
      now: sealedAt,
    );
    final next = engine.displayGame('JS_SC', sealedAt);
    expect(next.currentIssue, '34136342');
    expect(LotteryPeriodHelper.phaseOf(next, sealedAt), LotteryDisplayPhase.betting);
    expect(LotteryPeriodHelper.openRemainSeconds(next, sealedAt), 75);
    expect(LotteryPeriodHelper.bettingCountdownSeconds(next, sealedAt), 45);
  });

  test('封盘前更远的 openAt 不拉长剩余，提前量保持不变', () {
    final engine = LotteryPeriodEngine();
    final t0 = DateTime(2099, 6, 1, 12, 0, 0);
    engine.bootstrap(
      [
        LotteryGameModel(
          id: 'JS_SC',
          name: '极速赛车',
          currentIssue: '34136341',
          countdownSeconds: 75,
          openAtEpochMs: t0.add(const Duration(seconds: 75)).millisecondsSinceEpoch,
          sealSeconds: 30,
          sealAtEpochMs: t0.add(const Duration(seconds: 45)).millisecondsSinceEpoch,
        ),
      ],
      t0,
    );
    engine.onPeriodTick(
      'JS_SC',
      issue: '34136341',
      seconds: 95,
      openAtEpochMs: t0.add(const Duration(seconds: 95)).millisecondsSinceEpoch,
      now: t0,
    );
    final t15 = t0.add(const Duration(seconds: 15));
    final g = engine.displayGame('JS_SC', t15);
    expect(LotteryPeriodHelper.phaseOf(g, t15), LotteryDisplayPhase.betting);
    expect(LotteryPeriodHelper.bettingCountdownSeconds(g, t15), 30);
    expect(LotteryPeriodHelper.openRemainSeconds(g, t15), 60);
  });

  test('封盘前更近的 openAt 按原提前量平移 sealAt', () {
    final engine = LotteryPeriodEngine();
    final t0 = DateTime(2099, 6, 1, 12, 0, 0);
    engine.bootstrap(
      [
        LotteryGameModel(
          id: 'JS_SC',
          name: '极速赛车',
          currentIssue: '34136341',
          countdownSeconds: 75,
          openAtEpochMs: t0.add(const Duration(seconds: 75)).millisecondsSinceEpoch,
          sealSeconds: 30,
          sealAtEpochMs: t0.add(const Duration(seconds: 45)).millisecondsSinceEpoch,
        ),
      ],
      t0,
    );
    engine.onPeriodTick(
      'JS_SC',
      issue: '34136341',
      seconds: 60,
      openAtEpochMs: t0.add(const Duration(seconds: 60)).millisecondsSinceEpoch,
      now: t0,
    );
    final g = engine.displayGame('JS_SC', t0);
    expect(LotteryPeriodHelper.phaseOf(g, t0), LotteryDisplayPhase.betting);
    expect(LotteryPeriodHelper.openRemainSeconds(g, t0), 60);
    expect(LotteryPeriodHelper.bettingCountdownSeconds(g, t0), 30);
  });

  test('开奖时刻到了保持开奖中，同期更远 openAt 不把倒计时拉回来', () {
    final engine = LotteryPeriodEngine();
    final t0 = DateTime(2099, 6, 1, 12, 0, 0);
    final openAt = t0.add(const Duration(seconds: 40)).millisecondsSinceEpoch;
    final sealAt = t0.add(const Duration(seconds: 10)).millisecondsSinceEpoch;
    engine.bootstrap(
      [
        LotteryGameModel(
          id: 'JS_SC',
          name: '极速赛车',
          currentIssue: '34136341',
          countdownSeconds: 40,
          openAtEpochMs: openAt,
          sealSeconds: 30,
          sealAtEpochMs: sealAt,
        ),
      ],
      t0,
    );
    final opened = t0.add(const Duration(seconds: 40));
    final drawing = engine.displayGame('JS_SC', opened);
    expect(LotteryPeriodHelper.phaseOf(drawing, opened), LotteryDisplayPhase.drawing);
    expect(LotteryPeriodHelper.openRemainSeconds(drawing, opened), 0);

    engine.onPeriodTick(
      'JS_SC',
      issue: '34136341',
      seconds: 75,
      openAtEpochMs: opened.add(const Duration(seconds: 75)).millisecondsSinceEpoch,
      sealAtEpochMs: opened.add(const Duration(seconds: 45)).millisecondsSinceEpoch,
      sealSeconds: 30,
      now: opened,
    );
    final held = engine.displayGame('JS_SC', opened);
    expect(held.currentIssue, '34136341');
    expect(LotteryPeriodHelper.phaseOf(held, opened), LotteryDisplayPhase.drawing);
    expect(LotteryPeriodHelper.openRemainSeconds(held, opened), 0);

    final nextAt = opened.add(const Duration(seconds: 1));
    engine.onPeriodTick(
      'JS_SC',
      issue: '34136342',
      seconds: 75,
      openAtEpochMs: nextAt.add(const Duration(seconds: 75)).millisecondsSinceEpoch,
      sealAtEpochMs: nextAt.add(const Duration(seconds: 45)).millisecondsSinceEpoch,
      sealSeconds: 30,
      now: nextAt,
    );
    final next = engine.displayGame('JS_SC', nextAt);
    expect(next.currentIssue, '34136342');
    expect(LotteryPeriodHelper.phaseOf(next, nextAt), LotteryDisplayPhase.betting);
    expect(LotteryPeriodHelper.bettingCountdownSeconds(next, nextAt), 45);
    expect(LotteryPeriodHelper.openRemainSeconds(next, nextAt), 75);
  });

  test('开奖中停满 500 毫秒后，同期仍在未来的开奖时刻可以退出开奖中', () {
    final engine = LotteryPeriodEngine();
    final t0 = DateTime(2099, 6, 1, 12, 0, 0);
    final openAt = t0.add(const Duration(seconds: 10)).millisecondsSinceEpoch;
    final sealAt = t0.millisecondsSinceEpoch;
    engine.bootstrap(
      [
        LotteryGameModel(
          id: 'JS_SC',
          name: '极速赛车',
          currentIssue: '34136341',
          countdownSeconds: 10,
          openAtEpochMs: openAt,
          sealSeconds: 30,
          sealAtEpochMs: sealAt,
        ),
      ],
      t0,
    );
    final opened = t0.add(const Duration(seconds: 10));
    engine.onSecondTick(opened);
    final drawing = engine.displayGame('JS_SC', opened);
    expect(LotteryPeriodHelper.phaseOf(drawing, opened), LotteryDisplayPhase.drawing);

    final tooSoon = opened.add(const Duration(milliseconds: 200));
    engine.onPeriodTick(
      'JS_SC',
      issue: '34136341',
      seconds: 20,
      openAtEpochMs: tooSoon.add(const Duration(seconds: 20)).millisecondsSinceEpoch,
      sealAtEpochMs: tooSoon.millisecondsSinceEpoch,
      sealSeconds: 30,
      now: tooSoon,
    );
    expect(
      LotteryPeriodHelper.phaseOf(engine.displayGame('JS_SC', tooSoon), tooSoon),
      LotteryDisplayPhase.drawing,
    );

    final later = opened.add(LotteryPeriodEngine.stuckDrawingGrace);
    final serverOpen = later.add(const Duration(seconds: 18));
    engine.onPeriodTick(
      'JS_SC',
      issue: '34136341',
      seconds: 18,
      openAtEpochMs: serverOpen.millisecondsSinceEpoch,
      sealAtEpochMs: later.millisecondsSinceEpoch,
      sealSeconds: 30,
      now: later,
    );
    final recovered = engine.displayGame('JS_SC', later);
    expect(recovered.currentIssue, '34136341');
    expect(LotteryPeriodHelper.phaseOf(recovered, later), LotteryDisplayPhase.sealed);
    expect(LotteryPeriodHelper.openRemainSeconds(recovered, later), 18);
    expect(LotteryPeriodHelper.statusClockSeconds(recovered, later), 18);
  });

  test('同期开奖时刻被提前扣成开奖中后，本地秒针拉回还没到的开奖时刻', () {
    final engine = LotteryPeriodEngine();
    final t0 = DateTime(2099, 6, 1, 12, 0, 0);
    final openAt = t0.add(const Duration(seconds: 40));
    engine.bootstrap(
      [
        LotteryGameModel(
          id: 'JS_SC',
          name: '极速赛车',
          currentIssue: '34191267',
          previousIssue: '34191266',
          countdownSeconds: 40,
          openAtEpochMs: openAt.millisecondsSinceEpoch,
          sealAtEpochMs: t0.add(const Duration(seconds: 10)).millisecondsSinceEpoch,
          sealSeconds: 30,
        ),
      ],
      t0,
    );
    final midway = t0.add(const Duration(seconds: 5));
    expect(
      LotteryPeriodHelper.phaseOf(engine.displayGame('JS_SC', midway), midway),
      LotteryDisplayPhase.betting,
    );

    final pastOpen = t0.subtract(const Duration(seconds: 1)).millisecondsSinceEpoch;
    engine.onPeriodTick(
      'JS_SC',
      issue: '34191267',
      seconds: 0,
      openAtEpochMs: pastOpen,
      now: midway,
    );
    expect(
      LotteryPeriodHelper.phaseOf(engine.displayGame('JS_SC', midway), midway),
      LotteryDisplayPhase.drawing,
    );

    engine.onSecondTick(midway);
    final restored = engine.displayGame('JS_SC', midway);
    expect(restored.currentIssue, '34191267');
    expect(LotteryPeriodHelper.phaseOf(restored, midway), LotteryDisplayPhase.betting);
    expect(LotteryPeriodHelper.openRemainSeconds(restored, midway), 35);
  });

  test('秒针拉回不看交互是否暂停', () {
    // 下注页会暂停落盘，但秒针仍调用 onSecondTick，才能把提前扣掉的开奖时刻拉回来。
    final engine = LotteryPeriodEngine();
    final t0 = DateTime(2099, 6, 1, 12, 0, 0);
    final openAt = t0.add(const Duration(seconds: 40));
    engine.bootstrap(
      [
        LotteryGameModel(
          id: 'JS_SC',
          name: '极速赛车',
          currentIssue: '34191267',
          countdownSeconds: 40,
          openAtEpochMs: openAt.millisecondsSinceEpoch,
          sealAtEpochMs: t0.add(const Duration(seconds: 10)).millisecondsSinceEpoch,
          sealSeconds: 30,
        ),
      ],
      t0,
    );
    final midway = t0.add(const Duration(seconds: 5));
    engine.onPeriodTick(
      'JS_SC',
      issue: '34191267',
      seconds: 0,
      openAtEpochMs: t0.subtract(const Duration(seconds: 1)).millisecondsSinceEpoch,
      now: midway,
    );
    expect(engine.needsDrawRecovery('JS_SC', midway), isTrue);

    engine.onSecondTick(midway);
    final restored = engine.displayGame('JS_SC', midway);
    expect(LotteryPeriodHelper.phaseOf(restored, midway), LotteryDisplayPhase.betting);
    expect(engine.needsDrawRecovery('JS_SC', midway), isFalse);
    expect(LotteryPeriodHelper.openRemainSeconds(restored, midway), 35);
  });

  test('开奖时刻已过就要补拉，只用秒数播种时开奖时刻和终点写在一起', () {
    final engine = LotteryPeriodEngine();
    final t0 = DateTime(2099, 6, 1, 12, 0, 0);
    final openAt = t0.add(const Duration(seconds: 10)).millisecondsSinceEpoch;
    engine.bootstrap(
      [
        LotteryGameModel(
          id: 'JS_SC',
          name: '极速赛车',
          currentIssue: '34136341',
          countdownSeconds: 10,
          openAtEpochMs: openAt,
          sealAtEpochMs: t0.millisecondsSinceEpoch,
          sealSeconds: 10,
        ),
      ],
      t0,
    );
    final opened = t0.add(const Duration(seconds: 10));
    engine.onSecondTick(opened);
    final drawing = engine.displayGame('JS_SC', opened);
    expect(LotteryPeriodHelper.phaseOf(drawing, opened), LotteryDisplayPhase.drawing);
    expect(engine.needsDrawRecovery('JS_SC', opened), isTrue);

    final seeded = LotteryPeriodEngine();
    seeded.bootstrap(
      [
        const LotteryGameModel(
          id: 'JS_SC',
          name: '极速赛车',
          currentIssue: '1',
        ),
      ],
      t0,
    );
    seeded.onPeriodTick('JS_SC', issue: '1', seconds: 40, now: t0);
    final g = seeded.displayGame('JS_SC', t0);
    expect(
      g.openAtEpochMs,
      t0.add(const Duration(seconds: 40)).millisecondsSinceEpoch,
    );
    expect(seeded.countdownFor('JS_SC', t0), 40);
    expect(seeded.needsDrawRecovery('JS_SC', t0), isFalse);
  });

  test('开奖中超过 20 秒后，快照里的未来开奖时刻盖过钉死', () {
    final engine = LotteryPeriodEngine();
    final t0 = DateTime(2099, 6, 1, 12, 0, 0);
    final openAt = t0.add(const Duration(seconds: 40)).millisecondsSinceEpoch;
    final sealAt = t0.add(const Duration(seconds: 10)).millisecondsSinceEpoch;
    engine.bootstrap(
      [
        LotteryGameModel(
          id: 'JS_SC',
          name: '极速赛车',
          currentIssue: '34136341',
          countdownSeconds: 40,
          openAtEpochMs: openAt,
          sealSeconds: 30,
          sealAtEpochMs: sealAt,
        ),
      ],
      t0,
    );
    final opened = t0.add(const Duration(seconds: 40));
    engine.onSecondTick(opened);
    expect(engine.needsDrawRecovery('JS_SC', opened), isTrue);

    final later = opened.add(LotteryPeriodEngine.stuckDrawingAdopt);
    final serverOpen = later.add(const Duration(seconds: 30));
    engine.onPeriodTick(
      'JS_SC',
      issue: '34136341',
      seconds: 30,
      openAtEpochMs: serverOpen.millisecondsSinceEpoch,
      sealAtEpochMs: later.add(const Duration(seconds: 20)).millisecondsSinceEpoch,
      sealSeconds: 10,
      now: later,
    );
    final recovered = engine.displayGame('JS_SC', later);
    expect(recovered.currentIssue, '34136341');
    expect(LotteryPeriodHelper.phaseOf(recovered, later), LotteryDisplayPhase.betting);
    expect(LotteryPeriodHelper.openRemainSeconds(recovered, later), 30);
    expect(engine.needsDrawRecovery('JS_SC', later), isFalse);
  });

  test('换期后晚到的旧期帧只收上期开奖号，不把新期拉回开奖中', () {
    final engine = LotteryPeriodEngine();
    final t0 = DateTime(2099, 6, 1, 12, 0, 0);
    final openAt = t0.add(const Duration(seconds: 40)).millisecondsSinceEpoch;
    engine.bootstrap(
      [
        LotteryGameModel(
          id: 'JS_SC',
          name: '极速赛车',
          currentIssue: '34136341',
          countdownSeconds: 40,
          openAtEpochMs: openAt,
          sealSeconds: 30,
          sealAtEpochMs: t0.add(const Duration(seconds: 10)).millisecondsSinceEpoch,
        ),
      ],
      t0,
    );
    final opened = t0.add(const Duration(seconds: 41));
    engine.onSecondTick(opened);
    expect(engine.needsDrawRecovery('JS_SC', opened), isTrue);

    final nextOpen = opened.add(const Duration(seconds: 75)).millisecondsSinceEpoch;
    final nextSeal = opened.add(const Duration(seconds: 45)).millisecondsSinceEpoch;
    engine.onPeriodTick(
      'JS_SC',
      issue: '34136342',
      seconds: 75,
      openAtEpochMs: nextOpen,
      sealAtEpochMs: nextSeal,
      sealSeconds: 30,
      lastIssue: '34136341',
      lastRanks: const [1, 2, 3, 4, 5, 6, 7, 8, 9, 10],
      now: opened,
    );
    expect(engine.needsDrawRecovery('JS_SC', opened), isFalse);

    final stale = opened.add(const Duration(milliseconds: 300));
    engine.onPeriodTick(
      'JS_SC',
      issue: '34136341',
      seconds: 0,
      openAtEpochMs: openAt,
      sealAtEpochMs: t0.add(const Duration(seconds: 10)).millisecondsSinceEpoch,
      sealSeconds: 30,
      lastIssue: '34136340',
      lastRanks: const [10, 9, 8, 7, 6, 5, 4, 3, 2, 1],
      now: stale,
    );
    engine.mergeHttpSnapshot(
      [
        LotteryGameModel(
          id: 'JS_SC',
          name: '极速赛车',
          currentIssue: '34136341',
          countdownSeconds: 0,
          openAtEpochMs: openAt,
          sealSeconds: 30,
        ),
      ],
      stale,
    );
    engine.patchGame(
      LotteryGameModel(
        id: 'JS_SC',
        name: '极速赛车',
        currentIssue: '34136341',
        countdownSeconds: 0,
        openAtEpochMs: openAt,
      ),
      stale,
    );
    engine.onSecondTick(stale);

    final shown = engine.displayGame('JS_SC', stale);
    expect(shown.currentIssue, '34136342');
    expect(shown.previousIssue, '34136341');
    expect(shown.previousResults, const [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]);
    expect(LotteryPeriodHelper.phaseOf(shown, stale), LotteryDisplayPhase.betting);
    expect(engine.needsDrawRecovery('JS_SC', stale), isFalse);
    expect(engine.countdownFor('JS_SC', stale), greaterThanOrEqualTo(74));
  });
}
