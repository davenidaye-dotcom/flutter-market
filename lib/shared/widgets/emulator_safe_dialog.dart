import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 收起软键盘：弹窗前后、跳转前调用，避免模拟器 IME+重建卡死。
Future<void> dismissSoftKeyboard() async {
  FocusManager.instance.primaryFocus?.unfocus();
  SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
}

/// 模拟器友好弹窗：先收键盘 → 弹 → 关闭后再收一次并稍等。
Future<T?> showEmulatorSafeDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
  bool useRootNavigator = true,
  Color? barrierColor,
}) async {
  await dismissSoftKeyboard();
  await Future<void>.delayed(const Duration(milliseconds: 80));
  if (!context.mounted) return null;

  final result = await showDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    useRootNavigator: useRootNavigator,
    barrierColor: barrierColor,
    builder: builder,
  );

  await dismissSoftKeyboard();
  await Future<void>.delayed(const Duration(milliseconds: 80));
  return result;
}

/// 对话框按钮：先藏键盘再 pop，减少确定瞬间卡死。
VoidCallback safeDialogPop<T>(BuildContext dialogContext, [T? value]) {
  return () {
    FocusManager.instance.primaryFocus?.unfocus();
    SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
    Navigator.of(dialogContext).pop(value);
  };
}
