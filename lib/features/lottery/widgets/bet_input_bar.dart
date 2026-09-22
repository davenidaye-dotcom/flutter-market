import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../config/theme/app_colors.dart';

/// 下注输入栏（纯展示 + 点击回调，不用 TextField，避免模拟器弹系统键盘卡死）
/// 右侧一颗按钮：无内容 = 圆圈+（菜单）；有内容 = 飞机发送。
/// 文本换行后按钮贴底，与末行文本垂直对齐；单行时与输入框同高居中。
class BetInputBar extends StatelessWidget {
  const BetInputBar({
    super.key,
    required this.controller,
    required this.onTapInput,
    required this.onToggleMenu,
    required this.onSend,
    this.menuOpen = false,
    this.keypadOpen = false,
    this.enabled = true,
    this.submitting = false,
  });

  final TextEditingController controller;
  final VoidCallback onTapInput;
  final VoidCallback onToggleMenu;
  final VoidCallback onSend;
  final bool menuOpen;
  final bool keypadOpen;
  final bool enabled;
  final bool submitting;

  static double get _barH => 44.h;

  @override
  Widget build(BuildContext context) {
    final bg = !enabled
        ? const Color(0xFFE8E8E8)
        : (keypadOpen || menuOpen ? Colors.white : const Color(0xFFEEEEEE));
    final hint = enabled ? '请输入投注金额' : '房主不可下注';
    final fieldBg = enabled ? const Color(0xFFF5F5F5) : const Color(0xFFDDDDDD);
    final textColor = enabled ? AppColors.textPrimary : AppColors.textHint;

    return Material(
      color: bg,
      child: Padding(
        padding: EdgeInsets.fromLTRB(12.w, 10.h, 12.w, 10.h),
        child: ValueListenableBuilder<TextEditingValue>(
          valueListenable: controller,
          builder: (_, value, _) {
            final empty = value.text.trim().isEmpty;
            final canSend = enabled && !submitting && !empty;
            final showSend = !empty;
            return Row(
              // 单行：输入框高度=按钮高度，底对齐=视觉居中
              // 多行：按钮贴底，对齐最后一行文本
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: enabled ? onTapInput : null,
                    behavior: HitTestBehavior.opaque,
                    child: Container(
                      constraints: BoxConstraints(minHeight: _barH),
                      alignment: Alignment.centerLeft,
                      padding: EdgeInsets.symmetric(
                        horizontal: 12.w,
                        vertical: 10.h,
                      ),
                      decoration: BoxDecoration(
                        color: fieldBg,
                        borderRadius: BorderRadius.circular(8.r),
                        border: Border.all(
                          color: keypadOpen && enabled
                              ? AppColors.navBlue
                              : (enabled
                                  ? const Color(0xFFDDDDDD)
                                  : const Color(0xFFCCCCCC)),
                          width: keypadOpen && enabled ? 1.5 : 1,
                        ),
                      ),
                      child: Text(
                        empty ? hint : value.text,
                        softWrap: true,
                        style: TextStyle(
                          fontSize: 14.sp,
                          height: 1.35,
                          color: empty ? AppColors.textHint : textColor,
                        ),
                      ),
                    ),
                  ),
                ),
                SizedBox(width: 10.w),
                SizedBox(
                  width: _barH,
                  height: _barH,
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: !enabled || submitting
                          ? null
                          : (showSend
                              ? (canSend ? onSend : null)
                              : onToggleMenu),
                      customBorder: const CircleBorder(),
                      child: Center(
                        child: submitting
                            ? SizedBox(
                                width: 22.w,
                                height: 22.w,
                                child: const CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : showSend
                                ? _SendPlaneIcon(
                                    size: 36.w,
                                    active: canSend,
                                  )
                                : _CirclePlusIcon(
                                    size: 36.w,
                                    active: enabled,
                                    highlighted: menuOpen,
                                  ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _CirclePlusIcon extends StatelessWidget {
  const _CirclePlusIcon({
    required this.size,
    required this.active,
    required this.highlighted,
  });

  final double size;
  final bool active;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final color = !active
        ? AppColors.textHint
        : (highlighted ? AppColors.navBlue : const Color(0xFF555555));
    return CustomPaint(
      size: Size(size, size),
      painter: _CirclePlusPainter(color: color),
    );
  }
}

class _CirclePlusPainter extends CustomPainter {
  _CirclePlusPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.08;
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2 - stroke;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(c, r, paint);

    final arm = size.width * 0.22;
    canvas.drawLine(Offset(c.dx - arm, c.dy), Offset(c.dx + arm, c.dy), paint);
    canvas.drawLine(Offset(c.dx, c.dy - arm), Offset(c.dx, c.dy + arm), paint);
  }

  @override
  bool shouldRepaint(covariant _CirclePlusPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _SendPlaneIcon extends StatelessWidget {
  const _SendPlaneIcon({required this.size, required this.active});

  final double size;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final bg = active ? AppColors.navBlue : const Color(0xFFBDBDBD);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
      // 略偏右上，纸飞机视觉重心对齐圆圆心
      child: Transform.translate(
        offset: Offset(1.w, -0.5.h),
        child: Transform.rotate(
          angle: -0.6,
          child: Icon(
            Icons.send_rounded,
            size: size * 0.48,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}
