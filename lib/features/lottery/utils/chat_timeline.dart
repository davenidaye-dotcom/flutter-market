import '../../../data/models/chat_message_model.dart';
import 'bet_repeat_helper.dart';

import 'draw_history_rows.dart';

/// 将封盘消息插入对应期号的开奖结果之前，按时间线旧→新排序。
/// 每期开奖若缺封盘/预警，在此动态补全（不依赖 buffer 是否被裁剪）。
List<ChatMessageModel> buildChatTimeline(
  List<ChatMessageModel> messages, {
  String gameId = '',
  bool syntheticSeals = false,
}) {
  if (messages.isEmpty) return const [];

  final expanded = List<ChatMessageModel>.from(messages);
  final draws = <int, ChatMessageModel>{};
  final warnIssues = <int>{};
  final sealedIssues = <int>{};

  for (final m in messages) {
    final issue = extractIssue(m);
    if (issue == null || issue.isEmpty) continue;
    final issueKey = issueCompareKey(issue);
    if (issueKey <= 0) continue;
    if (m.type == ChatMessageType.resultCard) {
      draws[issueKey] = m;
    } else if (m.type == ChatMessageType.system) {
      if (m.content.contains('封盘线') || m.content.contains('停止战斗')) {
        sealedIssues.add(issueKey);
      } else if (m.content.contains('封盘')) {
        warnIssues.add(issueKey);
      }
    }
  }

  if (syntheticSeals) {
    for (final draw in draws.values) {
      final issue = extractIssue(draw);
      if (issue == null || issue.isEmpty) continue;
      final issueKey = issueCompareKey(issue);
      if (issueKey <= 0) continue;
      if (warnIssues.contains(issueKey) && sealedIssues.contains(issueKey)) {
        continue;
      }

      for (final seal in syntheticSealMessagesForDraw(
        gameId: gameId,
        draw: draw,
      )) {
        final isLine = seal.content.contains('封盘线') ||
            seal.content.contains('停止战斗');
        if (isLine && sealedIssues.contains(issueKey)) continue;
        if (!isLine && warnIssues.contains(issueKey)) continue;
        expanded.add(seal);
        if (isLine) {
          sealedIssues.add(issueKey);
        } else {
          warnIssues.add(issueKey);
        }
      }
    }
  }

  final deduped = <String, ChatMessageModel>{};
  for (final m in expanded) {
    final key = _timelineDedupeKey(m);
    final existing = deduped[key];
    if (existing == null || _preferTimelineMessage(m, existing)) {
      deduped[key] = m;
    }
  }
  final list = deduped.values.toList()
    ..sort((a, b) {
      final ai = _issueSortKey(a);
      final bi = _issueSortKey(b);
      if (ai != bi) return ai.compareTo(bi);
      return _phaseOrder(a).compareTo(_phaseOrder(b));
    });
  return list;
}

/// 历史兜底封盘文案，与 Java tickGame 推送一致。
List<ChatMessageModel> syntheticSealMessagesForDraw({
  required String gameId,
  required ChatMessageModel draw,
}) {
  final issue = extractIssue(draw);
  if (issue == null || issue.isEmpty) return const [];
  return [
    ChatMessageModel(
      id: 'hist-seal-warn-$gameId-${issueCompareKey(issue)}',
      sender: '机器人',
      content: '注意：距离封盘时间还有10秒，封盘之后将不能再投注！',
      time: '',
      type: ChatMessageType.system,
      isAdmin: true,
      issueNo: issue.trim(),
    ),
    ChatMessageModel(
      id: 'hist-sealed-$gameId-${issueCompareKey(issue)}',
      sender: '机器人',
      content: '======停止战斗====== =======封盘线=======',
      time: '',
      type: ChatMessageType.system,
      isAdmin: true,
      issueNo: issue.trim(),
    ),
  ];
}

bool hasSealMessagesForIssue(
  Iterable<ChatMessageModel> messages,
  String issue,
) {
  for (final m in messages) {
    if (m.type != ChatMessageType.system) continue;
    if (extractIssue(m) == issue) return true;
  }
  return false;
}

String? extractIssue(ChatMessageModel message) {
  final issue = message.issueNo;
  if (issue != null && issue.isNotEmpty) return issue;
  final match = RegExp(r'第(\d+)期').firstMatch(message.content);
  return match?.group(1);
}

int _issueSortKey(ChatMessageModel message) {
  final issue = extractIssue(message);
  if (issue == null || issue.isEmpty) return 1 << 30;
  // 时间线排序用全号，避免 %10000 跨天回绕把旧下注排到最新开奖后面
  final full = int.tryParse(issue.trim());
  if (full != null && full > 0) return full;
  final key = issueCompareKey(issue);
  if (key > 0) return key;
  return issue.hashCode;
}

int _phaseOrder(ChatMessageModel message) {
  return switch (message.type) {
    ChatMessageType.text || ChatMessageType.betReceipt => 0,
    ChatMessageType.system =>
      message.content.contains('封盘线') || message.content.contains('停止战斗')
          ? 2
          : 1,
    ChatMessageType.resultCard => 3,
    _ => 4,
  };
}

bool _isSyntheticTimelineMessage(ChatMessageModel message) {
  return message.id.startsWith('hist-seal-');
}

/// 去重时优先保留 WS/HTTP 真实消息（含时间），合成封盘仅作兜底。
bool _preferTimelineMessage(
  ChatMessageModel incoming,
  ChatMessageModel existing,
) {
  final incomingSynthetic = _isSyntheticTimelineMessage(incoming);
  final existingSynthetic = _isSyntheticTimelineMessage(existing);
  if (incomingSynthetic != existingSynthetic) {
    return !incomingSynthetic;
  }
  if (incoming.time.trim().isNotEmpty && existing.time.trim().isEmpty) {
    return true;
  }
  if (incoming.time.trim().isEmpty && existing.time.trim().isNotEmpty) {
    return false;
  }
  return false;
}

String _timelineDedupeKey(ChatMessageModel m) {
  if (isUserBetChatMessage(m) && m.id.isNotEmpty) {
    return 'user-${m.id}';
  }
  final issue = extractIssue(m);
  if (m.type == ChatMessageType.resultCard &&
      issue != null &&
      issue.isNotEmpty) {
    return 'draw-${issueCompareKey(issue)}';
  }
  if (m.type == ChatMessageType.system && issue != null && issue.isNotEmpty) {
    if (m.content.contains('封盘线') || m.content.contains('停止战斗')) {
      return 'sealed-${issueCompareKey(issue)}';
    }
    if (m.content.contains('封盘')) {
      return 'seal-warn-${issueCompareKey(issue)}';
    }
  }
  return m.id.isNotEmpty
      ? m.id
      : '${m.type.name}-${issue ?? ''}-${m.content.hashCode}';
}
