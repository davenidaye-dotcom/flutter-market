import 'package:flutter_test/flutter_test.dart';
import 'package:letou_app/shared/widgets/score_apply_sheet.dart';

void main() {
  test('只拼数字和一位小数点，挡掉其它输入', () {
    var amount = '';
    for (final key in ['1', '0', '0']) {
      amount = applyScoreKey(amount, key);
    }
    expect(amount, '100');

    amount = applyScoreKey(amount, '.');
    amount = applyScoreKey(amount, '.');
    amount = applyScoreKey(amount, '5');
    amount = applyScoreKey(amount, '6');
    amount = applyScoreKey(amount, '7');
    expect(amount, '100.56');

    amount = applyScoreKey(amount, '上');
    amount = applyScoreKey(amount, 'a');
    amount = applyScoreKey(amount, '-');
    expect(amount, '100.56');

    amount = applyScoreKey(amount, 'del');
    expect(amount, '100.5');
  });

  test('前导 0 被下一位替换，整数最多 8 位', () {
    expect(applyScoreKey('0', '8'), '8');
    expect(applyScoreKey('', '.'), '0.');
    var amount = '';
    for (var i = 0; i < 10; i++) {
      amount = applyScoreKey(amount, '9');
    }
    expect(amount, '99999999');
  });

  test('空、0、只有小数点不能提交', () {
    expect(scoreAmountSubmittable(''), isFalse);
    expect(scoreAmountSubmittable('0'), isFalse);
    expect(scoreAmountSubmittable('0.'), isFalse);
    expect(scoreAmountSubmittable('0.00'), isFalse);
    expect(scoreAmountSubmittable('.'), isFalse);
    expect(scoreAmountSubmittable('2.7'), isTrue);
    expect(scoreAmountSubmittable('100'), isTrue);
  });
}
