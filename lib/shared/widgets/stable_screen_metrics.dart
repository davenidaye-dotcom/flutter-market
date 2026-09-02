import 'package:flutter/material.dart';

/// 软键盘弹出时屏蔽 viewInsets 变化，避免 ScreenUtil 按新高度重建整棵 Widget 树。
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

    final bottom = mq.viewInsets.bottom;
    final stable = mq.copyWith(
      size: size,
      viewInsets: bottom == 0 ? mq.viewInsets : EdgeInsets.zero,
      padding: mq.padding,
      viewPadding: mq.viewPadding,
    );
    return MediaQuery(data: stable, child: widget.child);
  }
}
