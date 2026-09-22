import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../config/theme/app_colors.dart';
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
  static double hPad() => 10.w;
  /// 4 位期号居中，和「期数」同一列。
  static double issueW() => 52.w;
  static double issueGap() => 4.w;
  static double gyW() => 48.w;
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

  /// 历史表开奖球内数字相对球径
  static double ballFontScale() => 0.72;
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

/// 历史开奖展开面板 — 固定高度，与注单/长龙一致，可滚动
class HistoryDrawPanel extends StatelessWidget {
  const HistoryDrawPanel({
    super.key,
    required this.rows,
    this.loading = false,
    this.error = false,
    this.onRetry,
  });

  static const int maxRows = 10;
  static double panelHeight(BuildContext context) => 260.h;

  final List<HistoryDrawRow> rows;
  final bool loading;
  final bool error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final displayRows = rows.take(maxRows).toList();
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
            Expanded(child: _buildBody(displayRows, pad)),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(List<HistoryDrawRow> displayRows, double pad) {
    if (loading && displayRows.isEmpty) {
      return const Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
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
    if (displayRows.isEmpty) {
      return Center(
        child: Text(
          '暂无开奖记录',
          style: TextStyle(fontSize: 12.sp, color: AppColors.textHint),
        ),
      );
    }
    return ListView.separated(
      padding: EdgeInsets.fromLTRB(pad, 2.h, pad, 8.h),
      itemCount: displayRows.length,
      separatorBuilder: (_, _) => SizedBox(height: 2.h),
      itemBuilder: (_, i) => _DataRow(row: displayRows[i]),
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
      height: 32.h,
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
      height: 36.h,
      child: Pk10AlignRow(
        issue: Text(
          _issueTail(row.issue),
          style: HistoryDrawLayout.issueStyle(),
          textAlign: TextAlign.center,
          maxLines: 1,
        ),
        middle: LotteryBallRow(
          numbers: row.numbers,
          ballSize: HistoryDrawLayout.ballSize(),
          expandSlots: true,
          fontScale: HistoryDrawLayout.ballFontScale(),
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
