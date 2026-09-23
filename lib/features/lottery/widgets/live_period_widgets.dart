import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../config/theme/app_colors.dart';
import '../../../data/models/lottery_game_model.dart';
import '../../../shared/widgets/flip_countdown.dart';
import '../../../shared/widgets/lottery_ball.dart';
import '../providers/lottery_live_provider.dart';
import '../utils/draw_history_rows.dart';
import '../utils/lottery_period_ui.dart';

/// 从房间 live 态读取最新开奖快照（不读 uiTick）。
({String issue, List<int> ranks, bool placeholder}) latestDrawSnapshot(
  RoomLotteryLiveState state,
  String gameId,
) {
  final g = state.gameById(gameId);
  if (g == null) {
    return (issue: '', ranks: const <int>[], placeholder: false);
  }
  final ranks = g.previousResults.where((n) => n > 0).toList(growable: false);
  final issue = g.previousIssue?.trim() ?? '';
  final placeholder = ranks.isEmpty && g.isDrawing;
  return (issue: issue, ranks: ranks, placeholder: placeholder);
}

/// 上期期号：仅 [latestDrawWatchKey] 变化时重建。
class LiveLatestDrawIssueText extends ConsumerWidget {
  const LiveLatestDrawIssueText({
    super.key,
    required this.roomId,
    required this.gameId,
    this.compact = false,
    this.style,
    this.textAlign = TextAlign.center,
    this.emptyLabel = '--',
  });

  final String roomId;
  final String gameId;
  final bool compact;
  final TextStyle? style;
  final TextAlign textAlign;
  final String emptyLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(
      roomLotteryLiveProvider(roomId).select((s) {
        final g = s.gameById(gameId);
        if (g == null) return '';
        return latestDrawWatchKey(
          previousIssue: g.previousIssue,
          previousResults: g.previousResults,
          isDrawing: g.isDrawing,
        );
      }),
    );
    final snap = latestDrawSnapshot(ref.read(roomLotteryLiveProvider(roomId)), gameId);
    final label = snap.issue.isEmpty
        ? emptyLabel
        : (compact ? compactIssueNo(snap.issue) : snap.issue);
    return Text(
      label,
      style: style,
      textAlign: textAlign,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

/// 最新开奖球：仅上期期号/球号变化时重建，不随倒计时 uiTick 刷新。
class LiveLatestDrawBalls extends ConsumerWidget {
  const LiveLatestDrawBalls({
    super.key,
    required this.roomId,
    required this.gameId,
    this.ballSize,
    this.gap,
    this.expandSlots = false,
    this.digitFontSize,
    this.boxBoost = 0,
  });

  final String roomId;
  final String gameId;
  final double? ballSize;
  final double? gap;
  final bool expandSlots;
  final double? digitFontSize;
  final double boxBoost;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(
      roomLotteryLiveProvider(roomId).select((s) {
        final g = s.gameById(gameId);
        if (g == null) return '';
        return latestDrawWatchKey(
          previousIssue: g.previousIssue,
          previousResults: g.previousResults,
          isDrawing: g.isDrawing,
        );
      }),
    );
    final snap = latestDrawSnapshot(ref.read(roomLotteryLiveProvider(roomId)), gameId);
    return LotteryBallRow(
      numbers: snap.ranks,
      ballSize: ballSize,
      gap: gap,
      placeholder: snap.placeholder,
      expandSlots: expandSlots,
      digitFontSize: digitFontSize,
      boxBoost: boxBoost,
    );
  }
}

/// 冠亚和文案：随最新开奖球同步更新。
class LiveLatestDrawSumText extends ConsumerWidget {
  const LiveLatestDrawSumText({
    super.key,
    required this.roomId,
    required this.gameId,
    this.prefix = '冠亚和',
    this.style,
  });

  final String roomId;
  final String gameId;
  final String prefix;
  final TextStyle? style;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(
      roomLotteryLiveProvider(roomId).select((s) {
        final g = s.gameById(gameId);
        if (g == null) return '';
        return latestDrawWatchKey(
          previousIssue: g.previousIssue,
          previousResults: g.previousResults,
          isDrawing: g.isDrawing,
        );
      }),
    );
    final ranks = latestDrawSnapshot(
      ref.read(roomLotteryLiveProvider(roomId)),
      gameId,
    ).ranks;
    var sumText = '';
    if (ranks.length >= 2) {
      final sum = ranks[0] + ranks[1];
      final body = '$sum${sum >= 12 ? '大' : '小'}${sum % 2 == 0 ? '双' : '单'}';
      sumText = prefix.trim().isEmpty ? body : ' $body';
    }
    return Text(
      '$prefix$sumText',
      style: style ??
          TextStyle(
            fontSize: 11.sp,
            color: const Color(0xFF7A7A7A),
            fontWeight: FontWeight.w500,
          ),
    );
  }
}

