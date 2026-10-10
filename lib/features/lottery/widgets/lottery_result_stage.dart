import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../config/theme/app_colors.dart';
import '../../../shared/widgets/lottery_ball.dart';

/// 开奖卡暗色渐变。
abstract final class LotteryResultTheme {
  static const gradientTop = Color(0xFF1B2740);
  static const gradientBottom = Color(0xFF0E1524);
  static const LinearGradient shellGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [gradientTop, gradientBottom],
  );

  static const assetBg = 'assets/lottery/draw_podium/bg.png';
  static const assetBadgeGold = 'assets/lottery/draw_podium/badge_gold.png';
  static const assetBadgeSilver = 'assets/lottery/draw_podium/badge_silver.png';
  static const assetBadgeBronze = 'assets/lottery/draw_podium/badge_bronze.png';

  static String carSide(int number) =>
      'assets/lottery/draw_podium/car_side_$number.png';

  static String carFront(int number) =>
      'assets/lottery/draw_podium/car_front_$number.png';
}

/// 暗色壳。
class LotteryResultShell extends StatelessWidget {
  const LotteryResultShell({
    super.key,
    required this.child,
    this.borderRadius,
    this.width = double.infinity,
  });

  final Widget child;
  final BorderRadius? borderRadius;
  final double? width;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        gradient: LotteryResultTheme.shellGradient,
      ),
      child: child,
    );
  }
}

/// 顶行：标题 + 10 球。
class LotteryResultBallsHeader extends StatelessWidget {
  const LotteryResultBallsHeader({
    super.key,
    required this.title,
    required this.numbers,
    this.trailing,
    this.titleStyle,
    this.ballHeight,
    this.digitFontSize,
    this.gap,
    this.padding,
  });

  final String title;
  final List<int> numbers;
  final Widget? trailing;
  final TextStyle? titleStyle;
  final double? ballHeight;
  final double? digitFontSize;
  final double? gap;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final h = ballHeight ?? 20.h;
    final dig = digitFontSize ?? 10.sp;
    final g = gap ?? 2.w;
    return Padding(
      padding: padding ?? EdgeInsets.fromLTRB(10.w, 10.h, 10.w, 6.h),
      child: Row(
        children: [
          Text(
            title,
            style: titleStyle ??
                TextStyle(
                  color: Colors.white,
                  fontSize: 13.sp,
                  fontWeight: FontWeight.w700,
                ),
          ),
          SizedBox(width: 8.w),
          if (numbers.isNotEmpty)
            Expanded(
              child: SizedBox(
                height: h,
                child: LotteryBallRow(
                  numbers: numbers,
                  expandSlots: true,
                  gap: g,
                  digitFontSize: dig,
                  palette: AppColors.resultBallColors,
                ),
              ),
            )
          else
            const Spacer(),
          if (trailing != null) ...[
            SizedBox(width: 6.w),
            trailing!,
          ],
        ],
      ),
    );
  }
}

String lotteryGyLabel(List<int> ranks) {
  if (ranks.length < 2) return '';
  final gy = ranks[0] + ranks[1];
  return '冠亚和 $gy ${gy >= 12 ? '大' : '小'} ${gy.isOdd ? '单' : '双'}';
}

String lotteryGyBody(List<int> ranks) {
  if (ranks.length < 2) return '';
  final gy = ranks[0] + ranks[1];
  return '$gy ${gy >= 12 ? '大' : '小'} ${gy.isOdd ? '单' : '双'}';
}

/// 1-5 名 vs 10-6 名龙虎串（含前缀）。
String lotteryDragonTigerLine(List<int> ranks) {
  final body = lotteryDragonTigerBody(ranks);
  return body.isEmpty ? '' : '1-5龙虎 $body';
}

String lotteryDragonTigerBody(List<int> ranks) {
  if (ranks.length < 10) return '';
  final buf = StringBuffer();
  for (var i = 0; i < 5; i++) {
    if (i > 0) buf.write(' ');
    buf.write(ranks[i] > ranks[9 - i] ? '龙' : '虎');
  }
  return buf.toString();
}

/// 图3 三列脚注：期号 / 冠亚和 / 1-5龙虎。
class LotteryResultFooterColumns extends StatelessWidget {
  const LotteryResultFooterColumns({
    super.key,
    required this.issueText,
    required this.gyBody,
    required this.dtBody,
  });

  final String issueText;
  final String gyBody;
  final String dtBody;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black.withValues(alpha: 0.72),
      padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 8.h),
      child: Row(
        children: [
          Expanded(child: _col('期号', issueText, CrossAxisAlignment.start)),
          Expanded(child: _col('冠亚和', gyBody.isEmpty ? '—' : gyBody, CrossAxisAlignment.center)),
          Expanded(child: _col('1-5龙虎', dtBody.isEmpty ? '—' : dtBody, CrossAxisAlignment.end)),
        ],
      ),
    );
  }

  Widget _col(String label, String value, CrossAxisAlignment align) {
    return Column(
      crossAxisAlignment: align,
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.white54,
            fontSize: 9.sp,
            fontWeight: FontWeight.w500,
          ),
        ),
        SizedBox(height: 2.h),
        Text(
          value,
          style: TextStyle(
            color: Colors.white,
            fontSize: 10.sp,
            fontWeight: FontWeight.w600,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: switch (align) {
            CrossAxisAlignment.start => TextAlign.left,
            CrossAxisAlignment.end => TextAlign.right,
            _ => TextAlign.center,
          },
        ),
      ],
    );
  }
}

