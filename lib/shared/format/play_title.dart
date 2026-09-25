/// 注单行名次。特码是冠军位的号码；名次玩法按位显示。
String rankBetTitle(Map<dynamic, dynamic> row) {
  final title = '${row['title'] ?? '—'}'.trim();
  final code = '${row['playCode'] ?? ''}'.trim().toUpperCase();
  final amount = _amountTail(title);
  final tail = amount.isEmpty ? '' : ' $amount';

  if (code.startsWith('TM-')) {
    return '冠军 [${code.substring(3)}]$tail';
  }
  if (code.startsWith('POS-')) {
    final parts = code.split('-');
    if (parts.length >= 3) {
      final pos = int.tryParse(parts[1]) ?? 0;
      return '${_rankTitle(pos)} [${parts[2]}]$tail';
    }
  }

  final tm = RegExp(r'^特码-(\d+)\s*[【\[]([^】\]]+)[】\]]\s*(.*)$').firstMatch(title);
  if (tm != null) {
    final rest = (tm.group(3) ?? '').trim();
    return rest.isEmpty ? '冠军 [${tm.group(2)}]' : '冠军 [${tm.group(2)}] $rest';
  }
  final pos = RegExp(r'^第(\d+)名\s*[【\[]([^】\]]+)[】\]]\s*(.*)$').firstMatch(title);
  if (pos != null) {
    final rank = int.tryParse(pos.group(1) ?? '') ?? 0;
    final rest = (pos.group(3) ?? '').trim();
    final name = _rankTitle(rank);
    return rest.isEmpty ? '$name [${pos.group(2)}]' : '$name [${pos.group(2)}] $rest';
  }
  return title;
}

String _rankTitle(int position) {
  const names = ['', '冠军', '亚军', '第三名', '第四名', '第五名', '第六名', '第七名', '第八名', '第九名', '第十名'];
  if (position >= 1 && position < names.length) return names[position];
  return '第$position名';
}

String _amountTail(String title) {
  return RegExp(r'(\d+(?:\.\d+)?)\s*$').firstMatch(title)?.group(1) ?? '';
}
