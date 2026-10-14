import '../../../data/models/check_card_model.dart';
import '../../../shared/format/display_number.dart';
import 'bet_receipt_format.dart';

/// 从后端 text/content 里取分隔线以上的标题行（最多 4 行内出现 `---`/`===` 才认）。
String checkCardHeaderFromContent(String content) {
  final lines = content.split('\n');
  for (var i = 0; i < lines.length && i < 4; i++) {
    final t = lines[i].trim();
    if (t.startsWith('---') || t.startsWith('===')) {
      return lines.sublist(0, i + 1).join('\n').trim();
    }
  }
  return '';
}

/// 公共 payload / 历史 item → 结构化卡。`self` 为历史自带，WS 的 CHECK_SELF 另行 [CheckCardData.withSelf]。
CheckCardData parseCheckCard(
  Map<String, dynamic> m, {
  required bool isWin,
}) {
  final rowsRaw = m[isWin ? 'winners' : 'rankings'];
  final rows = <CheckRow>[
    if (rowsRaw is List)
      for (final e in rowsRaw)
        if (e is Map) CheckRow(Map<String, dynamic>.from(e)),
  ];
  final self = m['self'];
  CheckRow? selfRow;
  int? selfRank;
  if (self is Map) {
    final row = self['row'];
    if (row is Map) selfRow = CheckRow(Map<String, dynamic>.from(row));
    selfRank = int.tryParse('${self['rank']}');
  }
  final content = '${m['content'] ?? m['text'] ?? ''}';
  return CheckCardData(
    isWin: isWin,
    header: checkCardHeaderFromContent(content),
    rows: rows,
    total: int.tryParse('${m['total']}') ?? rows.length,
    selfRank: selfRank,
    selfRow: selfRow,
    lost: isWin && m['lost'] == true,
  );
}

/// 按结构化行拼卡片正文：自己置顶(第N名 / 本期未中奖) → 前 20 行(去掉自己) → 另有 N 位未显示。
String composeCheckCardText({
  required CheckCardData data,
  required String issue,
}) {
  final lines = <String>[];
  final header = data.header.trim();
  if (header.isNotEmpty) {
    lines.add(header);
  } else if (data.isWin) {
    lines.addAll(['$issue期已开奖', '中奖列表核对', '-------------------']);
  } else {
    lines.addAll(['$issue期已封盘', '竞猜列表核对', '-------------------']);
  }

  final selfRow = data.selfRow;
  var selfInTop = false;
  if (selfRow != null) {
    selfInTop = data.rows.any(selfRow.sameAs);
    final rank = data.selfRank ?? selfRow.rank;
    lines.addAll(_rowLines(selfRow, data.isWin, selfRank: rank));
  } else if (data.lost) {
    lines.add('本期未中奖');
  }

  for (final row in data.rows) {
    if (selfRow != null && selfRow.sameAs(row)) continue;
    lines.addAll(_rowLines(row, data.isWin));
  }
  if (data.rows.isEmpty && selfRow == null && !data.lost) {
    lines.add(data.isWin ? '本期暂无中奖名单，再接再厉!' : '暂无下注');
  }

  final selfOutside = selfRow != null && !selfInTop;
  final hidden = data.total - data.rows.length - (selfOutside ? 1 : 0);
  if (hidden > 0) lines.add('另有 $hidden 位未显示');
  return lines.join('\n');
}

List<String> _rowLines(CheckRow row, bool isWin, {int? selfRank}) {
  if (isWin) {
    final out = <String>[];
    if (selfRank != null && selfRank > 0) out.add('第$selfRank名');
    out.add('[${row.name}]中奖金额:${displayNumber(row.winAmount)}');
    final items = row.raw['items'];
    if (items is List) {
      for (final item in items) {
        if (item is! Map) continue;
        final line = formatReceiptItemLine(Map<String, dynamic>.from(item));
        if (line.isNotEmpty) out.add(line);
      }
    }
    out.add('输赢:${displayNumber(row.winLoss)}');
    return out;
  }
  final amount = row.amount;
  final amountText =
      amount == null || '$amount'.trim().isEmpty ? '' : displayNumber(amount);
  if (selfRank != null && selfRank > 0) {
    return ['第$selfRank名 [${row.name}] $amountText'.trimRight()];
  }
  return ['${row.rank ?? ''}. [${row.name}] $amountText'.trimRight()];
}
