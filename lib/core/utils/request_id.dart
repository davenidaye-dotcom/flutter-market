import 'dart:math';

final _rng = Random.secure();

/// UUID v4（小写，含连字符，满足服务端 [A-Za-z0-9_-]{1,64}）。
String newRequestId() {
  final b = List<int>.generate(16, (_) => _rng.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  String hex(int from, int to) => [
        for (var i = from; i < to; i++) b[i].toRadixString(16).padLeft(2, '0'),
      ].join();
  return '${hex(0, 4)}-${hex(4, 6)}-${hex(6, 8)}-${hex(8, 10)}-${hex(10, 16)}';
}
