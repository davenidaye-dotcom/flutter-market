import 'dart:convert';

/// WS 原始帧 → Map（可在 isolate 中调用）
Map<String, dynamic>? decodeWsJsonFrame(String raw) {
  try {
    final decoded = jsonDecode(raw);
    if (decoded is Map) {
      return Map<String, dynamic>.from(decoded);
    }
  } catch (_) {}
  return null;
}
