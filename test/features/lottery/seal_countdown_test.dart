import 'package:flutter_test/flutter_test.dart';
import 'package:letou_app/data/models/lottery_game_model.dart';
import 'package:letou_app/features/lottery/utils/lottery_period_ui.dart';

/// 对齐《App期数封盘与开奖时间_20260923》+ plus-ui `lotteryFeed.ts`。
void main() {
  final t0 = DateTime(2026, 9, 23, 12, 0, 0);

  test('距封盘：优先 sealAtEpochMs（文档 §4.2 / web sealRemainSeconds）', () {
    final openAt = t0.add(const Duration(seconds: 75));
    final sealAt = t0.add(const Duration(seconds: 45)); // sealSeconds=30
    final g = LotteryGameModel(
      id: 'JS_SC',
      name: '极速赛车',
      currentIssue: '1',
      countdownSeconds: 75,
      openAtEpochMs: openAt.millisecondsSinceEpoch,
      sealAtEpochMs: sealAt.millisecondsSinceEpoch,
      sealSeconds: 30,
    );
    expect(LotteryPeriodHelper.sealRemainSeconds(g, t0), 45);
    expect(LotteryPeriodHelper.bettingCountdownSeconds(g, t0), 45);
    expect(LotteryPeriodHelper.openRemainSeconds(g, t0), 75);
    expect(LotteryPeriodHelper.phaseOf(g, t0), LotteryDisplayPhase.betting);
  });

  test('封盘中：now≥sealAt 后按 openAt 倒数', () {
    final openAt = t0.add(const Duration(seconds: 75));
    final sealAt = t0.add(const Duration(seconds: 45));
    final g = LotteryGameModel(
      id: 'JS_SC',
      name: '极速赛车',
      currentIssue: '1',
      countdownSeconds: 25,
      openAtEpochMs: openAt.millisecondsSinceEpoch,
      sealAtEpochMs: sealAt.millisecondsSinceEpoch,
      sealSeconds: 30,
    );
    final duringSeal = t0.add(const Duration(seconds: 50));
    expect(LotteryPeriodHelper.sealRemainSeconds(g, duringSeal), 0);
    expect(LotteryPeriodHelper.openRemainSeconds(g, duringSeal), 25);
    expect(
      LotteryPeriodHelper.phaseOf(g, duringSeal),
      LotteryDisplayPhase.sealed,
    );
  });

  test('无 sealAt：用 openAt − sealSeconds', () {
    final openAt = t0.add(const Duration(seconds: 75));
    final g = LotteryGameModel(
      id: 'JS_SC',
      name: '极速赛车',
      currentIssue: '1',
      countdownSeconds: 75,
      openAtEpochMs: openAt.millisecondsSinceEpoch,
      sealSeconds: 30,
    );
    expect(LotteryPeriodRules.sealSecondsOf(g), 30);
    expect(LotteryPeriodHelper.sealRemainSeconds(g, t0), 45);
    expect(LotteryPeriodHelper.phaseOf(g, t0), LotteryDisplayPhase.betting);
    final nearSeal = t0.add(const Duration(seconds: 50));
    expect(LotteryPeriodHelper.phaseOf(g, nearSeal), LotteryDisplayPhase.sealed);
    expect(LotteryPeriodHelper.openRemainSeconds(g, nearSeal), 25);
  });

  test('无 openAt：countdown − sealSeconds（web 兜底）', () {
    final g = LotteryGameModel(
      id: 'JS_SC',
      name: '极速赛车',
      currentIssue: '1',
      countdownSeconds: 75,
      sealSeconds: 15,
    );
    expect(LotteryPeriodRules.sealSecondsOf(g), 15);
    expect(LotteryPeriodHelper.bettingCountdownSeconds(g), 60);
    expect(LotteryPeriodHelper.phaseOf(g), LotteryDisplayPhase.betting);

    final sealed = g.copyWith(countdownSeconds: 12);
    expect(LotteryPeriodHelper.phaseOf(sealed), LotteryDisplayPhase.sealed);
    expect(LotteryPeriodHelper.bettingCountdownSeconds(sealed), 0);
  });

  test('web sealGap：有 sealAt/openAt 时 gap 取时刻差，不盲信过期 sealSeconds', () {
    final openAt = t0.add(const Duration(seconds: 75));
    // 服务端 sealAt 已按 30s 重算；旧 sealSeconds 字段若仍写 10，应以时刻差为准
    final sealAt = t0.add(const Duration(seconds: 45));
    final g = LotteryGameModel(
      id: 'JS_SC',
      name: '极速赛车',
      currentIssue: '1',
      countdownSeconds: 75,
      openAtEpochMs: openAt.millisecondsSinceEpoch,
      sealAtEpochMs: sealAt.millisecondsSinceEpoch,
      sealSeconds: 10,
    );
    expect(LotteryPeriodRules.sealSecondsOf(g), 30);
    expect(LotteryPeriodHelper.sealRemainSeconds(g, t0), 45);
  });

  test('HTTP 仅 openAt：没有封盘时刻时不把整段开奖剩余当成距封盘', () {
    final openAt = t0.add(const Duration(seconds: 75));
    final g = LotteryGameModel(
      id: 'JS_SC',
      name: '极速赛车',
      currentIssue: '1',
      countdownSeconds: 75,
      openAtEpochMs: openAt.millisecondsSinceEpoch,
    );
    expect(LotteryPeriodRules.sealSecondsOf(g), 0);
    expect(LotteryPeriodRules.hasSealConfig(g), isFalse);
    expect(LotteryPeriodHelper.phaseOf(g, t0), LotteryDisplayPhase.betting);
    final nearOpen = t0.add(const Duration(seconds: 66));
    expect(LotteryPeriodHelper.phaseOf(g, nearOpen), LotteryDisplayPhase.betting);
    expect(LotteryPeriodHelper.bettingCountdownSeconds(g, nearOpen), 0);
    expect(LotteryPeriodHelper.openRemainSeconds(g, nearOpen), 9);
  });

  test('期态条数字是离开奖剩余，封盘点从 31 接到 30', () {
    final openAt = t0.add(const Duration(seconds: 75));
    final sealAt = t0.add(const Duration(seconds: 45));
    final g = LotteryGameModel(
      id: 'JS_SC',
      name: '极速赛车',
      currentIssue: '1',
      countdownSeconds: 75,
      openAtEpochMs: openAt.millisecondsSinceEpoch,
      sealAtEpochMs: sealAt.millisecondsSinceEpoch,
      sealSeconds: 30,
    );
    expect(LotteryPeriodHelper.phaseOf(g, t0), LotteryDisplayPhase.betting);
    expect(LotteryPeriodHelper.statusClockSeconds(g, t0), 75);

    final beforeSeal = t0.add(const Duration(seconds: 44));
    expect(LotteryPeriodHelper.phaseOf(g, beforeSeal), LotteryDisplayPhase.betting);
    expect(LotteryPeriodHelper.statusClockSeconds(g, beforeSeal), 31);

    final atSeal = t0.add(const Duration(seconds: 45));
    expect(LotteryPeriodHelper.phaseOf(g, atSeal), LotteryDisplayPhase.sealed);
    expect(LotteryPeriodHelper.statusClockSeconds(g, atSeal), 30);

    final opened = t0.add(const Duration(seconds: 75));
    expect(LotteryPeriodHelper.phaseOf(g, opened), LotteryDisplayPhase.drawing);
    expect(LotteryPeriodHelper.statusClockSeconds(g, opened), 0);
  });
}
