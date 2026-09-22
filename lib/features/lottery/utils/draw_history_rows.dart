import 'dart:math' as math;

import '../widgets/history_draw_panel.dart';
import '../../../data/models/chat_message_model.dart';

List<int> parseDrawRanksField(dynamic raw) {
  if (raw is List) {
    return raw
        .map((e) => int.tryParse('$e') ?? 0)
        .where((n) => n > 0)
        .toList(growable: false);
  }
  if (raw is String && raw.isNotEmpty) {
    return raw
        .split(RegExp(r'[,\s]+'))
        .map((e) => int.tryParse(e.trim()) ?? 0)
        .where((n) => n > 0)
        .toList(growable: false);
  }
  return const [];
}

/// 将 `/member/games/{gameType}/history` 响应转为面板行，最新在前。
List<HistoryDrawRow> drawHistoryRowsFromApi(List<Map<String, dynamic>> raw) {
  final rows = <HistoryDrawRow>[];
  final seen = <String>{};
  for (final m in raw) {
    final issue = m['issueNo']?.toString() ?? '';
    final ranks = parseDrawRanksField(m['ranks']);
    if (issue.isEmpty || ranks.isEmpty || seen.contains(issue)) continue;
    seen.add(issue);
    rows.add(
      HistoryDrawRow(
        issue: issue,
        numbers: ranks,
        summary: ranks.length >= 2 ? '${ranks[0] + ranks[1]}' : '',
      ),
    );
  }
  rows.sort((a, b) {
    final ai = int.tryParse(a.issue) ?? 0;
    final bi = int.tryParse(b.issue) ?? 0;
    return bi.compareTo(ai);
  });
  return rows;
}

bool sameIssueNo(String a, String b) {
  if (a == b) return true;
  if (a.isEmpty || b.isEmpty) return false;
  return issueCompareKey(a) == issueCompareKey(b);
}

/// 期号排序/比对：API 长号取后 4 位，与「窄位缩写」对齐，用于相等/先后判断。
/// **不要**拿这个当 UI 展示文案。
int issueCompareKey(String issue) {
  final n = int.tryParse(issue);
  if (n == null) return 0;
  return n >= 10000 ? n % 10000 : n;
}

/// 谁更新。两边都是长号时比完整数字，避免 34134131 的后四位 4131 盖过 34162601。
/// 一边是 4 位缩写时，只和长号的后四位比，相同则视为同一期。
int compareIssueNo(String a, String b) {
  final an = int.tryParse(a.trim()) ?? 0;
  final bn = int.tryParse(b.trim()) ?? 0;
  if (an == bn) return 0;
  if (an <= 0) return -1;
  if (bn <= 0) return 1;
  final aShort = an < 10000;
  final bShort = bn < 10000;
  if (aShort == bShort) return an.compareTo(bn);
  final long = aShort ? bn : an;
  final short = aShort ? an : bn;
  final byTail = short.compareTo(long % 10000);
  if (byTail == 0) return 0;
  return aShort ? byTail : -byTail;
}

/// 期号 +1（全号位数对齐），用于「开奖已写入 previous 但 WS 尚未推下一期」的展示修正。
String incrementIssueNo(String issue) {
  final t = issue.trim();
  if (t.isEmpty) return t;
  final n = int.tryParse(t);
  if (n == null) return t;
  return (n + 1).toString().padLeft(t.length, '0');
}

/// 窄位 UI（下注页顶栏、历史表期号列等）才截后 4 位。
String compactIssueNo(String issue) {
  final t = issue.trim();
  if (t.length > 4) return t.substring(t.length - 4);
  return t;
}

/// 聊天卡 / 彩种列表等：原样展示全号。长短比对请用 [issueCompareKey]。
String displayIssueNo(String issue) => issue.trim();

/// 同逻辑期优先保留更长的原始期号（长号优先于短号）。
String preferFullIssueNo(String a, String b) {
  final ta = a.trim();
  final tb = b.trim();
  if (ta.isEmpty) return tb;
  if (tb.isEmpty) return ta;
  if (issueCompareKey(ta) != issueCompareKey(tb)) {
    // 不同期：交给调用方用 compareKey 判断，这里偏保守保留 a
    return ta;
  }
  return ta.length >= tb.length ? ta : tb;
}

