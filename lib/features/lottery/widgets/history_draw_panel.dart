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
abstract final class HistoryDrawLayout {
  static double hPad() => 8.w;
  /// 4 位期号居中，和「期数」同一列。
  static double issueW() => 40.w;
  static double issueGap() => 2.w;
  static double gyW() => 46.w;
  static double dtW() => 58.w;
  static double trailingW() => gyW() + dtW();
  static double ballSize() => 18.w;

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

  /// 历史表开奖球内数字相对原来 18 边长的比例。
  static double ballFontScale() => 0.72;

  /// 开奖数字的绝对字号。顶栏和历史表共用，方框变大后字不跟着变。
  static double ballDigitSize() => ballSize() * ballFontScale();

  static const int visibleRows = 10;
  static double rowHeight() => 24.h;
  static double rowGap() => 1.h;
  static double headerHeight() => 28.h;
  static double listPadTop() => 1.h;
  static double listPadBottom() => 1.h;
}

/// 期号 | 十个等宽槽 | 冠亚和 | 龙虎。顶栏和下拉必须用这一行，禁止各自算宽。
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
        Expanded(child: middle),
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

  /// 首屏默认拉取条数；面板固定露出 [HistoryDrawLayout.visibleRows] 期，其余靠上拉。
  static const int pageSize = 20;
  /// 内存上限，避免无限堆积。
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
  /// 返回 false 表示没有更多期数。
  final Future<bool> Function()? onLoadMore;
  final EasyRefreshController? refreshController;

  @override
  Widget build(BuildContext context) {
    final pad = HistoryDrawLayout.hPad();

    return Material(
      color: Colors.transparent,
      child: Container(
        height: panelHeight(context),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.14),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            const _Header(),
            Expanded(child: _buildBody(rows, pad)),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(List<HistoryDrawRow> displayRows, double pad) {
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
              pad,
              HistoryDrawLayout.listPadTop(),
              pad,
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
    final pad = HistoryDrawLayout.hPad();
    return Container(
      height: HistoryDrawLayout.headerHeight(),
      padding: EdgeInsets.symmetric(horizontal: pad),
      color: const Color(0xFFF5F5F5),
      child: Pk10AlignRow(
        issue: Text('期数', style: HistoryDrawLayout.headerStyle(), textAlign: TextAlign.center),
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
        gy: Text('冠亚和', style: HistoryDrawLayout.headerStyle(), textAlign: TextAlign.center),
        dt: Text('1-5龙虎', style: HistoryDrawLayout.headerStyle(), textAlign: TextAlign.center),
      ),
    );
  }
}

class _DataRow extends StatelessWidget {
  const _DataRow({required this.row});

  final HistoryDrawRow row;

  static const _dragonTiger = Color(0xFF7A7A7A);

  static String _issueTail(String issue) {
    if (issue.length <= 4) return issue;
    return issue.substring(issue.length - 4);
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
          digitFontSize: HistoryDrawLayout.ballDigitSize(),
        ),
        gy: Text(
          '$sum$size$oddEven',
          textAlign: TextAlign.center,
          maxLines: 1,
          style: TextStyle(
            fontSize: 11.sp,
            height: 1.1,
            color: AppColors.danger,
            fontWeight: FontWeight.w600,
          ),
        ),
        dt: Text(
          dt,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 11.sp,
            height: 1.1,
            color: _dragonTiger,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
