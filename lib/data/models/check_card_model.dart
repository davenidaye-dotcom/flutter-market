/// BET_RANK / WIN_LIST 核对卡的结构化数据。公共卡只带前 20 行 + total，
/// 自己的名次由历史 `self` 或 WS `CHECK_SELF` 补上。
class CheckRow {
  const CheckRow(this.raw);

  final Map<String, dynamic> raw;

  int? get rank => int.tryParse('${raw['rank']}');

  String get accountId => '${raw['accountId'] ?? ''}'.trim();

  String get name => ('${raw['nickname'] ?? raw['senderName'] ?? raw['displayName'] ?? '会员'}')
      .trim();

  Object? get amount => raw['amount'];

  Object get winAmount => raw['winAmount'] ?? 0;

  Object get winLoss => raw['winLoss'] ?? 0;

  /// 同一玩家：优先 accountId，其次名次，最后昵称+金额。
  bool sameAs(CheckRow other) {
    if (accountId.isNotEmpty && other.accountId.isNotEmpty) {
      return accountId == other.accountId;
    }
    final a = rank;
    final b = other.rank;
    if (a != null && b != null) return a == b;
    return name == other.name &&
        '$amount' == '${other.amount}' &&
        '$winAmount' == '${other.winAmount}';
  }
}

class CheckCardData {
  const CheckCardData({
    required this.isWin,
    this.header = '',
    this.rows = const [],
    this.total = 0,
    this.selfRank,
    this.selfRow,
    this.lost = false,
  });

  /// true：WIN_LIST；false：BET_RANK
  final bool isWin;

  /// 后端文案里分隔线以上的标题行，缺省时按类型补默认标题。
  final String header;
  final List<CheckRow> rows;
  final int total;
  final int? selfRank;
  final CheckRow? selfRow;
  final bool lost;

  bool get hasSelf => selfRow != null || lost;

  CheckCardData withSelf({int? rank, CheckRow? row, bool lost = false}) {
    return CheckCardData(
      isWin: isWin,
      header: header,
      rows: rows,
      total: total,
      selfRank: rank,
      selfRow: row,
      lost: lost,
    );
  }

  /// 一张卡是否已经有（含自己的）更全信息。
  bool richerThan(CheckCardData other) {
    if (hasSelf != other.hasSelf) return hasSelf;
    return rows.length > other.rows.length;
  }

  Map<String, dynamic> toJson() => {
        'w': isWin,
        if (header.isNotEmpty) 'h': header,
        'r': [for (final r in rows) r.raw],
        'n': total,
        if (selfRank != null) 'sr': selfRank,
        if (selfRow != null) 'sw': selfRow!.raw,
        if (lost) 'l': true,
      };

  static CheckCardData? fromJson(Object? json) {
    if (json is! Map) return null;
    final rowsRaw = json['r'];
    final selfRaw = json['sw'];
    return CheckCardData(
      isWin: json['w'] == true,
      header: json['h']?.toString() ?? '',
      rows: rowsRaw is List
          ? [
              for (final e in rowsRaw)
                if (e is Map) CheckRow(Map<String, dynamic>.from(e)),
            ]
          : const [],
      total: int.tryParse('${json['n']}') ?? 0,
      selfRank: int.tryParse('${json['sr']}'),
      selfRow: selfRaw is Map ? CheckRow(Map<String, dynamic>.from(selfRaw)) : null,
      lost: json['l'] == true,
    );
  }
}
