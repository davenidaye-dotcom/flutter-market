import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../shared/widgets/emulator_safe_dialog.dart';

/// 注单悬浮面板 — 叠在聊天区上方
/// 金额列只显示总金额；点击弹出详情看投注内容。
class BetSlipPanel extends StatelessWidget {
  const BetSlipPanel({
    super.key,
    this.rows = const [],
    this.onCancelRow,
  });

  static const int maxRows = 20;
  static double panelHeight(BuildContext context) => 260.h;

  final List<BetSlipRow> rows;
  final ValueChanged<int>? onCancelRow;

  static const _headerColor = Color(0xFF555555);
  static const _emptyColor = Color(0xFF7A7A7A);
  static const _linkColor = Color(0xFF1E88E5);

  @override
  Widget build(BuildContext context) {
    final displayRows = rows.take(maxRows).toList();

    return Material(
      color: Colors.transparent,
      elevation: 0,
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
            Container(
              height: 34.h,
              padding: EdgeInsets.symmetric(horizontal: 12.w),
              color: const Color(0xFFF5F5F5),
              child: Row(
                children: [
                  _h('序列', flex: 2),
                  _h('期号', flex: 3),
                  _h('金额', flex: 3),
                  _h('操作', flex: 2),
                ],
              ),
            ),
            Expanded(
              child: displayRows.isEmpty
                  ? Center(
                      child: Text(
                        '暂无数据',
                        style: TextStyle(fontSize: 14.sp, color: _emptyColor),
                      ),
                    )
                  : ListView.separated(
                      padding: EdgeInsets.zero,
                      primary: false,
                      itemCount: displayRows.length,
                      separatorBuilder: (_, _) =>
                          const Divider(height: 1, color: Color(0xFFEEEEEE)),
                      itemBuilder: (_, i) {
                        final row = displayRows[i];
                        return SizedBox(
                          height: 40.h,
                          child: Padding(
                            padding: EdgeInsets.symmetric(horizontal: 12.w),
                            child: Row(
                              children: [
                                _c('${i + 1}', flex: 2),
                                _c(_issueTail(row.issue), flex: 3),
                                Expanded(
                                  flex: 3,
                                  child: Center(
                                    child: GestureDetector(
                                      onTap: () => _showDetail(context, row),
                                      behavior: HitTestBehavior.opaque,
                                      child: Text(
                                        row.amount,
                                        style: TextStyle(
                                          fontSize: 13.sp,
                                          fontWeight: FontWeight.w600,
                                          color: _linkColor,
                                          decoration: TextDecoration.underline,
                                          decorationColor: _linkColor,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                Expanded(
                                  flex: 2,
                                  child: Center(
                                    child: GestureDetector(
                                      onTap: row.canCancel && onCancelRow != null
                                          ? () => onCancelRow!(i)
                                          : null,
                                      behavior: HitTestBehavior.opaque,
                                      child: Text(
                                        row.action,
                                        style: TextStyle(
                                          fontSize: 12.sp,
                                          color: row.canCancel
                                              ? _linkColor
                                              : _emptyColor,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showDetail(BuildContext context, BetSlipRow row) async {
    final detail = row.detail.trim().isNotEmpty ? row.detail.trim() : row.amount;
    await showEmulatorSafeDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('注单详情'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _detailRow('期号', _issueTail(row.issue)),
            SizedBox(height: 8.h),
            _detailRow('总金额', row.amount),
            SizedBox(height: 8.h),
            Text(
              '投注内容',
              style: TextStyle(fontSize: 13.sp, color: Colors.black54),
            ),
            SizedBox(height: 4.h),
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: 220.h),
              child: SingleChildScrollView(
                child: Text(
                  detail,
                  style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w500),
                ),
              ),
            ),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: safeDialogPop(ctx),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 56.w,
          child: Text(
            label,
            style: TextStyle(fontSize: 13.sp, color: Colors.black54),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }

  Widget _h(String text, {required int flex}) {
    return Expanded(
      flex: flex,
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 13.sp,
          color: _headerColor,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _c(String text, {required int flex}) {
    return Expanded(
      flex: flex,
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 12.sp, color: const Color(0xFF333333)),
      ),
    );
  }

  static String _issueTail(String issue) {
    if (issue.length <= 4) return issue;
    return issue.substring(issue.length - 4);
  }
}

class BetSlipRow {
  const BetSlipRow({
    required this.issue,
    required this.amount,
    this.detail = '',
    this.orderId,
    this.action = '取消',
    this.canCancel = true,
  });

  final String issue;
  /// 总金额（列表展示，可点击）
  final String amount;
  /// 投注明细（详情弹窗）
  final String detail;
  final String? orderId;
  final String action;
  final bool canCancel;
}

/// 从核对文案 / 指令里解析总金额数字字符串。
String? betSlipTotalFromText(String text) {
  final t = text.trim();
  if (t.isEmpty) return null;
  final labeled = RegExp(r'总金额\s*[:：]?\s*([0-9]+(?:\.[0-9]+)?)').firstMatch(t);
  if (labeled != null) return labeled.group(1);

  final slashAmounts = RegExp(r'/([0-9]+(?:\.[0-9]+)?)')
      .allMatches(t)
      .map((m) => num.tryParse(m.group(1)!))
      .whereType<num>()
      .toList();
  if (slashAmounts.isNotEmpty) {
    final sum = slashAmounts.fold<num>(0, (a, b) => a + b);
    if (sum == sum.roundToDouble()) return '${sum.toInt()}';
    return '$sum';
  }

  // 大100 / 单50
  final shorthand = RegExp(r'[大小单双龙虎]([1-9]\d*(?:\.\d+)?)');
  final shortAmounts = shorthand
      .allMatches(t)
      .map((m) => num.tryParse(m.group(1)!))
      .whereType<num>()
      .toList();
  if (shortAmounts.isNotEmpty) {
    final sum = shortAmounts.fold<num>(0, (a, b) => a + b);
    if (sum == sum.roundToDouble()) return '${sum.toInt()}';
    return '$sum';
  }

  if (num.tryParse(t) != null) return t;
  return null;
}
