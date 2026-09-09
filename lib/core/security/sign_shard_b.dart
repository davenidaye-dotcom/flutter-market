/// 验签密钥碎片 B
String frSignPieceB() {
  // reverse('P7vL0sW#')
  const raw = '#Ws0Lv7P';
  return String.fromCharCodes(raw.codeUnits.reversed);
}

String frSignDecoyB() => 'zT4uY0nX';
