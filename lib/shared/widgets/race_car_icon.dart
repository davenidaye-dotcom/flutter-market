import 'package:flutter/material.dart';

/// 底栏「游戏」：侧面赛车，占位和线宽对齐旁边的 Material 图标。
class RaceCarIcon extends StatelessWidget {
  const RaceCarIcon({super.key, required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _RaceCarPainter(color),
    );
  }
}

class _RaceCarPainter extends CustomPainter {
  const _RaceCarPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 24;
    canvas.scale(scale);
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final ground = Path()..moveTo(2, 17.6)..lineTo(22, 17.6);
    final body = Path()
      ..moveTo(3.2, 17.6)
      ..lineTo(5.4, 12.2)
      ..arcToPoint(
        const Offset(7.6, 10.4),
        radius: const Radius.circular(2.2),
        clockwise: true,
      )
      ..lineTo(15.2, 10.4)
      ..cubicTo(16.2, 10.4, 17.1, 10.9, 17.6, 11.8)
      ..lineTo(20.8, 17.6);
    final cabin = Path()
      ..moveTo(8.2, 10.4)
      ..lineTo(9.6, 6.0)
      ..arcToPoint(
        const Offset(11.4, 4.4),
        radius: const Radius.circular(1.8),
        clockwise: true,
      )
      ..lineTo(13.0, 4.4)
      ..cubicTo(13.9, 4.4, 14.6, 4.9, 15.0, 5.7)
      ..lineTo(16.4, 10.4);

    canvas.drawPath(ground, stroke);
    canvas.drawPath(body, stroke);
    canvas.drawPath(cabin, stroke);
    canvas.drawCircle(const Offset(7.6, 17.6), 2.55, stroke);
    canvas.drawCircle(const Offset(16.6, 17.6), 2.55, stroke);
  }

  @override
  bool shouldRepaint(covariant _RaceCarPainter oldDelegate) => oldDelegate.color != color;
}
