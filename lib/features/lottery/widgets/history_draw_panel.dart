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
            Expanded(
              child: _buildBody(displayRows),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(List<HistoryDrawRow> displayRows) {
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
      padding: EdgeInsets.fromLTRB(8.w, 2.h, 8.w, 8.h),
      itemCount: displayRows.length,
      separatorBuilder: (_, _) => SizedBox(height: 2.h),
      itemBuilder: (_, i) => _DataRow(row: displayRows[i]),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  static const _muted = Color(0xFF7A7A7A);

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 34.h,
      padding: EdgeInsets.symmetric(horizontal: 8.w),
      color: const Color(0xFFF5F5F5),
      child: Row(
        children: [
          SizedBox(
            width: 40.w,
            child: Text(
              '期数',
              style: TextStyle(fontSize: 11.sp, color: _muted, fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: List.generate(
                10,
                (i) => Text(
                  _cnNum(i + 1),
                  style: TextStyle(fontSize: 10.sp, color: _muted, fontWeight: FontWeight.w500),
                ),
              ),
            ),
          ),
          SizedBox(
            width: 52.w,
            child: Text(
              '冠亚和',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 10.sp, color: _muted, fontWeight: FontWeight.w500),
            ),
          ),
          SizedBox(
            width: 56.w,
            child: Text(
              '1-5龙虎',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 10.sp, color: _muted, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  String _cnNum(int n) {
    const map = ['一', '二', '三', '四', '五', '六', '七', '八', '九', '十'];
    return map[n - 1];
  }
}

class _DataRow extends StatelessWidget {
  const _DataRow({required this.row});

  final HistoryDrawRow row;

  static const _strong = Color(0xFF6B6B6B);
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
      height: 40.h,
      child: Row(
        children: [
          SizedBox(
            width: 40.w,
            child: Text(
              _issueTail(row.issue),
              style: TextStyle(fontSize: 11.sp, color: _strong, fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(
            child: LotteryBallRow(numbers: row.numbers, ballSize: 16.w),
          ),
          SizedBox(
            width: 52.w,
            child: Text(
              '$sum$size$oddEven',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 10.sp,
                color: AppColors.danger,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          SizedBox(
            width: 56.w,
            child: Text(
              dt,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 10.sp,
                color: _dragonTiger,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
