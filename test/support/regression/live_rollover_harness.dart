import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:letou_app/features/lottery/providers/lottery_live_provider.dart';
import 'package:letou_app/features/lottery/utils/draw_history_rows.dart';
import 'package:letou_app/features/lottery/utils/lottery_period_ui.dart';

/// 真实联调：等待一次换期 rollover，断言「开奖中」与期号一致性。
abstract final class LiveRolloverHarness {
  /// 等待进入开奖窗口（CD=0 或 isDrawing），再等待回到下注（距封盘）。
  static Future<void> assertRolloverDrawingAndIssueConsistency({
    required ProviderContainer container,
    required String roomCode,
    required String gameId,
    Duration maxWait = const Duration(seconds: 330),
    Duration exitDrawingTimeout = const Duration(seconds: 20),
  }) async {
    final live = container.read(roomLotteryLiveProvider(roomCode).notifier);
    final waitUntil = DateTime.now().add(maxWait);
    var sawRollover = false;

    while (DateTime.now().isBefore(waitUntil)) {
      final g = live.displayGameFor(gameId);
      if (g == null) {
        await Future<void>.delayed(const Duration(milliseconds: 300));
        continue;
      }
      final phase = LotteryPeriodHelper.phaseOf(g);
      if (phase == LotteryDisplayPhase.drawing ||
          g.isDrawing ||
          live.countdownFor(gameId) <= 0) {
        sawRollover = true;
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }

    if (!sawRollover) {
      throw StateError(
        '未在 ${maxWait.inSeconds}s 内观测到换期/开奖中 gameId=$gameId',
      );
    }

    final exitUntil = DateTime.now().add(exitDrawingTimeout);
    List<int>? frozenDuringDrawing;

    while (DateTime.now().isBefore(exitUntil)) {
      final g = live.displayGameFor(gameId);
      if (g == null) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
        continue;
      }

      if (g.isDrawing || LotteryPeriodHelper.phaseOf(g) == LotteryDisplayPhase.drawing) {
        frozenDuringDrawing ??= List<int>.from(g.previousResults);
        if (frozenDuringDrawing.isNotEmpty &&
            g.previousResults.isNotEmpty &&
            frozenDuringDrawing.join(',') != g.previousResults.join(',')) {
          throw StateError(
            '开奖中球号不应提前刷新: was $frozenDuringDrawing now ${g.previousResults}',
          );
        }
        await Future<void>.delayed(const Duration(milliseconds: 200));
        continue;
      }

      if (g.countdownSeconds > LotteryPeriodRules.sealWarnSeconds) {
        final cur = g.currentIssue;
        final prev = g.previousIssue ?? '';
        if (cur.isEmpty || prev.isEmpty) {
          throw StateError('换期后缺少期号 current=$cur previous=$prev');
        }
        final ck = issueCompareKey(cur);
        final pk = issueCompareKey(prev);
        if (ck <= pk) {
          throw StateError(
            '换期后顶栏期号未前进: current=$cur previous=$prev',
          );
        }
        return;
      }

      await Future<void>.delayed(const Duration(milliseconds: 200));
    }

    throw StateError(
      '开奖中未在 ${exitDrawingTimeout.inSeconds}s 内切换到距封盘 gameId=$gameId',
    );
  }
}
