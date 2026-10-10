import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../config/theme/app_colors.dart';
import '../../../shared/format/display_number.dart';
import '../../../shared/widgets/emulator_safe_dialog.dart';

/// 确认弹框一行：号码 / 赔率 / 可改金额
class BetConfirmLine {
  BetConfirmLine({
    required this.playCode,
    required this.label,
    required this.oddsText,
    required num amount,
  }) : amountCtrl = TextEditingController(
          text: amount is int
              ? '$amount'
              : displayNumber(amount).replaceAll(RegExp(r'\.0+$'), ''),
        );

  final String playCode;
  final String label;
  final String oddsText;
  final TextEditingController amountCtrl;

  void dispose() => amountCtrl.dispose();
}

/// 用户点确定后带回的改后注单
class BetConfirmResult {
  const BetConfirmResult({
    required this.items,
    required this.command,
  });

  final List<Map<String, dynamic>> items;
  final String command;
}

/// 房主开启「下注确认」后的明细弹窗（对齐 Web：无确认列，金额可改）
Future<BetConfirmResult?> showBetConfirmDialog({
  required BuildContext context,
  required Future<List<BetConfirmLine>> Function() loadLines,
  String? issueNo,
}) async {
  return showEmulatorSafeDialog<BetConfirmResult>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _BetConfirmSheet(
      loadLines: loadLines,
      issueNo: issueNo,
    ),
  );
}

/// 自助回水：先核对业务日、流水、笔数、本次回水，确定后再领取。
Future<bool> showRebateClaimDialog({
  required BuildContext context,
  required String businessDate,
  required String turnover,
  required String count,
  required String amount,
  required bool canClaim,
}) async {
  final ok = await showEmulatorSafeDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      title: const Text('自助回水'),
      content: canClaim
          ? Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _rebateRow('业务日', businessDate),
                SizedBox(height: 8.h),
                _rebateRow('流水', turnover),
                SizedBox(height: 8.h),
                _rebateRow('笔数', count),
                SizedBox(height: 8.h),
                _rebateRow('本次回水', amount),
              ],
            )
          : const Text('暂无可领取回水'),
      actions: canClaim
          ? [
              TextButton(onPressed: safeDialogPop(ctx, false), child: const Text('取消')),
              FilledButton(onPressed: safeDialogPop(ctx, true), child: const Text('确定')),
            ]
          : [
              FilledButton(onPressed: safeDialogPop(ctx, false), child: const Text('知道了')),
            ],
    ),
  );
  return ok == true;
}

Widget _rebateRow(String label, String value) {
  return Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SizedBox(
        width: 72.w,
        child: Text(label, style: TextStyle(fontSize: 13.sp, color: Colors.black54)),
      ),
      Expanded(
        child: Text(value, style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600)),
      ),
    ],
  );
}

class _BetConfirmSheet extends StatefulWidget {
  const _BetConfirmSheet({
    required this.loadLines,
    this.issueNo,
  });

  final Future<List<BetConfirmLine>> Function() loadLines;
  final String? issueNo;

  @override
  State<_BetConfirmSheet> createState() => _BetConfirmSheetState();
}

