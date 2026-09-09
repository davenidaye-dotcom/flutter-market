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
