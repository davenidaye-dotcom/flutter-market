import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../config/theme/app_colors.dart';
import '../../../data/models/lottery_game_model.dart';
import '../../../shared/widgets/flip_countdown.dart';

/// 对齐《App期数封盘与开奖时间_20260923》与 plus-ui `lotteryFeed.ts`。
/// - `openAtEpochMs` = 本期开奖时刻（距开奖终点）
/// - `sealAtEpochMs` = 封盘时刻（距封盘）
/// - `sealSeconds` = 开奖前多少秒封盘（后台配置）
/// 无 seal 配置时 **不要捏造 10s**（web `sealGapSeconds` 返回 0）。
class LotteryPeriodRules {
  /// 仅作文案/兼容默认；相位倒计时禁止拿它冒充后台配置。
  static const defaultSealSeconds = 10;
  static const maxSealSeconds = 119;

  /// 兼容旧引用；请优先 [sealSecondsOf] / [sealRemainSeconds]。
  static const sealWarnSeconds = defaultSealSeconds;

  /// 是否已有可用的封盘配置（sealSeconds 或 open−seal 时刻差）。
  static bool hasSealConfig(LotteryGameModel game) => sealSecondsOf(game) > 0;

  /// 封盘提前量：对齐 web `sealGapSeconds`——优先 open−seal 时刻差，其次配置 sealSeconds。
  static int sealSecondsOf(LotteryGameModel game) {
    final open = game.openAtEpochMs ?? 0;
    final seal = game.sealAtEpochMs ?? 0;
    if (open > seal && seal > 0) {
      final gap = ((open - seal) / 1000).round();
      if (gap >= 1 && gap <= maxSealSeconds) return gap;
    }
    final configured = game.sealSeconds ?? 0;
    if (configured >= 1 && configured <= maxSealSeconds) return configured;
    return 0;
  }

  static int _remainToEpochMs(int epochMs, DateTime now) {
    if (epochMs <= 0) return 0;
    return math.max(0, ((epochMs - now.millisecondsSinceEpoch) / 1000).floor());
  }
}

enum LotteryDisplayPhase { betting, sealed, drawing }

abstract final class LotteryPeriodHelper {
  /// 距开奖：文档 §4.1——优先 `openAtEpochMs` 本地算，勿靠 countdown 自减。
  static int openRemainSeconds(LotteryGameModel game, [DateTime? now]) {
    final clock = now ?? DateTime.now();
    final openAt = game.openAtEpochMs ?? 0;
    if (openAt > 0) {
      return LotteryPeriodRules._remainToEpochMs(openAt, clock);
    }
    return math.max(0, game.countdownSeconds);
  }

  /// 距封盘：文档 §4.2 + web `sealRemainSeconds`——优先 `sealAtEpochMs`。
  static int sealRemainSeconds(LotteryGameModel game, [DateTime? now]) {
    final clock = now ?? DateTime.now();
    final sealAt = game.sealAtEpochMs ?? 0;
    if (sealAt > 0) {
      return LotteryPeriodRules._remainToEpochMs(sealAt, clock);
    }
    final open = game.openAtEpochMs ?? 0;
    final gap = LotteryPeriodRules.sealSecondsOf(game);
    if (open > 0 && gap > 0) {
      return LotteryPeriodRules._remainToEpochMs(open - gap * 1000, clock);
    }
    final openLeft = openRemainSeconds(game, clock);
    if (gap > 0) return math.max(0, openLeft - gap);
    return 0;
  }

  static LotteryDisplayPhase phaseOf(LotteryGameModel game, [DateTime? now]) {
    if (game.isDrawing || game.status == LotteryStatus.drawing) {
      return LotteryDisplayPhase.drawing;
    }
    final clock = now ?? DateTime.now();
    final openLeft = openRemainSeconds(game, clock);
    // 与 web openText 一致：封盘和开奖剩余都到 0，显示开奖中，不停留在「封盘中 00:00」。
    if (openLeft <= 0) {
      return LotteryDisplayPhase.drawing;
    }
    final sealAt = game.sealAtEpochMs ?? 0;
    final gap = LotteryPeriodRules.sealSecondsOf(game);
    // 无 sealAt / sealSeconds 前不进「封盘中」（防 HTTP 缺字段假窗口）
    if (sealAt <= 0 && gap <= 0) {
      return LotteryDisplayPhase.betting;
    }
    // 开奖剩余减到提前量：与翻页钟同一条 openAt，到 0 的同一秒进入封盘。
    if (bettingCountdownSeconds(game, clock) <= 0) {
      return LotteryDisplayPhase.sealed;
    }
    return LotteryDisplayPhase.betting;
  }

