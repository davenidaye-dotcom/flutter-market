/// 键盘盖进列表的高度，再加一行空隙。
/// [barHeight] 是仍留在屏幕底部的底栏。没有底栏时传 0。
double keyboardListCover({
  required double keyboard,
  required double safeBottom,
  required double barHeight,
  double gap = 8,
}) {
  if (keyboard <= 0) return 0;
  final overlap = keyboard - safeBottom - barHeight;
  if (overlap <= 0) return 0;
  return overlap + gap;
}

/// 把这一块的下沿抬到键盘上沿再留 [gap]。已经在键盘上方时返回 0。
double keyboardRevealDelta({
  required double rowBottom,
  required double keyboardTop,
  double gap = 8,
}) {
  final target = keyboardTop - gap;
  if (rowBottom <= target) return 0;
  return rowBottom - target;
}
