import 'dart:convert';

import 'package:letou_app/data/models/chat_message_model.dart';
import 'package:letou_app/features/lottery/utils/draw_history_rows.dart';
import 'package:letou_app/features/lottery/utils/draw_result_parse.dart';

/// 与 [LotteryRepository._parseChatMessage] 保持一致，供回归测试断言。
ChatMessageModel parseApiChatMessage(Map<String, dynamic> m) {
  final msgType = m['msgType']?.toString().toUpperCase() ?? 'CHAT';
  final createdAt = m['createdAt']?.toString() ?? '';
  final time = createdAt.length >= 16 ? createdAt.substring(11, 16) : createdAt;
  final content = m['content']?.toString() ?? '';
  final parsed = msgType == 'DRAW_RESULT'
      ? DrawResultParse.parse(content)
      : (issueNo: null, ranks: const <int>[]);
  final apiIssue = m['issueNo']?.toString();
  final isUserChat = msgType == 'CHAT';
  return ChatMessageModel(
    id: m['id']?.toString() ?? '',
    sender: m['senderName']?.toString() ?? (isUserChat ? '会员' : '管理员'),
    content: content,
    time: time,
    type: switch (msgType) {
      'DRAW_RESULT' => ChatMessageType.resultCard,
      'SEAL_WARN' || 'SEALED' || 'SYS' => ChatMessageType.system,
      _ => ChatMessageType.text,
    },
    isAdmin: !isUserChat,
    issueNo: apiIssue?.isNotEmpty == true
        ? apiIssue
        : (parsed.issueNo ?? _issueFromMessageId(m['id']?.toString())),
    drawRanks: parsed.ranks.isEmpty ? null : parsed.ranks,
  );
}

String? _issueFromMessageId(String? id) {
  if (id == null || id.isEmpty) return null;
  final parts = id.split('-');
  if (parts.length < 3) return null;
  return parts.last;
}

List<ChatMessageModel> parseApiChatMessages(List<dynamic> raw) {
  return raw
      .whereType<Map>()
      .map((e) => parseApiChatMessage(Map<String, dynamic>.from(e)))
      .toList()
      .reversed
      .toList();
}

List<Map<String, dynamic>> loadJsonList(String json) {
  final decoded = jsonDecode(json);
  if (decoded is List) {
    return decoded
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }
  return const [];
}

List<Map<String, dynamic>> loadDrawHistoryRows(String json) {
  final decoded = jsonDecode(json);
  if (decoded is Map && decoded['rows'] is List) {
    return (decoded['rows'] as List)
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }
  if (decoded is List) {
    return decoded
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }
  return const [];
}

ChatMessageModel sealWarn(String gameId, String issue, {int remain = 9}) {
  return ChatMessageModel(
    id: 'seal-warn-$gameId-$issue',
    sender: '管理员',
    content: '注意：距离封盘时间还有${remain}秒，封盘之后将不能再投注！',
    time: '21:05',
    type: ChatMessageType.system,
    isAdmin: true,
    issueNo: issue,
  );
}

ChatMessageModel sealedLine(String gameId, String issue) {
  return ChatMessageModel(
    id: 'sealed-$gameId-$issue',
    sender: '管理员',
    content: '======停止战斗====== =======封盘线=======',
    time: '21:05',
    type: ChatMessageType.system,
    isAdmin: true,
    issueNo: issue,
  );
}

ChatMessageModel drawCard(String gameId, String issue, List<int> ranks) {
  return ChatMessageModel(
    id: 'draw-$gameId-$issue',
    sender: '管理员',
    content: '第$issue期开奖',
    time: '21:06',
    type: ChatMessageType.resultCard,
    isAdmin: true,
    issueNo: issue,
    drawRanks: ranks,
  );
}

ChatMessageModel userBet(String gameId, String orderId, String command) {
  return ChatMessageModel(
    id: 'bet-chat-$gameId-$orderId',
    sender: 'player01',
    content: command,
    time: '21:04',
    type: ChatMessageType.text,
    isAdmin: false,
  );
}

ChatMessageModel betRank(String gameId, String issue) {
  return ChatMessageModel(
    id: betRankChatMessageId(gameId, issue),
    sender: '机器人',
    content: '$issue期已封盘\n竞猜列表核对',
    time: '21:05',
    type: ChatMessageType.betListCheck,
    isAdmin: false,
    issueNo: issue,
  );
}

ChatMessageModel winList(String gameId, String issue) {
  return ChatMessageModel(
    id: winListChatMessageId(gameId, issue),
    sender: '机器人',
    content: '$issue期已开奖\n中奖列表核对',
    time: '21:06',
    type: ChatMessageType.winCheck,
    isAdmin: false,
    issueNo: issue,
  );
}

List<ChatMessageModel> drawsFromHistoryJson(String json, String gameId) {
  final rows = drawHistoryRowsFromApi(loadDrawHistoryRows(json));
  return drawRowsToResultMessages(rows, gameId: gameId);
}
