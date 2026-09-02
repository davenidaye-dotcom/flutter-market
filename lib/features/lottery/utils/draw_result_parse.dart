/// 解析聊天/接口中的开奖文案：第34134056期开奖: 8,4,1,6,3,5,9,10,7,2
class DrawResultParse {
  const DrawResultParse._();

  static ({String? issueNo, List<int> ranks}) parse(String content) {
    final trimmed = content.trim();
    if (trimmed.isEmpty) {
      return (issueNo: null, ranks: const <int>[]);
    }
    final match = RegExp(
      r'第\s*(\d+)\s*期\s*开奖[:：]?\s*(.*)$',
      caseSensitive: false,
    ).firstMatch(trimmed);
    if (match != null) {
      return (
        issueNo: match.group(1),
        ranks: _parseRanks(match.group(2) ?? ''),
      );
    }
    return (issueNo: null, ranks: _parseRanks(trimmed));
  }

  static List<int> _parseRanks(String raw) {
    if (raw.isEmpty) return const [];
    return raw
        .split(RegExp(r'[,，\s|]+'))
        .map((s) => int.tryParse(s.trim()))
        .whereType<int>()
        .where((n) => n > 0)
        .toList();
  }
}
