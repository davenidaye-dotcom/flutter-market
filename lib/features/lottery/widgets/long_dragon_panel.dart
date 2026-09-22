import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// 长龙悬浮面板 — 叠在聊天区上方
class LongDragonPanel extends StatelessWidget {
  const LongDragonPanel({super.key, this.rows = const []});

  static const int maxRows = 20;
  static double panelHeight(BuildContext context) => 260.h;

  final List<LongDragonRow> rows;

  static const _headerColor = Color(0xFF555555);
  static const _emptyColor = Color(0xFF7A7A7A);

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
            Container(
              height: 34.h,
              padding: EdgeInsets.symmetric(horizontal: 12.w),
              color: const Color(0xFFF5F5F5),
              child: Row(
                children: [
                  _h('序列', flex: 2),
                  _h('位置', flex: 3),
                  _h('结果', flex: 2),
                  _h('连期', flex: 2),
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
                                _c(row.position, flex: 3),
                                _c(row.result, flex: 2, color: row.resultColor),
                                _c('${row.streak}期', flex: 2),
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

  Widget _c(String text, {required int flex, Color? color}) {
    return Expanded(
      flex: flex,
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 12.sp, color: color ?? const Color(0xFF333333)),
      ),
    );
  }
}

class LongDragonRow {
  const LongDragonRow({
    required this.position,
    required this.result,
    required this.streak,
    this.resultColor,
  });

  final String position;
  final String result;
  final int streak;
  final Color? resultColor;
}

const mockLongDragonRows = [
  LongDragonRow(position: '冠军', result: '大', streak: 5, resultColor: Color(0xFFE53935)),
  LongDragonRow(position: '冠军', result: '单', streak: 4, resultColor: Color(0xFFE53935)),
  LongDragonRow(position: '亚军', result: '小', streak: 3, resultColor: Color(0xFF1E88E5)),
  LongDragonRow(position: '冠亚和', result: '双', streak: 6, resultColor: Color(0xFFE53935)),
  LongDragonRow(position: '冠军龙虎', result: '龙', streak: 3, resultColor: Color(0xFFE53935)),
];
