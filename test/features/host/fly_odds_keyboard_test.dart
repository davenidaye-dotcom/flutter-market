import 'package:flutter_test/flutter_test.dart';
import 'package:letou_app/shared/widgets/keyboard_list_reveal.dart';

void main() {
  test('列表底部空白只补键盘盖进列表的高度', () {
    expect(
      keyboardListCover(keyboard: 320, safeBottom: 34, barHeight: 68),
      226,
    );
    expect(keyboardListCover(keyboard: 0, safeBottom: 34, barHeight: 68), 0);
    expect(keyboardListCover(keyboard: 80, safeBottom: 34, barHeight: 68), 0);
  });

  test('已经在键盘上方的行不再滚', () {
    expect(keyboardRevealDelta(rowBottom: 480, keyboardTop: 500), 0);
    expect(keyboardRevealDelta(rowBottom: 700, keyboardTop: 500), 208);
  });
}
