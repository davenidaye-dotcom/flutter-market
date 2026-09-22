
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
}
