import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../shared/widgets/emulator_safe_dialog.dart';

/// 房主开启「下注确认」后的二次确认弹窗
Future<bool> showBetConfirmDialog({
  required BuildContext context,
  required String command,
  String? issueNo,
  String? amountText,
}) async {
  final ok = await showEmulatorSafeDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('确认下注'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _row('指令', command),
          if (issueNo != null && issueNo.isNotEmpty) ...[
            SizedBox(height: 8.h),
            _row('期号', issueNo),
          ],
          if (amountText != null && amountText.isNotEmpty) ...[
            SizedBox(height: 8.h),
            _row('金额', amountText),
          ],
        ],
      ),
      actions: [
        TextButton(onPressed: safeDialogPop(ctx, false), child: const Text('取消')),
        FilledButton(onPressed: safeDialogPop(ctx, true), child: const Text('确认下注')),
      ],
    ),
  );
  return ok == true;
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

Widget _row(String label, String value) {
  return Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SizedBox(
        width: 48.w,
        child: Text(label, style: TextStyle(fontSize: 13.sp, color: Colors.black54)),
      ),
      Expanded(
        child: Text(value, style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600)),
      ),
    ],
  );
}