/// 房间级 uiTick 驱动倒计时数字，无独立 Timer.periodic。
class LiveFlipCountdown extends ConsumerWidget {
  const LiveFlipCountdown({
    super.key,
    required this.roomId,
    required this.gameId,
    this.tickEnabled = true,
    this.digitColor = AppColors.countdownGreen,
    this.bettingMode = false,
  });

  final String roomId;
  final String gameId;
  final bool tickEnabled;
  final Color digitColor;
  /// true = 显示距封盘（总秒数 − 提前封盘秒数）
  final bool bettingMode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (tickEnabled) {
      ref.watch(roomLotteryLiveProvider(roomId).select((s) => s.uiTick));
    }
    final notifier = ref.read(roomLotteryLiveProvider(roomId).notifier);
    var sec = notifier.countdownFor(gameId);
    if (bettingMode) {
      final game = notifier.displayGameFor(gameId);
      sec = LotteryPeriodHelper.bettingCountdownSeconds(
        (game ??
                LotteryGameModel(
                  id: gameId,
                  name: '',
                  currentIssue: '',
                  countdownSeconds: sec,
                ))
            .copyWith(countdownSeconds: sec),
      );
    }
    return FlipCountdown(seconds: sec, digitColor: digitColor);
  }
}

/// 聊天/大厅期态条：元数据走 Riverpod select，倒计时数字走 uiTick。
class LiveLotteryPeriodCountdownRow extends ConsumerWidget {
  const LiveLotteryPeriodCountdownRow({
    super.key,
    required this.roomId,
    required this.gameId,
    this.tickEnabled = true,
    this.issuePrefix,
    this.showIssue = true,
    this.issueStyle,
    this.sealedStyle,
    this.drawingStyle,
    this.countdownColor = AppColors.danger,
  });

  final String roomId;
  final String gameId;
  final bool tickEnabled;
  final String? issuePrefix;
  final bool showIssue;
  final TextStyle? issueStyle;
  final TextStyle? sealedStyle;
  final TextStyle? drawingStyle;
  final Color countdownColor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (tickEnabled) {
      ref.watch(roomLotteryLiveProvider(roomId).select((s) => s.uiTick));
    }
    final notifier = ref.read(roomLotteryLiveProvider(roomId).notifier);
    final game = notifier.displayGameFor(gameId);
    if (game == null) return const SizedBox.shrink();
    final issueLabel = compactIssueNo(game.currentIssue);

    return LotteryPeriodCountdownRow(
      game: game,
      issuePrefix: issuePrefix ?? issueLabel,
      showIssue: showIssue,
      compactCountdown: true,
      issueStyle: issueStyle,
      sealedStyle: sealedStyle,
      drawingStyle: drawingStyle,
      countdownColor: countdownColor,
    );
  }
}

/// 大厅彩种卡片倒计时区：聊天遮罩打开时可关闭 tick，避免后台 rebuild。
class LiveHallGameCountdown extends ConsumerWidget {
  const LiveHallGameCountdown({
    super.key,
    required this.roomId,
    required this.gameId,
    this.tickEnabled = true,
  });

  final String roomId;
  final String gameId;
  final bool tickEnabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (tickEnabled) {
      ref.watch(roomLotteryLiveProvider(roomId).select((s) => s.uiTick));
    }
    final notifier = ref.read(roomLotteryLiveProvider(roomId).notifier);
    final game = notifier.displayGameFor(gameId);
    if (game == null) return const SizedBox.shrink();
    final now = DateTime.now();
    final phase = LotteryPeriodHelper.phaseOf(game, now);

    return switch (phase) {
      LotteryDisplayPhase.drawing => SizedBox(
          height: 18.h,
          child: Align(
            alignment: Alignment.centerRight,
            child: Text(
              '开奖中',
              style: TextStyle(
                fontSize: 13.sp,
                color: AppColors.danger,
                fontWeight: FontWeight.w600,
                height: 1,
              ),
            ),
          ),
        ),
      LotteryDisplayPhase.sealed => SizedBox(
          height: 18.h,
          child: Align(
            alignment: Alignment.centerRight,
            child: Text(
              '封盘中，距离开奖${LotteryPeriodHelper.statusClockSeconds(game, now)}秒',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13.sp,
                color: AppColors.danger,
                fontWeight: FontWeight.w600,
                height: 1,
              ),
            ),
          ),
        ),
      LotteryDisplayPhase.betting => SizedBox(
          height: 18.h,
          child: Align(
            alignment: Alignment.centerRight,
            child: FlipCountdown(
              seconds: LotteryPeriodHelper.bettingCountdownSeconds(game, now),
              compact: true,
              digitColor: AppColors.danger,
            ),
          ),
        ),
    };
  }
}
