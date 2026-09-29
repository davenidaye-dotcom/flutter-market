/// 特码=TM+POS，两面-龙虎=LM+DT。存库仍分 playCode，界面合并成一行。
class MergedPlayRow {
  const MergedPlayRow({
    required this.name,
    required this.codes,
    required this.shown,
  });

  final String name;
  final List<String> codes;
  final Map<String, dynamic> shown;
}

List<MergedPlayRow> mergePlayOddsRows(
  List<Map<String, dynamic>> items, {
  String codeKey = 'playCode',
  String nameKey = 'playName',
}) {
  Map<String, dynamic>? pick(String code) {
    for (final it in items) {
      if ((it[codeKey] ?? '').toString().toUpperCase() == code) return it;
    }
    return null;
  }

  bool used(String code) {
    final u = code.toUpperCase();
    return u == 'TM' || u == 'POS' || u == 'LM' || u == 'DT';
  }

  final rows = <MergedPlayRow>[];
  final tm = pick('TM');
  final pos = pick('POS');
  if (tm != null || pos != null) {
    final shown = tm ?? pos!;
    rows.add(MergedPlayRow(
      name: '特码',
      codes: [
        if (tm != null) 'TM',
        if (pos != null) 'POS',
      ],
      shown: shown,
    ));
  }
  final lm = pick('LM');
  final dt = pick('DT');
  if (lm != null || dt != null) {
    final shown = lm ?? dt!;
    rows.add(MergedPlayRow(
      name: '两面-龙虎',
      codes: [
        if (lm != null) 'LM',
        if (dt != null) 'DT',
      ],
      shown: shown,
    ));
  }
  const order = [
    'GYH_DS',
    'GYH_BIG',
    'GYH_EVEN',
    'GYH_XS',
    'GYH_SMALL',
    'GYH_ODD',
    'GYH_3',
    'GYH_5',
    'GYH_7',
    'GYH_9',
    'GYH_11',
  ];
  final rest = items.where((it) => !used((it[codeKey] ?? '').toString())).toList()
    ..sort((a, b) {
      final ca = (a[codeKey] ?? '').toString().toUpperCase();
      final cb = (b[codeKey] ?? '').toString().toUpperCase();
      final ia = order.indexOf(ca);
      final ib = order.indexOf(cb);
      final ra = ia >= 0 ? ia : (ca.startsWith('GYH') ? 50 : 80);
      final rb = ib >= 0 ? ib : (cb.startsWith('GYH') ? 50 : 80);
      return ra.compareTo(rb);
    });
  for (final it in rest) {
    rows.add(MergedPlayRow(
      name: (it[nameKey] ?? it[codeKey] ?? '').toString(),
      codes: [(it[codeKey] ?? '').toString()],
      shown: it,
    ));
  }
  return rows;
}
