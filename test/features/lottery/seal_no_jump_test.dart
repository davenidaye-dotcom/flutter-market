
import 'package:flutter_test/flutter_test.dart';
import 'package:letou_app/data/models/lottery_game_model.dart';
import 'package:letou_app/features/lottery/engine/lottery_period_engine.dart';
import 'package:letou_app/features/lottery/utils/lottery_period_ui.dart';

void main() {
  test('同期内后到的 sealAt/openAt 按服务端时刻更新距封盘', () {
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

    // 与 web mergePeriod 一致：后到的 sealAt/openAt 覆盖，距封盘跟着变。
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
    expect(LotteryPeriodHelper.bettingCountdownSeconds(after, t15), 50);
    expect(LotteryPeriodHelper.openRemainSeconds(after, t15), 80);

    engine.applySealConfig(
      'JS_SC',
      sealSeconds: 10,
      sealAtEpochMs: t0.add(const Duration(seconds: 70)).millisecondsSinceEpoch,
      now: t15,
    );
    final afterEnrich = engine.displayGame('JS_SC', t15);
    // sealSeconds=10 不得把 sealAt 改回 open-10；仍用刚写入的 sealAt。
    expect(LotteryPeriodHelper.bettingCountdownSeconds(afterEnrich, t15), 55);
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

  test('封盘前只带 openAt 时按原提前量平移 sealAt', () {
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
    expect(LotteryPeriodHelper.bettingCountdownSeconds(g, t15), 50);
    expect(LotteryPeriodHelper.openRemainSeconds(g, t15), 80);
  });
}
