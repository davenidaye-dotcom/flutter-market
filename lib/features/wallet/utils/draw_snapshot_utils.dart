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
    case 'COMMISSION':
      return '代理佣金';
    case 'UP':
    case 'OWNER_CREDIT_UP':
      return '上分';
    case 'DOWN':
    case 'OWNER_CREDIT_DOWN':
      return '下分';
    case 'TOTALUP':
      return '总上分';
    case 'TOTALDOWN':
      return '总下分';
    case 'TOTALBET':
    case 'TOTALTURNOVER':
      return '总流水';
    case 'TOTALBONUS':
      return '总派彩';
    case 'TOTALWINLOSS':
      return '总输赢';
    case 'TOTALREBATE':
      return '总回水';
    case 'TOTALORDERS':
      return '总笔数';
    case 'TOTALBALANCE':
      return '总积分';
    case 'GAMERESULT':
      return '庄家结果';
    case 'PLAYERRESULT':
      return '玩家结果';
    case 'PENDING':
      return '待开奖';
    case 'SETTLED':
      return '已结算';
    case 'CANCELLED':
    case 'CANCEL':
    case 'VOID':
      return '已取消';
    default:
      return type;
  }
}

String betStatusLabel(String status) {
  switch (status.toUpperCase()) {
    case 'WIN':
      return '中奖';
    case 'LOSE':
      return '未中';
    case 'SETTLING':
      return '结算中';
    case 'PENDING':
      return '待开奖';
    case 'CANCEL':
      return '已取消';
    case 'VOID':
      return '已作废';
    default:
      return status;
  }
}
