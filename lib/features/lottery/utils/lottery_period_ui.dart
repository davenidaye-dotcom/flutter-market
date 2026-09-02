import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../config/theme/app_colors.dart';
import '../../../data/models/lottery_game_model.dart';
import '../../../shared/widgets/flip_countdown.dart';

/// 与后端 PlayCatalog.SEAL_WARN_SECONDS / 期态 tick 对齐。
/// 服务端 countdownSeconds = 距开奖（openAt），封盘线 = 最后 10 秒。
class LotteryPeriodRules {
  static const sealWarnSeconds = 10;
}

enum LotteryDisplayPhase { betting, sealed, drawing }

abstract final class LotteryPeriodHelper {
  static LotteryDisplayPhase phaseOf(LotteryGameModel game) {
    if (game.isDrawing || game.status == LotteryStatus.drawing) {
      return LotteryDisplayPhase.drawing;
    }
    if (game.countdownSeconds <= 0) {
      // 露出结束到下一帧 WS 之间 CD 可能仍为 0，不应一直「开奖中」
      return LotteryDisplayPhase.sealed;
    }
    if (game.status == LotteryStatus.sealed ||
        game.countdownSeconds <= LotteryPeriodRules.sealWarnSeconds) {
      return LotteryDisplayPhase.sealed;
    }
    return LotteryDisplayPhase.betting;
  }

  /// 下注中显示「距封盘」秒数（= 距开奖 - 10）
  static int bettingCountdownSeconds(LotteryGameModel game) {
    return (game.countdownSeconds - LotteryPeriodRules.sealWarnSeconds)
        .clamp(0, 99999);
  }

  static bool showDrawingPlaceholders(LotteryGameModel game) {
    return phaseOf(game) == LotteryDisplayPhase.drawing &&
        game.previousResults.isEmpty;
  }

  static bool canBetNow(LotteryGameModel game) {
    return phaseOf(game) == LotteryDisplayPhase.betting;
  }

  static LotteryStatus statusFromCountdown(int seconds, {bool hasResult = true}) {
    if (seconds <= 0) return LotteryStatus.drawing;
    if (seconds <= LotteryPeriodRules.sealWarnSeconds) {
      return LotteryStatus.sealed;
    }
    return LotteryStatus.open;
  }
}

/// 期态条：下注(距封盘) → 封盘中 → 开奖中
class LotteryPeriodCountdownRow extends StatelessWidget {
  const LotteryPeriodCountdownRow({
    super.key,
    required this.game,
    this.issuePrefix,
    this.showIssue = true,
    this.compactCountdown = false,
    this.issueStyle,
    this.labelStyle,
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
  final TextStyle? labelStyle;
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
    final phase = LotteryPeriodHelper.phaseOf(game);
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
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (issue.isNotEmpty) Text(issue, style: issueTextStyle),
              Text(
                '封盘中',
                style: sealedStyle ?? phaseLabel,
              ),
              SizedBox(width: 8.w),
              FlipCountdown(
                seconds: game.countdownSeconds,
                compact: compactCountdown,
              ),
            ],
          ),
        ),
      LotteryDisplayPhase.betting => _phaseRow(
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                issue.isEmpty ? '距封盘' : '$issue 距封盘',
                style: labelStyle ?? issueTextStyle,
              ),
              SizedBox(width: 8.w),
              FlipCountdown(
                seconds: LotteryPeriodHelper.bettingCountdownSeconds(game),
                compact: compactCountdown,
              ),
            ],
          ),
        ),
    };
  }
}
