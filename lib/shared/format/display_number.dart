/// 展示用数字：去掉小数尾零。期号、账号、日期不要走这里。
String displayNumber(dynamic value) {
  if (value == null) return '0';
  final raw = value is String ? value.trim() : null;
  if (raw != null && raw.isEmpty) return '0';

  final parsed = value is num ? value : num.tryParse(raw ?? '$value');
  if (parsed == null) return raw ?? '$value';
  if (parsed == 0) return '0';

  var plain = raw != null && !_scientific(raw) ? raw : parsed.toStringAsFixed(8);
  if (plain.startsWith('+')) plain = plain.substring(1);
  if (plain.contains('.')) {
    plain = plain.replaceFirst(RegExp(r'0+$'), '');
    plain = plain.replaceFirst(RegExp(r'\.$'), '');
  }
  if (plain == '-0' || plain.isEmpty) return '0';
  return plain;
}

bool _scientific(String raw) {
  final s = raw.toLowerCase();
  return s.contains('e');
}
