import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../config/theme/app_colors.dart';
import '../../../data/repositories/providers.dart';
import '../../../shared/format/display_number.dart';
import '../../../shared/format/play_label.dart';
import '../../../shared/widgets/emulator_safe_dialog.dart';

/// 注单悬浮面板 — 叠在聊天区上方
/// 金额列只显示总金额；点击弹出详情看投注内容。
class BetSlipPanel extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
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
                                      onTap: () => _showDetail(context, ref, row),
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

  Future<void> _showDetail(BuildContext context, WidgetRef ref, BetSlipRow row) async {
    final detail = row.detail.trim().isNotEmpty ? row.detail.trim() : row.amount;
    var lines = _parseDetailLines(detail, row.amount);
    var issue = row.issue.trim();
    var totalText = row.amount.trim().isNotEmpty
        ? row.amount.trim()
        : '${_sumAmounts(lines)}';

    final orderId = (row.orderId ?? '').trim();
    if (orderId.isNotEmpty) {
      try {
        final data = await ref.read(walletRepositoryProvider).getBetDetail(orderId);
        final fromApi = _linesFromOrderDetail(data);
        if (fromApi.isNotEmpty) {
          lines = fromApi;
          final apiIssue = '${data['issueNo'] ?? data['issue_no'] ?? ''}'.trim();
          if (apiIssue.isNotEmpty) issue = apiIssue;
          final apiTotal = data['totalAmount'] ?? data['total_amount'];
          if (apiTotal != null && '$apiTotal'.trim().isNotEmpty) {
            totalText = displayNumber(apiTotal);
          } else {
            totalText = '${_sumAmounts(lines)}';
          }
        }
      } catch (_) {
        // 保留本地解析结果
      }
    }

    if (!context.mounted) return;
    await showEmulatorSafeDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 24.h),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 360.w, maxHeight: 0.78.sh),
          child: Padding(
            padding: EdgeInsets.fromLTRB(14.w, 14.h, 14.w, 12.h),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '下注明细',
                  style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w700),
                ),
                if (issue.isNotEmpty) ...[
                  SizedBox(height: 4.h),
                  Text(
                    '期号 $issue',
                    style: TextStyle(fontSize: 12.sp, color: AppColors.textSecondary),
                  ),
                ],
                SizedBox(height: 10.h),
                _detailHeaderRow(),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: lines.length,
                    separatorBuilder: (_, __) =>
                        const Divider(height: 1, color: Color(0xFFEEEEEE)),
                    itemBuilder: (_, i) => _detailLineRow(lines[i]),
                  ),
                ),
                SizedBox(height: 8.h),
                Text(
                  '笔数 ${lines.length}　总金额 $totalText',
                  style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600),
                ),
                SizedBox(height: 12.h),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton(
                    onPressed: safeDialogPop(ctx),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.navBlue,
                      padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 10.h),
                    ),
                    child: const Text('知道了'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static List<_DetailLine> _linesFromOrderDetail(Map<String, dynamic> data) {
    final raw = data['items'];
    if (raw is! List || raw.isEmpty) return const [];
    final out = <_DetailLine>[];
    for (final e in raw) {
      if (e is! Map) continue;
      final m = Map<String, dynamic>.from(e);
      final code = '${m['playCode'] ?? m['play_code'] ?? ''}'.trim();
      final fallback =
          '${m['playName'] ?? m['play_name'] ?? m['playCode'] ?? m['play_code'] ?? ''}'.trim();
      final label = playDisplayLabel(code, fallbackName: fallback);
      if (label.isEmpty || label == '—') continue;
      final amount = m['amount'];
      final amountText = amount == null ? '—' : displayNumber(amount);
      final odds = m['odds'] ?? m['oddsSnapshot'] ?? m['odds_snapshot'];
      final oddsText = odds == null ? '—' : displayNumber(odds);
      out.add(_DetailLine(label: label, amount: amountText, oddsText: oddsText));
    }
    return out;
  }

  Widget _detailHeaderRow() {
    final style = TextStyle(
      fontSize: 12.sp,
      fontWeight: FontWeight.w600,
      color: AppColors.textSecondary,
    );
    return Container(
      color: const Color(0xFFF5F5F5),
      padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 8.h),
      child: Row(
        children: [
          Expanded(flex: 5, child: Text('号码', style: style)),
          Expanded(flex: 3, child: Text('赔率', style: style, textAlign: TextAlign.center)),
          Expanded(flex: 4, child: Text('金额', style: style, textAlign: TextAlign.center)),
        ],
      ),
    );
  }

  Widget _detailLineRow(_DetailLine line) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 8.h),
      child: Row(
        children: [
          Expanded(
            flex: 5,
            child: Text(line.label, style: TextStyle(fontSize: 13.sp)),
          ),
          Expanded(
            flex: 3,
            child: Text(
              line.oddsText,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13.sp),
            ),
          ),
          Expanded(
            flex: 4,
            child: Text(
              line.amount,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
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

  /// 解析详情文案为表格行（只展示；无赔率时显示 —）
  static List<_DetailLine> _parseDetailLines(String detail, String fallbackAmount) {
    final text = detail.trim();
    if (text.isEmpty) {
      return [_DetailLine(label: '—', amount: fallbackAmount)];
    }
    final out = <_DetailLine>[];

    // 冠军 [ 大/4 ]  /  第8名[ 2/55 4/55 ]
    final bracket = RegExp(r'([^\s\[]+.*?)\s*\[\s*([^\]]+)\s*\]');
    for (final m in bracket.allMatches(text)) {
      final prefix = m.group(1)!.trim();
      final inner = m.group(2)!.trim();
      for (final part in inner.split(RegExp(r'\s+'))) {
        final parsed = _splitSlashAmount(part);
        if (parsed == null) continue;
        final label = prefix.isEmpty ? parsed.$1 : '$prefix ${parsed.$1}';
        out.add(_DetailLine(label: label.trim(), amount: parsed.$2));
      }
    }
    if (out.isNotEmpty) return out;

    // 冠军/大/5  大/100  1/大/10（空格分隔多注）
    for (final token in text.split(RegExp(r'\s+'))) {
      final parsed = _splitSlashAmount(token);
      if (parsed == null) continue;
      out.add(_DetailLine(label: parsed.$1, amount: parsed.$2));
    }
    if (out.isNotEmpty) return out;

    // 大100 / 单50
    final shorthand = RegExp(r'([大小单双龙虎])([1-9]\d*(?:\.\d+)?)');
    for (final m in shorthand.allMatches(text)) {
      out.add(_DetailLine(label: m.group(1)!, amount: m.group(2)!));
    }
    if (out.isNotEmpty) return out;

    return [_DetailLine(label: text, amount: fallbackAmount)];
  }

  /// `大/4` / `冠军/大/5` → (号码, 金额)
  static (String, String)? _splitSlashAmount(String raw) {
    final t = raw.trim();
    if (t.isEmpty || !t.contains('/')) return null;
    final parts = t.split('/');
    if (parts.length < 2) return null;
    final amount = parts.last.trim();
    if (amount.isEmpty || num.tryParse(amount) == null) return null;
    final label = parts.sublist(0, parts.length - 1).join(' ').trim();
    if (label.isEmpty) return null;
    return (label, amount);
  }

  static int _sumAmounts(List<_DetailLine> lines) {
    var sum = 0;
    for (final l in lines) {
      sum += int.tryParse(l.amount.trim()) ?? 0;
    }
    return sum;
  }
}

class _DetailLine {
  const _DetailLine({
    required this.label,
    required this.amount,
    this.oddsText = '—',
  });

  final String label;
  final String amount;
  final String oddsText;
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
