import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';

import 'page_app_bar.dart';

/// 把输入条抬到系统键盘上沿。和设置备注一样直接读窗口键盘高度。
/// 房间底栏里的页面会减掉底栏；从房间里点进来的整页不再减。
class KeyboardInputLift extends StatefulWidget {
  const KeyboardInputLift({super.key, required this.child});

  final Widget child;

  @override
  State<KeyboardInputLift> createState() => _KeyboardInputLiftState();
}

class _KeyboardInputLiftState extends State<KeyboardInputLift> with WidgetsBindingObserver {
  double _keyboard = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeMetrics() => _sync();

  void _sync() {
    if (!mounted) return;
    final views = WidgetsBinding.instance.platformDispatcher.views;
    if (views.isEmpty) return;
    final view = views.first;
    final next = view.viewInsets.bottom / view.devicePixelRatio;
    if ((next - _keyboard).abs() < 0.5) return;
    setState(() => _keyboard = next);
  }

  double get _lift {
    if (_keyboard <= 0) return 0;
    final fullPage = ShellCoverCloser.maybeOf(context) != null ||
        StatefulNavigationShell.maybeOf(context) == null;
    if (fullPage) return _keyboard;
    final views = WidgetsBinding.instance.platformDispatcher.views;
    final safe = views.isEmpty ? 0.0 : views.first.padding.bottom / views.first.devicePixelRatio;
    final nav = 56.h + safe;
    final lift = _keyboard - nav;
    return lift > 0 ? lift : 0;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedPadding(
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: _lift),
      child: widget.child,
    );
  }
}