/// 顶栏最新开奖 select 键：仅上期期号/球号/无球时开奖态变化才更新。
String latestDrawWatchKey({
  String? previousIssue,
  required List<int> previousResults,
  required bool isDrawing,
}) {
  final prev = previousIssue != null && previousIssue.trim().isNotEmpty
      ? issueCompareKey(previousIssue)
      : 0;
  final ranks = previousResults.where((n) => n > 0).toList();
  if (ranks.isNotEmpty) return '$prev|${ranks.join(',')}';
  return '$prev|drawing:${isDrawing ? 1 : 0}';
}

/// 聊天页监听用：长/短号归一化，避免 PERIOD_TICK 与 HTTP 格式交替触发重建。
String normalizedGameChatMeta({
  required String currentIssue,
  String? previousIssue,
  required List<int> previousResults,
}) {
  final cur = issueCompareKey(currentIssue);
  final prev = previousIssue != null && previousIssue.isNotEmpty
      ? issueCompareKey(previousIssue)
      : 0;
  return '$cur|$prev|${previousResults.join(',')}';
}

/// WS / HTTP / 缓存统一开奖卡片 id，防止 sync 后 ListView key 抖动。
String drawChatMessageId(String gameId, String issue) {
  return 'draw-$gameId-${issueCompareKey(issue)}';
}

String sealWarnChatMessageId(String gameId, String issue) {
  return 'seal-warn-$gameId-${issueCompareKey(issue)}';
}

String sealedChatMessageId(String gameId, String issue) {
  return 'sealed-$gameId-${issueCompareKey(issue)}';
}

String betRankChatMessageId(String gameId, String issue) {
  return 'bet-rank-$gameId-${issueCompareKey(issue)}';
}

String winListChatMessageId(String gameId, String issue) {
  return 'win-list-$gameId-${issueCompareKey(issue)}';
}

/// 入库统一：id 用 compareKey 去重；展示文案保留服务端全号（不截成 4 位）。
/// 注意：此处不调用 chat_timeline.extractIssue，避免与 chat_timeline 循环 import。
String? _rawIssueOf(ChatMessageModel message) {
  final issue = message.issueNo;
  if (issue != null && issue.isNotEmpty) return issue;
  return RegExp(r'第(\d+)期').firstMatch(message.content)?.group(1);
}

ChatMessageModel normalizeStoredChatMessage(
  ChatMessageModel message, {
  required String gameId,
}) {
  final rawIssue = _rawIssueOf(message);
  if (rawIssue == null || rawIssue.isEmpty) return message;
  final full = rawIssue.trim();
  if (message.type == ChatMessageType.resultCard) {
    final ranks = message.drawRanks;
    return ChatMessageModel(
      id: drawChatMessageId(gameId, rawIssue),
      sender: (message.sender.isEmpty || message.sender == '管理员')
          ? '机器人'
          : message.sender,
      content: '第$full期开奖',
      time: message.time,
      type: ChatMessageType.resultCard,
      isAdmin: true,
      issueNo: full,
      drawRanks: ranks,
    );
  }
  if (message.type == ChatMessageType.system) {
    final isLine = message.content.contains('封盘线') ||
        message.content.contains('停止战斗');
    final isWarn = message.content.contains('封盘');
    if (!isLine && !isWarn) return message;
    return ChatMessageModel(
      id: isLine
          ? sealedChatMessageId(gameId, rawIssue)
          : sealWarnChatMessageId(gameId, rawIssue),
      sender: (message.sender.isEmpty || message.sender == '管理员')
          ? '机器人'
          : message.sender,
      content: message.content,
      time: message.time,
      type: ChatMessageType.system,
      isAdmin: true,
      issueNo: full,
    );
  }
  return message;
}

/// ListView 稳定 key：按期号逻辑键，不跟服务端长号 id 走。
String stableChatItemKey(ChatMessageModel message) {
  final issue = _rawIssueOf(message);
  if (issue != null && issue.isNotEmpty) {
    final key = issueCompareKey(issue);
    if (message.type == ChatMessageType.resultCard) {
      return 'draw-$key';
    }
    if (message.type == ChatMessageType.betListCheck) {
      return 'bet-rank-$key';
    }
    if (message.type == ChatMessageType.winCheck) {
      return 'win-list-$key';
    }
    if (message.type == ChatMessageType.system) {
      if (message.content.contains('封盘线') ||
          message.content.contains('停止战斗')) {
        return 'sealed-$key';
      }
      if (message.content.contains('封盘')) {
        return 'seal-warn-$key';
      }
    }
  }
  return message.id.isNotEmpty
      ? message.id
      : '${message.type.name}-${message.content.hashCode}';
}

