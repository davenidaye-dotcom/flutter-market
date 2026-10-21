import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../config/theme/app_colors.dart';
import 'emulator_safe_dialog.dart';

/// 上下分金额键盘。只接受按键拼出来的数字，不申请系统输入法。
String applyScoreKey(String amount, String key) {
  if (key == 'del') {
    return amount.isEmpty ? amount : amount.substring(0, amount.length - 1);
  }
  if (key == '.') {
    if (amount.contains('.')) return amount;
    return amount.isEmpty ? '0.' : '$amount.';
  }
  if (key.length != 1 || key.codeUnitAt(0) < 48 || key.codeUnitAt(0) > 57) {
    return amount;
  }
  final dot = amount.indexOf('.');
  if (dot >= 0) {
    if (amount.length - dot - 1 >= 2) return amount;
    return amount + key;
  }
  if (amount == '0') return key;
  if (amount.length >= 8) return amount;
  return amount + key;
}

/// 空、0、只剩小数点都不能提交。
bool scoreAmountSubmittable(String amount) {
  if (amount.isEmpty || amount == '.') return false;
  final n = double.tryParse(amount);
  return n != null && n > 0;
}

/// 底部安全数字键盘。返回金额文本；取消或点外面返回 null。
Future<String?> showScoreApplySheet(
  BuildContext context, {
  required String label,
}) async {
  await dismissSoftKeyboard();
  await Future<void>.delayed(const Duration(milliseconds: 80));
  if (!context.mounted) return null;
  final result = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16.r)),
    ),
    builder: (ctx) => _ScoreApplySheet(label: label),
  );
  await dismissSoftKeyboard();
  return result;
}

class _ScoreApplySheet extends StatefulWidget {
  const _ScoreApplySheet({required this.label});

  final String label;

  @override
  State<_ScoreApplySheet> createState() => _ScoreApplySheetState();
}

class _ScoreApplySheetState extends State<_ScoreApplySheet> {
  String _amount = '';

  static const _rows = [
    ['1', '2', '3'],
    ['4', '5', '6'],
    ['7', '8', '9'],
    ['.', '0', 'del'],
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      dismissSoftKeyboard();
    });
  }

  void _tap(String key) {
    final next = applyScoreKey(_amount, key);
    if (next == _amount) return;
    setState(() => _amount = next);
  }

  void _submit() {
    if (!scoreAmountSubmittable(_amount)) return;
    Navigator.of(context).pop(_amount);
  }

  @override
  Widget build(BuildContext context) {
    final ok = scoreAmountSubmittable(_amount);
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(16.w, 8.h, 8.w, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '申请${widget.label}',
                    style: TextStyle(
                      fontSize: 16.sp,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(
                    '取消',
                    style: TextStyle(fontSize: 15.sp, color: AppColors.textSecondary),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(16.w, 0, 16.w, 12.h),
            child: Container(
              width: double.infinity,
              alignment: Alignment.centerLeft,
              padding: EdgeInsets.only(bottom: 8.h),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: AppColors.primary, width: 1.5)),
              ),
              child: Text(
                _amount.isEmpty ? '请输入${widget.label}金额' : _amount,
                style: TextStyle(
                  fontSize: _amount.isEmpty ? 15.sp : 28.sp,
                  fontWeight: _amount.isEmpty ? FontWeight.w400 : FontWeight.w600,
                  color: _amount.isEmpty ? AppColors.textHint : AppColors.textPrimary,
                ),
              ),
            ),
          ),
          SizedBox(
            height: 208.h,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 3,
                  child: Column(
                    children: [
                      for (final row in _rows)
                        Expanded(
                          child: Row(
                            children: [
                              for (final key in row)
                                Expanded(
                                  child: _Key(
                                    label: key == 'del' ? '退格' : key,
                                    onTap: () => _tap(key),
                                  ),
                                ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  flex: 1,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: ok ? _submit : null,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: ok ? AppColors.primary : const Color(0xFFF2F3F5),
                        border: const Border(
                          top: BorderSide(color: AppColors.divider),
                          left: BorderSide(color: AppColors.divider),
                        ),
                      ),
                      child: Center(
                        child: Text(
                          '确定',
                          style: TextStyle(
                            fontSize: 16.sp,
                            fontWeight: FontWeight.w600,
                            color: ok ? Colors.white : AppColors.textHint,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Key extends StatefulWidget {
  const _Key({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  State<_Key> createState() => _KeyState();
}

class _KeyState extends State<_Key> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (_) => setState(() => _pressed = true),
      onPointerUp: (_) => setState(() => _pressed = false),
      onPointerCancel: (_) => setState(() => _pressed = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: _pressed ? const Color(0xFFE8F1FC) : Colors.white,
            border: const Border(
              top: BorderSide(color: AppColors.divider),
              right: BorderSide(color: AppColors.divider),
            ),
          ),
          child: Center(
            child: Text(
              widget.label,
              style: TextStyle(
                fontSize: widget.label == '退格' ? 14.sp : 20.sp,
                fontWeight: FontWeight.w500,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