/// 聊天开奖卡领奖台。左亚军、中冠军、右季军。车身按球色分文件，号码画在白板上。
class LotteryDrawPodiumScene extends StatelessWidget {
  const LotteryDrawPodiumScene({super.key, required this.numbers});

  /// 前三名车号：冠军、亚军、季军。
  final List<int> numbers;

  @override
  Widget build(BuildContext context) {
    final first = numbers.isNotEmpty ? numbers[0] : 0;
    final second = numbers.length > 1 ? numbers[1] : 0;
    final third = numbers.length > 2 ? numbers[2] : 0;
    return SizedBox(
      height: 140.h,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: Image.asset(
              LotteryResultTheme.assetBg,
              fit: BoxFit.cover,
              alignment: Alignment.bottomCenter,
              errorBuilder: (_, _, _) => const ColoredBox(color: Color(0xFF0E1524)),
            ),
          ),
          Positioned(
            left: 2.w,
            right: 2.w,
            bottom: 0,
            height: 90.h,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: _RankedCar(
                    asset: LotteryResultTheme.carSide(second),
                    number: second,
                    aspect: 756 / 217,
                    fx: 0.432,
                    fy: 0.624,
                    numW: 0.16,
                    numH: 0.30,
                  ),
                ),
                Expanded(
                  child: _RankedCar(
                    asset: LotteryResultTheme.carFront(first),
                    number: first,
                    aspect: 474 / 277,
                    fx: 0.504,
                    fy: 0.694,
                    numW: 0.24,
                    numH: 0.13,
                  ),
                ),
                Expanded(
                  child: _RankedCar(
                    asset: LotteryResultTheme.carSide(third),
                    number: third,
                    aspect: 756 / 217,
                    fx: 0.432,
                    fy: 0.624,
                    numW: 0.16,
                    numH: 0.30,
                    flip: true,
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            left: 2.w,
            right: 2.w,
            top: 0,
            height: 52.h,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: _RankBadge(
                    asset: LotteryResultTheme.assetBadgeSilver,
                    number: second,
                    height: 42.h,
                  ),
                ),
                Expanded(
                  child: _RankBadge(
                    asset: LotteryResultTheme.assetBadgeGold,
                    number: first,
                    height: 52.h,
                  ),
                ),
                Expanded(
                  child: _RankBadge(
                    asset: LotteryResultTheme.assetBadgeBronze,
                    number: third,
                    height: 42.h,
                    title: '季军',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RankBadge extends StatelessWidget {
  const _RankBadge({
    required this.asset,
    required this.number,
    required this.height,
    this.title,
  });

  final String asset;
  final int number;
  final double height;
  final String? title;

  @override
  Widget build(BuildContext context) {
    if (number <= 0) return SizedBox(height: height);
    return Align(
      alignment: Alignment.bottomCenter,
      child: SizedBox(
        height: height,
        child: AspectRatio(
          aspectRatio: 560 / 590,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.asset(asset, fit: BoxFit.fill),
              if (title != null)
                Align(
                  alignment: const Alignment(0, -0.78),
                  child: FractionallySizedBox(
                    widthFactor: 0.56,
                    heightFactor: 0.22,
                    child: FittedBox(
                      fit: BoxFit.contain,
                      child: Text(
                        title!,
                        style: const TextStyle(
                          color: Color(0xFFF3D2AE),
                          fontSize: 40,
                          fontWeight: FontWeight.w900,
                          height: 1,
                          shadows: [
                            Shadow(color: Color(0xCC000000), blurRadius: 2),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              Align(
                alignment: const Alignment(0, 0.16),
                child: FractionallySizedBox(
                  widthFactor: 0.34,
                  heightFactor: 0.20,
                  child: FittedBox(
                    fit: BoxFit.contain,
                    child: Text(
                      '$number',
                      style: const TextStyle(
                        color: Color(0xFF1A1A1A),
                        fontSize: 40,
                        fontWeight: FontWeight.w900,
                        height: 1,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RankedCar extends StatelessWidget {
  const _RankedCar({
    required this.asset,
    required this.number,
    required this.aspect,
    required this.fx,
    required this.fy,
    required this.numW,
    required this.numH,
    this.flip = false,
  });

  final String asset;
  final int number;
  final double aspect;
  final double fx;
  final double fy;
  final double numW;
  final double numH;
  final bool flip;

  @override
  Widget build(BuildContext context) {
    if (number < 1 || number > 10) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        final boxW = constraints.maxWidth;
        final boxH = constraints.maxHeight;
        if (boxW <= 0 || boxH <= 0) return const SizedBox.shrink();
        var iw = boxW;
        var ih = iw / aspect;
        if (ih > boxH) {
          ih = boxH;
          iw = ih * aspect;
        }
        final ox = (boxW - iw) / 2;
        final oy = boxH - ih;
        final nx = flip ? 1 - fx : fx;
        final numW = iw * this.numW;
        final numH = ih * this.numH;
        return Stack(
          children: [
            Positioned(
              left: ox,
              top: oy,
              width: iw,
              height: ih,
              child: Transform.flip(
                flipX: flip,
                child: Image.asset(asset, fit: BoxFit.fill),
              ),
            ),
            Positioned(
              left: ox + iw * nx - numW / 2,
              top: oy + ih * fy - numH / 2,
              width: numW,
              height: numH,
              child: FittedBox(
                fit: BoxFit.contain,
                child: Text(
                  '$number',
                  style: const TextStyle(
                    color: Color(0xFF1A1A1A),
                    fontSize: 32,
                    fontWeight: FontWeight.w900,
                    height: 1,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
