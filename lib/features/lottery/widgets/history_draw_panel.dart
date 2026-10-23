import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:easy_refresh/easy_refresh.dart';
import '../../../config/theme/app_colors.dart';
import '../../../shared/widgets/app_page_loading.dart';
import '../../../shared/widgets/app_pull_refresh.dart';
import '../../../shared/widgets/lottery_ball.dart';

class HistoryDrawRow {
  const HistoryDrawRow({
    required this.issue,
    required this.numbers,
    required this.summary,
  });

  final String issue;
  final List<int> numbers;
  final String summary;
}

/// 顶栏期号、开奖球、历史表头、下拉数据行共用同一套列宽。
/// 期号右对齐，离首块 3px。方块保持 22.6，首块贴轨道左、末块贴轨道右，往冠亚和挤。
/// 末块到冠亚和、冠亚和到龙虎用同一段 [tailGap]；冠亚和文字居中，龙虎文字左对齐，
/// 这样两侧露出的空隙一样宽。
abstract final class HistoryDrawLayout {
  static double hPad() => 4.w;
  /// 左侧再少 3 逻辑像素。4.w 小于 4 时贴边，避免负 padding。
  static double leftPad() {
    final p = hPad() - 4;
    return p < 0 ? 0 : p;
  }
  /// 后 4 位细体期号约 22px，28 右对齐后仍完整显示。
  static double issueW() => 28.w;
  /// 期号字形右缘到首块左缘。
  static double issueGap() => 3;
  static double gyW() => 42.w;
  static double dtW() => 52.w;
  /// 末块 | 冠亚和 | 龙虎 两段间隔。
  static double tailGap() => 3;
  static double trailingW() => tailGap() + gyW() + tailGap() + dtW();
  static double ballSize() => 22.6.w;

  static TextStyle issueStyle() => TextStyle(
        fontSize: 10.sp,
        height: 1.1,
        color: const Color(0xFF5A5A5A),
        fontWeight: FontWeight.w300,
      );

  /// 表头「期数」跟期号列一起收，避免 13sp 两字在 28 宽里换行。
  static TextStyle issueHeaderStyle() => TextStyle(
        fontSize: 10.sp,
        height: 1.1,
        color: const Color(0xFF7A7A7A),
        fontWeight: FontWeight.w600,
      );

  static TextStyle headerStyle() => TextStyle(
        fontSize: 13.sp,
        height: 1.1,
        color: const Color(0xFF7A7A7A),
        fontWeight: FontWeight.w600,
      );

  static double ballFontScale() => 0.55;

  static double ballDigitSize() => ballSize() * ballFontScale();

  static double ballGap() => 1;

  static double ballRadius() => LotteryBallStyle.radius();

  @Deprecated('Use ballGap; boost removed to keep spacing')
  static double ballBoxBoost() => 0;

  static const int visibleRows = 11;
  /// 行高贴球径；行间距固定 1 逻辑像素
  static double rowHeight() => ballSize();
  static double rowGap() => 1;
  static double headerHeight() => rowHeight();
  static double listPadTop() => 1;
  static double listPadBottom() => 1;
}

/// 期号 | 十个等宽槽 | 冠亚和 | 1-5龙虎。
class Pk10AlignRow extends StatelessWidget {
  const Pk10AlignRow({
    super.key,
    required this.issue,
    required this.middle,
    required this.gy,
    required this.dt,
  });

  final Widget issue;
  final Widget middle;
  final Widget gy;
  final Widget dt;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: HistoryDrawLayout.issueW(),
          child: Align(alignment: Alignment.centerRight, child: issue),
        ),
        SizedBox(width: HistoryDrawLayout.issueGap()),
        Expanded(child: middle),
        SizedBox(width: HistoryDrawLayout.tailGap()),
        SizedBox(
          width: HistoryDrawLayout.gyW(),
          child: Center(child: gy),
        ),
        SizedBox(width: HistoryDrawLayout.tailGap()),
        SizedBox(
          width: HistoryDrawLayout.dtW(),
          child: Align(alignment: Alignment.centerLeft, child: dt),
        ),
      ],
    );
  }
}

/// 历史开奖展开面板 — 固定高度，下拉刷新 / 上拉加载更多
class HistoryDrawPanel extends StatelessWidget {
  const HistoryDrawPanel({
    super.key,
    required this.rows,
    this.loading = false,
    this.error = false,
    this.onRetry,
    this.onRefresh,
    this.onLoadMore,
    this.refreshController,
  });

  static const int pageSize = 20;
  static const int maxCachedRows = 300;
  @Deprecated('Use pageSize')
  static const int maxRows = pageSize;

  static double panelHeight(BuildContext context) {
    final rows = HistoryDrawLayout.visibleRows;
    return HistoryDrawLayout.headerHeight() +
        HistoryDrawLayout.listPadTop() +
        HistoryDrawLayout.listPadBottom() +
        rows * HistoryDrawLayout.rowHeight() +
        (rows - 1) * HistoryDrawLayout.rowGap();
  }

