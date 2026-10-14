import 'package:flutter_test/flutter_test.dart';
import 'package:letou_app/data/models/check_card_model.dart';
import 'package:letou_app/features/lottery/utils/check_card_format.dart';

Map<String, dynamic> _rank(int rank, String name, num amount, {String? aid}) => {
      'rank': rank,
      'nickname': name,
      'amount': amount,
      if (aid != null) 'accountId': aid,
    };

void main() {
  const issue = '34163647';

  test('BET_RANK：自己置顶并带名次，前 20 行去掉自己，尾部补"另有 N 位"', () {
    final rows = [for (var i = 1; i <= 20; i++) _rank(i, 'u$i', 1000 - i, aid: '$i')];
    final card = parseCheckCard({
      'rankings': rows,
      'total': 120,
      'self': {'rank': 3, 'row': rows[2]},
    }, isWin: false);
    final lines = composeCheckCardText(data: card, issue: issue).split('\n');

    expect(lines[0], '$issue期已封盘');
    // 标题 3 行之后第一行是自己
    expect(lines[3], startsWith('第3名 [u3]'));
    // 自己只出现一次
    expect(lines.where((l) => l.contains('[u3]')).length, 1);
    expect(lines.where((l) => l.startsWith('1. [u1]')).length, 1);
    // 20 行里包含自己：N = 120 - 20
    expect(lines.last, '另有 100 位未显示');
  });

  test('BET_RANK：自己不在前 20 时 N 再减 1', () {
    final rows = [for (var i = 1; i <= 20; i++) _rank(i, 'u$i', 1000 - i, aid: '$i')];
    final card = parseCheckCard({
      'rankings': rows,
      'total': 50,
      'self': {'rank': 33, 'row': _rank(33, 'me', 5, aid: '999')},
    }, isWin: false);
    final lines = composeCheckCardText(data: card, issue: issue).split('\n');
    expect(lines[3], startsWith('第33名 [me]'));
    expect(lines.last, '另有 29 位未显示');
  });

  test('WIN_LIST：未中奖置顶，且 total<=20 时不出现尾行', () {
    final card = parseCheckCard({
      'winners': [
        {'nickname': 'w1', 'winAmount': 100, 'winLoss': 50},
      ],
      'total': 1,
      'lost': true,
    }, isWin: true);
    final lines = composeCheckCardText(data: card, issue: issue).split('\n');
    expect(lines[3], '本期未中奖');
    expect(lines.any((l) => l.contains('[w1]')), isTrue);
    expect(lines.any((l) => l.contains('另有')), isFalse);
  });

  test('CHECK_SELF 晚到：withSelf 之后重新拼装，自己置顶', () {
    final base = parseCheckCard({
      'rankings': [_rank(1, 'a', 10), _rank(2, 'b', 5)],
      'total': 2,
    }, isWin: false);
    final withSelf = base.withSelf(rank: 2, row: CheckRow(_rank(2, 'b', 5)));
    final lines = composeCheckCardText(data: withSelf, issue: issue).split('\n');
    expect(lines[3], startsWith('第2名 [b]'));
    expect(lines.where((l) => l.contains('[b]')).length, 1);
  });

  test('结构化数据可 JSON 往返', () {
    final card = parseCheckCard({
      'winners': [
        {'nickname': 'w1', 'winAmount': 100, 'winLoss': 50},
      ],
      'total': 9,
      'self': {'rank': 4, 'row': {'nickname': 'me', 'winAmount': 1, 'winLoss': 1}},
    }, isWin: true);
    final back = CheckCardData.fromJson(card.toJson())!;
    expect(composeCheckCardText(data: back, issue: issue),
        composeCheckCardText(data: card, issue: issue));
  });
}
