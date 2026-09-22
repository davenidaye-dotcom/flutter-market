import 'package:flutter/material.dart';

/// 锁定 [MediaQuery.size]，避免软键盘导致 ScreenUtil 按新高度整树重建。
///
/// 注意：必须保留真实 [viewInsets]。若清零，底部弹层/输入框无法避让键盘。
class StableScreenMetrics extends StatefulWidget {
  const StableScreenMetrics({super.key, required this.child});

  final Widget child;

  @override
  State<StableScreenMetrics> createState() => _StableScreenMetricsState();
}

class _StableScreenMetricsState extends State<StableScreenMetrics> {
  Size? _lockedSize;

  static bool _isValidSize(Size size) => size.width > 0 && size.height > 0;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    if (_lockedSize == null || !_isValidSize(_lockedSize!)) {
      if (_isValidSize(mq.size)) {
        _lockedSize = mq.size;
      }
    }

    final size = (_lockedSize != null && _isValidSize(_lockedSize!))
        ? _lockedSize!
        : mq.size;

    // 只锁 size；viewInsets 原样下发，供键盘避让使用
    final stable = mq.copyWith(size: size);
    return MediaQuery(data: stable, child: widget.child);
  }
}

/// 读 FlutterView 真实键盘高度，不受上层 MediaQuery 篡改影响。
double realKeyboardInset(BuildContext context) {
  return MediaQueryData.fromView(View.of(context)).viewInsets.bottom;
}
