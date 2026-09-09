/// 解析注单/账变冗余字段 drawRanks（逗号分隔）。
List<int> parseDrawRanks(dynamic raw) {
  if (raw == null) return const [];
  final text = '$raw'.trim();
  if (text.isEmpty) return const [];
  final out = <int>[];
  for (final part in text.split(',')) {
    final n = int.tryParse(part.trim());
    if (n != null) out.add(n);
  }
  return out;
}

String? pickDrawRanks(Map<String, dynamic> row) {
  final raw = row['drawRanks'] ?? row['draw_ranks'];
  if (raw == null) return null;
  final text = '$raw'.trim();
  return text.isEmpty ? null : text;
}

int? pickSumGy(Map<String, dynamic> row) {
  final raw = row['sumGy'] ?? row['sum_gy'];
  if (raw is int) return raw;
  return int.tryParse('$raw');
}

String issueTail(String issue) {
  final t = issue.trim();
  if (t.length <= 4) return t;
  return t.substring(t.length - 4);
}

String ledgerChangeLabel(String type) {
  switch (type.toUpperCase()) {
    case 'BET':
      return '下注';
    case 'BET_CANCEL':
      return '取消下注';
    case 'WIN':
      return '中奖派彩';
    case 'REBATE':
      return '回水';
    case 'REDPACK':
      return '红包';
    case 'UP':
      return '上分';
    case 'DOWN':
      return '下分';
    default:
      return type;
  }
}

String betStatusLabel(String status) {
  switch (status.toUpperCase()) {
    case 'WIN':
      return 'WIN';
    case 'LOSE':
      return 'LOSE';
    case 'SETTLING':
      return '结算中';
    case 'PENDING':
      return '待开';
    case 'CANCEL':
      return '已取消';
    default:
      return status;
  }
}
