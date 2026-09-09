/// 验签密钥碎片 A（勿合并成明文常量；与 B/C/D 按编排器重组）
String frSignPieceA() {
  // reverse('Fr9kQx2m')
  const raw = 'm2xQk9rF';
  return String.fromCharCodes(raw.codeUnits.reversed);
}

/// 诱饵，故意不参与重组
String frSignDecoyA() => 'K9mP2xQ#Lw';