/// 缓存时间线是否仍接近当前期（防磁盘旧开奖先闪现）。
/// 必须比完整期号：后四位会把更早的 34134131 当成比 34162601 更新。
bool isDrawTimelineFresh(
  List<ChatMessageModel> timeline,
  String currentIssue, {
  String? previousIssue,
}) {
  final targetIssue = (previousIssue != null && previousIssue.isNotEmpty)
      ? previousIssue
      : currentIssue;
  if (targetIssue.isEmpty) return true;
  final targetKey = int.tryParse(targetIssue.trim()) ?? 0;
  if (targetKey <= 0) return true;
  var maxKey = 0;
  for (final m in timeline) {
    if (m.type != ChatMessageType.resultCard) continue;
    final issue = _rawIssueOf(m);
    if (issue == null || issue.isEmpty) continue;
    final n = int.tryParse(issue.trim()) ?? 0;
    if (n > maxKey) maxKey = n;
  }
  if (maxKey == 0) return false;
  // 聊天至少应包含最近一期开奖；落后超过 1 期则强制 HTTP 回补
  return targetKey - maxKey <= 1;
}

/// 合并 API / WS / 磁盘多路来源，按逻辑期号去重（长短同号合并），最新在前。
List<HistoryDrawRow> mergeHistorySources(Iterable<List<HistoryDrawRow>> sources) {
  final byKey = <int, HistoryDrawRow>{};
  for (final list in sources) {
    for (final row in list) {
      final key = issueCompareKey(row.issue);
      if (key <= 0) continue;
      final existing = byKey[key];
      if (existing == null) {
        byKey[key] = row;
        continue;
      }
      final preferredIssue = preferFullIssueNo(row.issue, existing.issue);
      final betterNums = row.numbers.length > existing.numbers.length
          ? row.numbers
          : existing.numbers;
      byKey[key] = HistoryDrawRow(
        issue: preferredIssue,
        numbers: betterNums,
        summary: betterNums.length >= 2
            ? '${betterNums[0] + betterNums[1]}'
            : existing.summary,
      );
    }
  }
  final merged = byKey.values.toList()
    ..sort((a, b) {
      final ai = issueCompareKey(a.issue);
      final bi = issueCompareKey(b.issue);
      if (ai != bi) return bi.compareTo(ai);
      return b.issue.length.compareTo(a.issue.length);
    });
  return merged;
}

List<ChatMessageModel> drawRowsToResultMessages(
  List<HistoryDrawRow> rows, {
  required String gameId,
}) {
  return rows
      .map(
        (r) {
          final issue = r.issue.trim();
          return ChatMessageModel(
            id: drawChatMessageId(gameId, r.issue),
            sender: '机器人',
            content: '第$issue期开奖',
            time: '',
            type: ChatMessageType.resultCard,
            isAdmin: true,
            issueNo: issue,
            drawRanks: r.numbers,
          );
        },
      )
      .toList(growable: false);
}

List<HistoryDrawRow> mergeDrawHistoryRows({
  required List<HistoryDrawRow> base,
  HistoryDrawRow? liveHead,
  int maxRows = HistoryDrawPanel.maxRows,
}) {
  final merged = <HistoryDrawRow>[];
  if (liveHead != null) merged.add(liveHead);
  for (final row in base) {
    if (liveHead != null && sameIssueNo(row.issue, liveHead.issue)) continue;
    // 最新在前：与上一行断档则停（比完整期号，避免后四位误判）。
    if (merged.isNotEmpty) {
      final prevN = int.tryParse(merged.last.issue.trim()) ?? 0;
      final rowN = int.tryParse(row.issue.trim()) ?? 0;
      if (prevN >= 10000 && rowN >= 10000 && prevN - rowN > 1) break;
      if (prevN > 0 &&
          rowN > 0 &&
          prevN < 10000 &&
          rowN < 10000 &&
          prevN - rowN > 1) {
        break;
      }
    }
    merged.add(row);
    if (merged.length >= maxRows) break;
  }
  return merged;
}