  final List<HistoryDrawRow> rows;
  final bool loading;
  final bool error;
  final VoidCallback? onRetry;
  final Future<void> Function()? onRefresh;
  final Future<bool> Function()? onLoadMore;
  final EasyRefreshController? refreshController;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      child: Container(
        height: panelHeight(context),
        decoration: const BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Color(0x24000000),
              blurRadius: 8,
              offset: Offset(0, 4),
            ),
          ],
        ),
        clipBehavior: Clip.hardEdge,
        child: Column(
          children: [
            const _Header(),
            Expanded(child: _buildBody(rows)),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(List<HistoryDrawRow> displayRows) {
    if (loading && displayRows.isEmpty) {
      return const AppPageLoading();
    }
    if (error) {
      return GestureDetector(
        onTap: onRetry,
        child: Center(
          child: Text(
            '加载失败，点击重试',
            style: TextStyle(fontSize: 12.sp, color: AppColors.danger),
          ),
        ),
      );
    }

    final list = displayRows.isEmpty
        ? ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              SizedBox(height: 80.h),
              Center(
                child: Text(
                  '暂无开奖记录',
                  style: TextStyle(fontSize: 12.sp, color: AppColors.textHint),
                ),
              ),
            ],
          )
        : ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(
              HistoryDrawLayout.leftPad(),
              HistoryDrawLayout.listPadTop(),
              HistoryDrawLayout.hPad(),
              HistoryDrawLayout.listPadBottom(),
            ),
            itemCount: displayRows.length,
            separatorBuilder: (_, _) =>
                SizedBox(height: HistoryDrawLayout.rowGap()),
            itemBuilder: (_, i) => _DataRow(row: displayRows[i]),
          );

    if (onRefresh == null && onLoadMore == null) {
      return list;
    }
    return AppPullRefresh(
      controller: refreshController,
      onRefresh: onRefresh ?? () async {},
      onLoad: onLoadMore,
      child: list,
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: HistoryDrawLayout.headerHeight(),
      padding: EdgeInsets.fromLTRB(
        HistoryDrawLayout.leftPad(),
        0,
        HistoryDrawLayout.hPad(),
        0,
      ),
      color: const Color(0xFFF5F5F5),
      child: Pk10AlignRow(
        issue: Text(
          '期数',
          style: HistoryDrawLayout.issueHeaderStyle(),
          textAlign: TextAlign.center,
        ),
        middle: const _RankHeads(),
        gy: Text(
          '冠亚和',
          style: HistoryDrawLayout.headerStyle(),
          textAlign: TextAlign.center,
          maxLines: 1,
        ),
        dt: Text(
          '1-5龙虎',
          style: HistoryDrawLayout.headerStyle(),
          textAlign: TextAlign.center,
          maxLines: 1,
        ),
      ),
    );
  }
}

/// 名次字与方块同一条轨道：字心落在对应方块中心。
class _RankHeads extends StatelessWidget {
  const _RankHeads();

  static const _cn = ['一', '二', '三', '四', '五', '六', '七', '八', '九', '十'];

  @override
  Widget build(BuildContext context) {
    final size = HistoryDrawLayout.ballSize();
    final style = HistoryDrawLayout.headerStyle();
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final ball = w > 0 && size * 10 > w ? w / 10 : size;
        final gap = w > ball * 10 ? (w - ball * 10) / 9 : 0.0;
        return Stack(
          fit: StackFit.expand,
          children: [
            for (var i = 0; i < _cn.length; i++)
              Positioned(
                left: i * (ball + gap),
                width: ball,
                top: 0,
                bottom: 0,
                child: Center(
                  child: Text(_cn[i], style: style, maxLines: 1),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _DataRow extends StatelessWidget {
  const _DataRow({required this.row});

  final HistoryDrawRow row;

  static const _yinBlue = Color(0xFF1E88E5);

  static String _issueTail(String issue) {
    if (issue.length <= 4) return issue;
    return issue.substring(issue.length - 4);
  }

  static Color _sideColor(String ch) {
    if (ch == '大' || ch == '双' || ch == '龙') return AppColors.danger;
    if (ch == '小' || ch == '单' || ch == '虎') return _yinBlue;
    return const Color(0xFF5A5A5A);
  }

  static TextSpan _coloredChars(String text, {double? fontSize, FontWeight? weight}) {
    return TextSpan(
      children: [
        for (final rune in text.runes)
          TextSpan(
            text: String.fromCharCode(rune),
            style: TextStyle(
              fontSize: fontSize,
              height: 1.1,
              color: _sideColor(String.fromCharCode(rune)),
              fontWeight: weight ?? FontWeight.w600,
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final pending = row.numbers.length < 2;
    final sum = pending ? 0 : row.numbers[0] + row.numbers[1];
    final size = sum >= 12 ? '大' : '小';
    final oddEven = sum % 2 == 0 ? '双' : '单';
    final dt = !pending && row.numbers.length >= 10
        ? List.generate(5, (i) {
            final a = row.numbers[i];
            final b = row.numbers[9 - i];
            return a > b ? '龙' : '虎';
          }).join()
        : '';
    final dashStyle = TextStyle(
      fontSize: 11.sp,
      height: 1.1,
      color: const Color(0xFF5A5A5A),
      fontWeight: FontWeight.w600,
    );

    return SizedBox(
      height: HistoryDrawLayout.rowHeight(),
      child: Pk10AlignRow(
        issue: Text(
          _issueTail(row.issue),
          style: HistoryDrawLayout.issueStyle(),
          textAlign: TextAlign.center,
          maxLines: 1,
        ),
        middle: LotteryBallRow(
          numbers: row.numbers,
          pinEdges: true,
          placeholder: pending,
          ballSize: HistoryDrawLayout.ballSize(),
          gap: HistoryDrawLayout.ballGap(),
          digitFontSize: HistoryDrawLayout.ballDigitSize(),
          fontScale: HistoryDrawLayout.ballFontScale(),
        ),
        gy: pending
            ? Text('—', style: dashStyle, textAlign: TextAlign.center, maxLines: 1)
            : Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: '$sum'.padLeft(2, '0'),
                      style: dashStyle,
                    ),
                    _coloredChars('$size$oddEven', fontSize: 11.sp),
                  ],
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
              ),
        dt: pending
            ? Text('—', style: dashStyle, textAlign: TextAlign.center, maxLines: 1)
            : Text.rich(
                _coloredChars(dt, fontSize: 9.sp, weight: FontWeight.w500),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
      ),
    );
  }
}
