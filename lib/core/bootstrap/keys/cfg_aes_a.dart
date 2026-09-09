/// 配置解密 AES 口令碎片 A（重组后经 SHA256 得 32 字节密钥）
String cfgAesPieceA() {
  const raw = 'q9Km2x'; // reverse later in assembler with others
  return String.fromCharCodes(raw.codeUnits.reversed);
}

String cfgAesDecoyA() => 'NOPE_AES_A';
