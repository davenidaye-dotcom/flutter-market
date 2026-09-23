import 'package:flutter/widgets.dart';

/// 弹层/对话框关闭后再 dispose，避免 EditableText 仍挂着 listener 时触发
/// `_dependents.isEmpty` 断言红屏。
void disposeTextControllersAfterFrame(Iterable<TextEditingController> controllers) {
  final list = List<TextEditingController>.of(controllers);
  WidgetsBinding.instance.addPostFrameCallback((_) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final c in list) {
        c.dispose();
      }
    });
  });
}
