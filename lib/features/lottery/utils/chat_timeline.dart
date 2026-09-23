import '../../../data/models/chat_message_model.dart';
import 'bet_repeat_helper.dart';

import 'draw_history_rows.dart';

/// 将封盘消息插入对应期号的开奖结果之前，按时间线旧→新排序。
/// 同一期内：下注区(同注单 CHAT→RECEIPT 成对) → 封盘预警 → 封盘线 → 竞猜核对 → 开奖 → 中奖核对。
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
      final byIssue = _compareMessagesByIssue(a, b);
      if (byIssue != 0) return byIssue;
      final byPhase = _phaseOrder(a).compareTo(_phaseOrder(b));
      if (byPhase != 0) return byPhase;
      return _stableTieBreak(a, b);
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
      content: '======封盘线======\n======停止战斗======',
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
  if (issue != null && issue.isNotEmpty) return issue.trim();
  // 开奖卡：第34163647期开奖
  final withDi = RegExp(r'第(\d+)期').firstMatch(message.content);
  if (withDi != null) return withDi.group(1);
  // 竞猜/中奖核对：34163647期已封盘 / 34163647期已开奖
  final bare = RegExp(r'(\d{5,})期').firstMatch(message.content);
  return bare?.group(1);
}

/// 长短号同一期视为相等（走 [compareIssueNo]）；无期号排最后。
int _compareMessagesByIssue(ChatMessageModel a, ChatMessageModel b) {
  final ia = extractIssue(a);
  final ib = extractIssue(b);
  final aMissing = ia == null || ia.isEmpty;
  final bMissing = ib == null || ib.isEmpty;
  if (aMissing && bMissing) return 0;
  if (aMissing) return 1;
  if (bMissing) return -1;
  return compareIssueNo(ia, ib);
}

/// 同一期内相位：下注区(0，CHAT/RECEIPT 同相按注单成对) → 封盘预警 → 封盘线 → 竞猜 → 开奖 → 中奖
int _phaseOrder(ChatMessageModel message) {
  return switch (message.type) {
    ChatMessageType.text => 0,
    ChatMessageType.betReceipt => 0,
    ChatMessageType.system => _systemPhase(message),
    ChatMessageType.betListCheck => 4,
    ChatMessageType.resultCard => 5,
    ChatMessageType.winCheck => 6,
    _ => 7,
  };
}

int _systemPhase(ChatMessageModel message) {
  final c = message.content;
  if (c.contains('封盘线') || c.contains('停止战斗')) return 3;
  if (c.contains('封盘')) return 2;
  return 2;
}

bool _isBettingMessage(ChatMessageModel m) =>
    m.type == ChatMessageType.text || m.type == ChatMessageType.betReceipt;

/// 从 `bet-chat-{game}-{orderId}` / `bet-receipt-{game}-{orderId}` 取注单键。
String? _betOrderKey(ChatMessageModel m) {
  final match =
      RegExp(r'^bet-(?:chat|receipt)-[^-]+-(.+)$').firstMatch(m.id.trim());
  if (match == null) return null;
  final raw = match.group(1)?.trim();
  return (raw == null || raw.isEmpty) ? null : raw;
}

int _betTypeRank(ChatMessageModel m) =>
    m.type == ChatMessageType.betReceipt ? 1 : 0;

/// 同相位稳定次序：下注区按注单成对(CHAT→RECEIPT)；其余按时间再按 id。
int _stableTieBreak(ChatMessageModel a, ChatMessageModel b) {
  if (_isBettingMessage(a) && _isBettingMessage(b)) {
    final ao = _betOrderKey(a);
    final bo = _betOrderKey(b);
    if (ao != null && bo != null && ao != bo) {
      final an = int.tryParse(ao);
      final bn = int.tryParse(bo);
      if (an != null && bn != null) return an.compareTo(bn);
      return ao.compareTo(bo);
    }
    if (ao != null && bo != null && ao == bo) {
      final byType = _betTypeRank(a).compareTo(_betTypeRank(b));
      if (byType != 0) return byType;
    }
    // 一边无 orderId：先按时间，再让有 orderId 的相对稳定
    final at = _timeSortKey(a.time);
    final bt = _timeSortKey(b.time);
    if (at != bt) return at.compareTo(bt);
    if (ao != null && bo == null) return -1;
    if (ao == null && bo != null) return 1;
    final byType = _betTypeRank(a).compareTo(_betTypeRank(b));
    if (byType != 0) return byType;
    return a.id.compareTo(b.id);
  }
  final at = _timeSortKey(a.time);
  final bt = _timeSortKey(b.time);
  if (at != bt) return at.compareTo(bt);
  return a.id.compareTo(b.id);
}

int _timeSortKey(String raw) {
  final t = raw.trim();
  if (t.isEmpty) return 0;
  // HH:mm 或 HH:mm:ss
  final m = RegExp(r'^(\d{1,2}):(\d{2})(?::(\d{2}))?').firstMatch(t);
  if (m == null) return 0;
  final h = int.tryParse(m.group(1)!) ?? 0;
  final min = int.tryParse(m.group(2)!) ?? 0;
  final s = int.tryParse(m.group(3) ?? '0') ?? 0;
  return h * 3600 + min * 60 + s;
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
  if (m.type == ChatMessageType.betListCheck &&
      issue != null &&
      issue.isNotEmpty) {
    return 'bet-rank-${issueCompareKey(issue)}';
  }
  if (m.type == ChatMessageType.winCheck &&
      issue != null &&
      issue.isNotEmpty) {
    return 'win-list-${issueCompareKey(issue)}';
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
