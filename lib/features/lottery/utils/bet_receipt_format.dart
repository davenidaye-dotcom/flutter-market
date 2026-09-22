/// 机器人投注确认 / 下单排名 / 中奖核对文案，对齐：`亚军[ 6/50 ]`
String formatBetReceiptText({
  String mention = '',
  String issue = '',
  dynamic total,
  List<dynamic>? items,
  String fallbackContent = '',
}) {
  final lines = <String>[];
  final m = mention.trim();
  if (m.isNotEmpty && m != '机器人') lines.add('@$m');
  final iss = issue.trim();
  if (iss.isNotEmpty) lines.add('$iss期投注成功!');
  if (total != null && '$total'.trim().isNotEmpty) {
    lines.add('总金额:$total');
  }
  var hasItem = false;
  if (items != null) {
    for (final raw in items) {
      if (raw is! Map) continue;
      final line = formatReceiptItemLine(Map<String, dynamic>.from(raw));
      if (line.isEmpty) continue;
      lines.add(line);
      hasItem = true;
    }
  }
  if (!hasItem && fallbackContent.trim().isNotEmpty) {
    lines.add(fallbackContent.trim());
  }
  return lines.join('\n');
}

String formatReceiptItemLine(Map<String, dynamic> raw) {
  final name = '${raw['playName'] ?? raw['playCode'] ?? ''}'.trim();
  final detail =
      '${raw['text'] ?? raw['content'] ?? raw['amount'] ?? ''}'.trim();
  if (name.isEmpty && detail.isEmpty) return '';
  if (name.isEmpty) return detail;
  if (detail.isEmpty) return name;
  if (detail.startsWith('[')) return '$name$detail';
  return '$name[ $detail ]';
}

/// 开奖后 `WIN_LIST`：优先后端 content，否则用 winners 组装。
String formatWinCheckText({
  required String issue,
  String? content,
  List<WinCheckEntry>? winners,
}) {
  final ready = (content ?? '').trim();
  if (ready.isNotEmpty) return ready;
  final lines = <String>['$issue期已开奖', '中奖列表核对', '-------------------'];
  final list = winners ?? const <WinCheckEntry>[];
  if (list.isEmpty) {
    lines.add('本期暂无中奖名单，请再接再厉。');
    return lines.join('\n');
  }
  for (final w in list) {
    lines.add('[${w.name}]中奖金额:${w.winAmount}');
    for (final play in w.plays) {
      if (play.isNotEmpty) lines.add(play);
    }
    lines.add('输赢:${w.winLoss}');
  }
  return lines.join('\n');
}

/// 封盘后 `BET_RANK`：优先后端 content。
String formatBetRankText({
  required String issue,
  String? content,
  List<dynamic>? rankings,
}) {
  final ready = (content ?? '').trim();
  if (ready.isNotEmpty) return ready;
  final lines = <String>['$issue期下单量排名', '-------------------'];
  if (rankings != null) {
    for (final raw in rankings) {
      if (raw is! Map) continue;
      final m = Map<String, dynamic>.from(raw);
      final rank = m['rank'] ?? '';
      final name = (m['nickname'] ?? m['displayName'] ?? '会员').toString();
      final amount = m['amount'] ?? '';
      lines.add('$rank. [$name] $amount');
    }
  }
  if (lines.length == 2) lines.add('暂无下注');
  return lines.join('\n');
}

/// 兼容旧调用名 → [formatBetRankText]
String formatBetListCheckText({
  required String issue,
  String? content,
  List<dynamic>? accounts,
}) {
  return formatBetRankText(issue: issue, content: content, rankings: accounts);
}

class WinCheckEntry {
  const WinCheckEntry({
    required this.name,
    required this.winAmount,
    required this.winLoss,
    this.plays = const [],
  });

  final String name;
  final Object winAmount;
  final Object winLoss;
  final List<String> plays;
}

List<WinCheckEntry> parseWinCheckWinners(List<dynamic>? winners) {
  if (winners == null) return const [];
  final out = <WinCheckEntry>[];
  for (final raw in winners) {
    if (raw is! Map) continue;
    final m = Map<String, dynamic>.from(raw);
    final name = (m['nickname'] ?? m['senderName'] ?? m['displayName'] ?? '会员')
        .toString()
        .trim();
    final plays = <String>[];
    final items = m['items'];
    if (items is List) {
      for (final item in items) {
        if (item is! Map) continue;
        final line = formatReceiptItemLine(Map<String, dynamic>.from(item));
        if (line.isNotEmpty) plays.add(line);
      }
    }
    out.add(WinCheckEntry(
      name: name.isEmpty ? '会员' : name,
      winAmount: m['winAmount'] ?? 0,
      winLoss: m['winLoss'] ?? 0,
      plays: plays,
    ));
  }
  return out;
}
