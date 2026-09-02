import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../config/theme/app_colors.dart';
import '../../../shared/widgets/lottery_ball.dart';

/// 列表行内紧凑开奖展示：小球 + 冠亚和（有则显示）。
class CompactDrawSnapshotRow extends StatelessWidget {
  const CompactDrawSnapshotRow({
    super.key,
    required this.ranks,
    this.sumGy,
    this.ballSize,
    this.showLabel = true,
  });

  final List<int> ranks;
  final int? sumGy;
  final double? ballSize;
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    if (ranks.isEmpty) return const SizedBox.shrink();
    final gy = sumGy ??
        (ranks.length >= 2 ? ranks[0] + ranks[1] : null);
    return Row(
      children: [
        if (showLabel) ...[
          Text(
            '开奖',
            style: TextStyle(fontSize: 10.sp, color: AppColors.textHint),
          ),
          SizedBox(width: 6.w),
        ],
        Expanded(
          child: LotteryBallRow(
            numbers: ranks,
            ballSize: ballSize ?? 14.w,
            gap: 2.w,
          ),
        ),
        if (gy != null) ...[
          SizedBox(width: 6.w),
          Text(
            '和$gy',
            style: TextStyle(
              fontSize: 10.sp,
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ],
    );
  }
}

/// 竞猜/账变列表项：主信息 + 可选开奖第二行。
class BetLedgerRecordTile extends StatelessWidget {
  const BetLedgerRecordTile({
    super.key,
    required this.topLine,
    this.drawRanks = const [],
    this.sumGy,
    this.trailing,
    this.subtitle,
    this.padding,
  });

  final Widget topLine;
  final List<int> drawRanks;
  final int? sumGy;
  final Widget? trailing;
  final Widget? subtitle;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding ?? EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: topLine),
              if (trailing != null) trailing!,
            ],
          ),
          if (subtitle != null) ...[
            SizedBox(height: 4.h),
            subtitle!,
          ],
          if (drawRanks.isNotEmpty) ...[
            SizedBox(height: 8.h),
            CompactDrawSnapshotRow(ranks: drawRanks, sumGy: sumGy),
          ],
        ],
      ),
    );
  }
}
