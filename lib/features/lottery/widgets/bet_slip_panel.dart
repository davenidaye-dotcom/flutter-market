import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// 注单悬浮面板 — 叠在聊天区上方
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
                  _h('金额', flex: 2),
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
                                _c(row.amount, flex: 2),
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
                                              ? const Color(0xFF1E88E5)
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

  Widget _h(String text, {required int flex}) {
    return Expanded(
      flex: flex,
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 13.sp, color: _headerColor, fontWeight: FontWeight.w500),
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
    this.orderId,
    this.action = '取消',
    this.canCancel = true,
  });

  final String issue;
  final String amount;
  final String? orderId;
  final String action;
  final bool canCancel;
}
