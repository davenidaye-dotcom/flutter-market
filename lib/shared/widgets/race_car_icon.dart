import 'package:flutter/material.dart';

/// 底栏「游戏」：侧面赛车，线宽与客服图标同一档。
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
      ..strokeWidth = 1.7
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final ground = Path()..moveTo(4.5, 15.4)..lineTo(19.5, 15.4);
    final body = Path()
      ..moveTo(6.2, 15.4)
      ..lineTo(7.9, 11.2)
      ..arcToPoint(
        const Offset(9.5, 10),
        radius: const Radius.circular(1.7),
        clockwise: true,
      )
      ..lineTo(14.5, 10)
      ..cubicTo(15.14, 10, 15.72, 10.36, 16, 11)
      ..lineTo(17.8, 15.4);
    final cabin = Path()
      ..moveTo(9.4, 10)
      ..lineTo(10.4, 7.85)
      ..arcToPoint(
        const Offset(11.5, 7.2),
        radius: const Radius.circular(1.2),
        clockwise: true,
      )
      ..lineTo(12.6, 7.2)
      ..cubicTo(13.08, 7.2, 13.52, 7.48, 13.72, 7.92)
      ..lineTo(14.7, 10);

    canvas.drawPath(ground, stroke);
    canvas.drawPath(body, stroke);
    canvas.drawPath(cabin, stroke);
    canvas.drawCircle(const Offset(8, 15.4), 1.65, stroke);
    canvas.drawCircle(const Offset(16.1, 15.4), 1.65, stroke);
  }

  @override
  bool shouldRepaint(covariant _RaceCarPainter oldDelegate) => oldDelegate.color != color;
}
