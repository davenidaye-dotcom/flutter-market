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
/// 设计宽 375：期号列 39、球间距 1、方块 22.6。边长 = min(格宽 − 球间距, 22.6.w)。
/// 期号列从 48 收到 39，让出的 9px 给球间距；首球离格边半个间距，用 [ballNudge] 补回贴近。
abstract final class HistoryDrawLayout {
  static double hPad() => 4.w;
  /// 左侧再少 3 逻辑像素。4.w 小于 4 时贴边，避免负 padding。
  static double leftPad() {
    final p = hPad() - 4;
    return p < 0 ? 0 : p;
  }
  /// 后 4 位期号 13sp 约 30px，39 仍完整显示（34 以下会出现 ellipsis）。
  static double issueW() => 39.w;
  static double issueGap() => 0;
  static double gyW() => 42.w;
  static double dtW() => 54.w;
  static double trailingW() => gyW() + dtW();
  static double ballSize() => 22.6.w;
  /// 方块行左移量：1 + 半个球间距，首球与期号的距离和无间距时一致。
  static double ballNudge() => 1 + ballGap() / 2;

  static TextStyle issueStyle() => TextStyle(
        fontSize: 13.sp,
        height: 1.1,
        color: const Color(0xFF5A5A5A),
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
          child: Center(child: issue),
        ),
        SizedBox(width: HistoryDrawLayout.issueGap()),
        Expanded(
          child: Transform.translate(
            offset: Offset(-HistoryDrawLayout.ballNudge(), 0),
            child: middle,
          ),
        ),
        SizedBox(
          width: HistoryDrawLayout.gyW(),
          child: Center(child: gy),
        ),
        SizedBox(
          width: HistoryDrawLayout.dtW(),
          child: Center(child: dt),
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

  static const _cn = ['一', '二', '三', '四', '五', '六', '七', '八', '九', '十'];

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
          style: HistoryDrawLayout.headerStyle(),
          textAlign: TextAlign.center,
        ),
        middle: Row(
          children: [
            for (final label in _cn)
              Expanded(
                child: Center(
                  child: Text(label, style: HistoryDrawLayout.headerStyle()),
                ),
              ),
          ],
        ),
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
    final sum = row.numbers.length >= 2 ? row.numbers[0] + row.numbers[1] : 0;
    final size = sum >= 12 ? '大' : '小';
    final oddEven = sum % 2 == 0 ? '双' : '单';
    final dt = row.numbers.length >= 10
        ? List.generate(5, (i) {
            final a = row.numbers[i];
            final b = row.numbers[9 - i];
            return a > b ? '龙' : '虎';
          }).join()
        : '';

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
          expandSlots: true,
          ballSize: HistoryDrawLayout.ballSize(),
          gap: HistoryDrawLayout.ballGap(),
          digitFontSize: HistoryDrawLayout.ballDigitSize(),
          fontScale: HistoryDrawLayout.ballFontScale(),
        ),
        gy: Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: '$sum'.padLeft(2, '0'),
                style: TextStyle(
                  fontSize: 11.sp,
                  height: 1.1,
                  color: const Color(0xFF5A5A5A),
                  fontWeight: FontWeight.w600,
                ),
              ),
              _coloredChars('$size$oddEven', fontSize: 11.sp),
            ],
          ),
          textAlign: TextAlign.center,
          maxLines: 1,
        ),
        dt: Text.rich(
          _coloredChars(dt, fontSize: 9.sp, weight: FontWeight.w500),
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}