  /// 红色距封盘翻页钟：直接数到封盘时刻。
  /// 封盘时刻 = 开盘 +（一期总秒数 − 提前封盘秒数）。没有封盘时刻时不改成数整段开奖剩余。
  static int bettingCountdownSeconds(LotteryGameModel game, [DateTime? now]) {
    return sealRemainSeconds(game, now);
  }

  /// 封盘后「距离开奖 N 秒」用的离开奖剩余。封盘前翻页钟用 [bettingCountdownSeconds]。
  static int statusClockSeconds(LotteryGameModel game, [DateTime? now]) {
    return openRemainSeconds(game, now);
  }

  static bool showDrawingPlaceholders(LotteryGameModel game) {
    return phaseOf(game) == LotteryDisplayPhase.drawing &&
        game.previousResults.isEmpty;
  }

  static bool canBetNow(LotteryGameModel game, [DateTime? now]) {
    return phaseOf(game, now) == LotteryDisplayPhase.betting;
  }

  static LotteryStatus statusFromCountdown(
    int seconds, {
    int sealSeconds = 0,
    bool hasResult = true,
  }) {
    if (seconds <= 0) return LotteryStatus.drawing;
    if (sealSeconds > 0 && seconds <= sealSeconds) return LotteryStatus.sealed;
    return LotteryStatus.open;
  }
}

/// 期态条：封盘前红色翻页钟（距封盘）→「封盘中，距离开奖 N 秒」→ 开奖中
class LotteryPeriodCountdownRow extends StatelessWidget {
  const LotteryPeriodCountdownRow({
    super.key,
    required this.game,
    this.issuePrefix,
    this.showIssue = true,
    this.compactCountdown = false,
    this.issueStyle,
    this.sealedStyle,
    this.drawingStyle,
  });

  final LotteryGameModel game;
  final String? issuePrefix;
  /// false 时期号由外层单独列展示（与下方开奖球对齐）
  final bool showIssue;
  /// 紧凑倒计时，与「封盘中/开奖中」同高，避免期态切换抖动
  final bool compactCountdown;
  final TextStyle? issueStyle;
  final TextStyle? sealedStyle;
  final TextStyle? drawingStyle;

  double get _rowHeight => compactCountdown ? 18.h : 26.h;

  Widget _phaseRow(Widget child) {
    return SizedBox(
      height: _rowHeight,
      child: Align(
        alignment: Alignment.centerLeft,
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final phase = LotteryPeriodHelper.phaseOf(game, now);
    final issue = showIssue ? (issuePrefix ?? '') : '';
    final baseIssue = TextStyle(
      fontSize: 12.sp,
      color: AppColors.textPrimary,
    );
    final issueTextStyle = issueStyle ?? baseIssue;
    final phaseLabel = TextStyle(
      fontSize: 13.sp,
      color: AppColors.danger,
      fontWeight: FontWeight.w600,
      height: 1,
    );

    return switch (phase) {
      LotteryDisplayPhase.drawing => _phaseRow(
          Text.rich(
            TextSpan(
              children: [
                if (issue.isNotEmpty)
                  TextSpan(text: '$issue ', style: issueTextStyle),
                TextSpan(
                  text: '开奖中',
                  style: drawingStyle ?? phaseLabel,
                ),
              ],
            ),
          ),
        ),
      LotteryDisplayPhase.sealed => _phaseRow(
          Text.rich(
            TextSpan(
              children: [
                if (issue.isNotEmpty)
                  TextSpan(text: '$issue ', style: issueTextStyle),
                TextSpan(
                  text:
                      '封盘中，距离开奖${LotteryPeriodHelper.statusClockSeconds(game, now)}秒',
                  style: sealedStyle ?? phaseLabel,
                ),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      LotteryDisplayPhase.betting => _phaseRow(
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (issue.isNotEmpty) Text(issue, style: issueTextStyle),
              if (issue.isNotEmpty) SizedBox(width: 8.w),
              FlipCountdown(
                seconds: LotteryPeriodHelper.bettingCountdownSeconds(game, now),
                compact: compactCountdown,
                digitColor: AppColors.danger,
              ),
            ],
          ),
        ),
    };
  }
}
