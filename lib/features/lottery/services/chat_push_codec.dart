import 'dart:convert';

/// 在 isolate 中解析/序列化聊天缓存，避免主线程 jsonDecode/jsonEncode 卡死。
List<Map<String, dynamic>> decodeChatCachePayload(String raw) {
  final decoded = jsonDecode(raw);
  if (decoded is! List) return const [];
  final out = <Map<String, dynamic>>[];
  for (final item in decoded) {
    if (item is Map) {
      out.add(Map<String, dynamic>.from(item));
    }
  }
  return out;
}

String encodeChatCachePayload(List<Map<String, dynamic>> items) {
  return jsonEncode(items);
}