class _BetConfirmSheetState extends State<_BetConfirmSheet> {
  List<BetConfirmLine>? _lines;
  String? _error;
  bool _loading = true;
  bool _followLatestOdds = true;
  String? _amountError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final lines = await widget.loadLines();
      if (!mounted) return;
      if (lines.isEmpty) {
        setState(() {
          _loading = false;
          _error = '无可确认注单';
        });
        return;
      }
      for (final l in lines) {
        l.amountCtrl.addListener(_onAmountChanged);
      }
      setState(() {
        _lines = lines;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  void _onAmountChanged() {
    if (mounted) setState(() => _amountError = null);
  }

  @override
  void dispose() {
    final lines = _lines;
    if (lines != null) {
      for (final l in lines) {
        l.amountCtrl.removeListener(_onAmountChanged);
        l.dispose();
      }
    }
    super.dispose();
  }

  int get _count => _lines?.length ?? 0;

  int get _total {
    var sum = 0;
    for (final l in _lines ?? const <BetConfirmLine>[]) {
      final n = int.tryParse(l.amountCtrl.text.trim());
      if (n != null && n > 0) sum += n;
    }
    return sum;
  }

  void _submit() {
    final lines = _lines;
    if (lines == null || lines.isEmpty) return;
    final items = <Map<String, dynamic>>[];
    final cmdParts = <String>[];
    for (final l in lines) {
      final raw = l.amountCtrl.text.trim();
      final n = int.tryParse(raw);
      if (n == null || n <= 0) {
        setState(() => _amountError = '请输入正整数金额');
        return;
      }
      items.add({'playCode': l.playCode, 'amount': n});
      cmdParts.add('${l.label.replaceAll(' ', '/')}/$n');
    }
    Navigator.of(context).pop(
      BetConfirmResult(items: items, command: cmdParts.join(' ')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final issue = (widget.issueNo ?? '').trim();
    return Dialog(
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
                '下注明细 (请确认注单)',
                style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w700),
              ),
              if (issue.isNotEmpty) ...[
                SizedBox(height: 4.h),
                Text('期号 $issue', style: TextStyle(fontSize: 12.sp, color: AppColors.textSecondary)),
              ],
              SizedBox(height: 10.h),
              if (_loading) ...[
                Padding(
                  padding: EdgeInsets.symmetric(vertical: 28.h),
                  child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                ),
                _cancelButton(),
              ] else if (_error != null) ...[
                Padding(
                  padding: EdgeInsets.symmetric(vertical: 20.h),
                  child: Text(_error!, style: TextStyle(fontSize: 13.sp, color: AppColors.danger)),
                ),
                _cancelButton(),
              ] else ...[
                _headerRow(),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: _lines!.length,
                    separatorBuilder: (_, __) =>
                        const Divider(height: 1, color: Color(0xFFEEEEEE)),
                    itemBuilder: (_, i) => _lineRow(_lines![i]),
                  ),
                ),
                SizedBox(height: 8.h),
                Text(
                  '笔数 $_count　总金额 $_total',
                  style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600),
                ),
                if (_amountError != null) ...[
                  SizedBox(height: 4.h),
                  Text(_amountError!, style: TextStyle(fontSize: 12.sp, color: AppColors.danger)),
                ],
                SizedBox(height: 10.h),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: OutlinedButton.styleFrom(
                          padding: EdgeInsets.symmetric(vertical: 10.h),
                        ),
                        child: const Text('取消'),
                      ),
                    ),
                    SizedBox(width: 10.w),
                    Expanded(
                      child: FilledButton(
                        onPressed: _submit,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.navBlue,
                          padding: EdgeInsets.symmetric(vertical: 10.h),
                        ),
                        child: const Text('确定'),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 6.h),
                InkWell(
                  onTap: () => setState(() => _followLatestOdds = !_followLatestOdds),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 22.w,
                        height: 22.w,
                        child: Checkbox(
                          value: _followLatestOdds,
                          onChanged: (v) => setState(() => _followLatestOdds = v ?? true),
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                      SizedBox(width: 4.w),
                      Expanded(
                        child: Text(
                          '如赔率变化，按最新赔率投注，不提示赔率变化',
                          style: TextStyle(fontSize: 11.sp, color: AppColors.textSecondary),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _cancelButton() {
    return OutlinedButton(
      onPressed: () => Navigator.of(context).pop(),
      style: OutlinedButton.styleFrom(
        padding: EdgeInsets.symmetric(vertical: 10.h),
      ),
      child: const Text('取消'),
    );
  }

  Widget _headerRow() {
    return Container(
      color: const Color(0xFFF5F5F5),
      padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 8.h),
      child: Row(
        children: [
          Expanded(flex: 5, child: Text('号码', style: _headStyle)),
          Expanded(flex: 3, child: Text('赔率', style: _headStyle, textAlign: TextAlign.center)),
          Expanded(flex: 4, child: Text('金额', style: _headStyle, textAlign: TextAlign.center)),
        ],
      ),
    );
  }

  TextStyle get _headStyle => TextStyle(
        fontSize: 12.sp,
        fontWeight: FontWeight.w600,
        color: AppColors.textSecondary,
      );

  Widget _lineRow(BetConfirmLine line) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 6.h),
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
            child: SizedBox(
              height: 34.h,
              child: TextField(
                controller: line.amountCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13.sp),
                decoration: InputDecoration(
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 8.h),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(4.r)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
