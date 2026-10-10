/// 展示用数字：最多保留 [maxDecimals] 位小数（直接截断，不四舍五入），并去掉尾零。
/// 期号、账号、日期不要走这里。赔率等需要更多位时传更大的 maxDecimals；传负数表示不截断。
String displayNumber(dynamic value, {int maxDecimals = 2}) {
  if (value == null) return '0';
  final raw = value is String ? value.trim() : null;
  if (raw != null && raw.isEmpty) return '0';

  final parsed = value is num ? value : num.tryParse(raw ?? '$value');
  if (parsed == null) return raw ?? '$value';
  if (parsed == 0) return '0';

  var plain = raw != null && !_scientific(raw) ? raw : parsed.toStringAsFixed(8);
  if (plain.startsWith('+')) plain = plain.substring(1);
  if (maxDecimals >= 0) {
    plain = _truncateDecimals(plain, maxDecimals);
  }
  if (plain.contains('.')) {
    plain = plain.replaceFirst(RegExp(r'0+$'), '');
    plain = plain.replaceFirst(RegExp(r'\.$'), '');
  }
  if (plain == '-0' || plain.isEmpty) return '0';
  return plain;
}

/// 直接舍弃多余小数位，不四舍五入。例：111.927 → 111.92
String _truncateDecimals(String plain, int maxDecimals) {
  final dot = plain.indexOf('.');
  if (dot < 0) return plain;
  if (maxDecimals == 0) return plain.substring(0, dot);
  final end = dot + 1 + maxDecimals;
  if (end >= plain.length) return plain;
  return plain.substring(0, end);
}

bool _scientific(String raw) {
  final s = raw.toLowerCase();
  return s.contains('e');
}
