import 'package:flutter/material.dart';

import '../utils/pc28_format.dart';

/// 加拿大开奖：三个号码圆球，加号隔开，等号后是总和球。颜色按球内数字的波色。
class Pc28DrawFormula extends StatelessWidget {
  const Pc28DrawFormula({
    super.key,
    required this.numbers,
    this.placeholder = false,
    this.ballSize = 18,
    this.gap = 6,
  });

  final List<int> numbers;
  final bool placeholder;
  final double ballSize;
  final double gap;

  @override
  Widget build(BuildContext context) {
    final ok = !placeholder && Pc28Format.valid(numbers);
    final values = ok
        ? <int?>[...numbers, Pc28Format.sumOf(numbers)]
        : const <int?>[null, null, null, null];
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < values.length; i++) ...[
            if (i > 0) ...[
              SizedBox(width: gap),
              Text(
                i == values.length - 1 ? '=' : '+',
                style: TextStyle(
                  fontSize: ballSize * 0.52,
                  height: 1,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF9AA0A6),
                ),
              ),
              SizedBox(width: gap),
            ],
            Pc28WaveBall(number: values[i], size: ballSize),
          ],
        ],
      ),
    );
  }
}

class Pc28WaveBall extends StatelessWidget {
  const Pc28WaveBall({super.key, required this.number, required this.size});

  final int? number;
  final double size;

  @override
  Widget build(BuildContext context) {
    final n = number;
    final color = n == null ? const Color(0xFFE4E6EA) : Pc28Format.colorOf(n);
    final light = Color.lerp(color, Colors.white, 0.55)!;
    final dark = Color.lerp(color, Colors.black, 0.32)!;
    final label = n == null ? '–' : '$n';
    final fontSize = size * 0.5;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          center: const Alignment(-0.35, -0.45),
          radius: 0.9,
          colors: [light, color, dark],
          stops: const [0.0, 0.55, 1.0],
        ),
      ),
      child: n == null
          ? Text(
              label,
              style: TextStyle(
                color: const Color(0xFF9AA0A6),
                fontSize: fontSize,
                height: 1,
                fontWeight: FontWeight.w700,
              ),
            )
          : Stack(
              alignment: Alignment.center,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: fontSize,
                    height: 1,
                    fontWeight: FontWeight.w700,
                    foreground: Paint()
                      ..style = PaintingStyle.stroke
                      ..strokeWidth = 0.8
                      ..color = const Color(0xFF000000),
                  ),
                ),
                Text(
                  label,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: fontSize,
                    height: 1,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
    );
  }
}
