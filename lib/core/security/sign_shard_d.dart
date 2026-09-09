/// 验签密钥碎片 D
String frSignPieceD() {
  // reverse('6cH1jR5!')
  const raw = '!5Rj1Hc6';
  return String.fromCharCodes(raw.codeUnits.reversed);
}

String frSignDecoyD() => 'Fr9kQx2m??';
