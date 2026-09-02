import '../../../data/models/chat_message_model.dart';
import '../utils/chat_timeline.dart';

/// isolate 入口：从 JSON map 列表构建聊天时间线
List<Map<String, dynamic>> buildTimelinePayload(Map<String, dynamic> raw) {
  final gameId = raw['gameId']?.toString() ?? '';
  final items = raw['messages'];
  final messages = <ChatMessageModel>[];
  if (items is List) {
    for (final json in items) {
      if (json is! Map) continue;
      final m = _messageFromJson(Map<String, dynamic>.from(json));
      if (m != null) messages.add(m);
    }
  }
  final timeline = buildChatTimeline(
    messages,
    gameId: gameId,
    syntheticSeals: true,
  );
  return timeline.map(_messageToJson).toList(growable: false);
}

ChatMessageModel? messageFromTimelineJson(Map<String, dynamic> json) =>
    _messageFromJson(json);

Map<String, dynamic> _messageToJson(ChatMessageModel message) => {
      'id': message.id,
      'sender': message.sender,
      'content': message.content,
      'time': message.time,
      'type': message.type.name,
      'isAdmin': message.isAdmin,
      if (message.issueNo != null) 'issueNo': message.issueNo,
      if (message.drawRanks != null) 'drawRanks': message.drawRanks,
    };

ChatMessageModel? _messageFromJson(Map<String, dynamic> json) {
  final id = json['id']?.toString();
  if (id == null || id.isEmpty) return null;
  final typeName = json['type']?.toString() ?? 'text';
  final type = ChatMessageType.values.firstWhere(
    (t) => t.name == typeName,
    orElse: () => ChatMessageType.text,
  );
  final ranksRaw = json['drawRanks'];
  final List<int>? drawRanks = ranksRaw is List
      ? ranksRaw.map((e) => int.tryParse('$e') ?? 0).where((e) => e > 0).toList()
      : null;
  return ChatMessageModel(
    id: id,
    sender: json['sender']?.toString() ?? '管理员',
    content: json['content']?.toString() ?? '',
    time: json['time']?.toString() ?? '',
    type: type,
    isAdmin: json['isAdmin'] == true,
    issueNo: json['issueNo']?.toString(),
    drawRanks: drawRanks == null || drawRanks.isEmpty ? null : drawRanks,
  );
}
