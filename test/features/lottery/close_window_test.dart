import 'package:flutter_test/flutter_test.dart';
import 'package:letou_app/data/models/lottery_game_model.dart';
import 'package:letou_app/features/lottery/engine/lottery_period_engine.dart';
import 'package:letou_app/features/lottery/utils/lottery_period_ui.dart';

/// 后台「封盘时间窗」：窗口内显示封盘中 + 距开盘倒计时，禁止下注。
void main() {
  final t0 = DateTime(2026, 10, 14, 3, 0, 0);
  int ms(DateTime d) => d.millisecondsSinceEpoch;

  LotteryGameModel game({int? start, int? end}) => LotteryGameModel(
        id: 'JS_SC',
        name: '极速赛车',
        currentIssue: '100',
        countdownSeconds: 60,
        openAtEpochMs: ms(t0.add(const Duration(seconds: 60))),
        sealAtEpochMs: ms(t0.add(const Duration(seconds: 50))),
        sealSeconds: 10,
        closeStartEpochMs: start,
        closeEndEpochMs: end,
      );

  test('窗口外正常投注，窗口内进入 closed 且不可下注', () {
    final start = t0.add(const Duration(minutes: 10));
    final end = t0.add(const Duration(minutes: 70));
    final g = game(start: ms(start), end: ms(end));
    // 把期的时刻推远，避免期的封盘/开奖干扰
    final far = g.copyWith(
      openAtEpochMs: ms(t0.add(const Duration(hours: 5))),
      sealAtEpochMs: ms(t0.add(const Duration(hours: 5, seconds: -10))),
    );

    expect(LotteryPeriodHelper.phaseOf(far, t0), LotteryDisplayPhase.betting);
    expect(LotteryPeriodHelper.canBetNow(far, t0), isTrue);

    final inside = start.add(const Duration(minutes: 1));
    expect(LotteryPeriodHelper.phaseOf(far, inside), LotteryDisplayPhase.closed);
    expect(LotteryPeriodHelper.canBetNow(far, inside), isFalse);
    expect(LotteryPeriodHelper.closeRemainSeconds(far, inside), 59 * 60);

    // 结束的这一刻起恢复
    expect(LotteryPeriodHelper.inCloseWindow(far, end), isFalse);
    expect(LotteryPeriodHelper.phaseOf(far, end), LotteryDisplayPhase.betting);
  });

  test('窗口内即使该期已在开奖中，也优先显示封盘中', () {
    final g = game(
      start: ms(t0.subtract(const Duration(minutes: 1))),
      end: ms(t0.add(const Duration(minutes: 5))),
    ).copyWith(isDrawing: true);
    expect(LotteryPeriodHelper.phaseOf(g, t0), LotteryDisplayPhase.closed);
  });

  test('没配置窗口（null / 0）不影响原有相位', () {
    expect(LotteryPeriodHelper.phaseOf(game(), t0), LotteryDisplayPhase.betting);
    expect(
      LotteryPeriodHelper.phaseOf(game(start: 0, end: 0), t0),
      LotteryDisplayPhase.betting,
    );
  });

  test('倒计时文案：不足 1 小时 mm:ss，否则 h:mm:ss', () {
    expect(LotteryPeriodHelper.formatCloseRemain(59), '00:59');
    expect(LotteryPeriodHelper.formatCloseRemain(3599), '59:59');
    expect(LotteryPeriodHelper.formatCloseRemain(3600), '1:00:00');
    expect(LotteryPeriodHelper.formatCloseRemain(5025), '1:23:45');
  });

  test('WS tick 带窗口 → 进入 closed；下一个 tick 不带 → 清除', () {
    final engine = LotteryPeriodEngine();
    engine.bootstrap([game()], t0);

    engine.onPeriodTick(
      'JS_SC',
      issue: '100',
      seconds: 60,
      openAtEpochMs: ms(t0.add(const Duration(seconds: 60))),
      sealAtEpochMs: ms(t0.add(const Duration(seconds: 50))),
      closeStartEpochMs: ms(t0.subtract(const Duration(minutes: 1))),
      closeEndEpochMs: ms(t0.add(const Duration(minutes: 30))),
      now: t0,
    );
    final closed = engine.displayGame('JS_SC', t0);
    expect(LotteryPeriodHelper.phaseOf(closed, t0), LotteryDisplayPhase.closed);

    engine.onPeriodTick(
      'JS_SC',
      issue: '100',
      seconds: 60,
      openAtEpochMs: ms(t0.add(const Duration(seconds: 60))),
      sealAtEpochMs: ms(t0.add(const Duration(seconds: 50))),
      closeStartEpochMs: 0,
      closeEndEpochMs: 0,
      now: t0,
    );
    final open = engine.displayGame('JS_SC', t0);
    expect(LotteryPeriodHelper.phaseOf(open, t0), LotteryDisplayPhase.betting);
  });
}
