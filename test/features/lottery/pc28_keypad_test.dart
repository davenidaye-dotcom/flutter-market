import 'package:flutter_test/flutter_test.dart';
import 'package:letou_app/features/lottery/widgets/bet_keypad_panel.dart';

void main() {
  test('左键是总和，右边斜杠还在', () {
    expect(BetKeypadPanel.pc28Grid.last, ['双', '总和', '0', '/', '绿波']);
  });

  test('总和能贴在大的两侧，贴过一次就不再放', () {
    expect(BetKeypadPanel.isPc28MutexBlocked('', '总和'), isFalse);
    expect(BetKeypadPanel.isPc28MutexBlocked('大', '总和'), isFalse);
    expect(BetKeypadPanel.isPc28MutexBlocked('总和', '大'), isFalse);
    expect(BetKeypadPanel.isPc28MutexBlocked('总和', '/'), isTrue);
    expect(BetKeypadPanel.isPc28MutexBlocked('总和', '红波'), isTrue);
    expect(BetKeypadPanel.isPc28MutexBlocked('总和大', '小'), isTrue);
    expect(BetKeypadPanel.isPc28MutexBlocked('总和大', '大'), isTrue);
    expect(BetKeypadPanel.isPc28MutexBlocked('大', '大'), isTrue);
    expect(BetKeypadPanel.isPc28MutexBlocked('大总和', '总和'), isTrue);
    expect(BetKeypadPanel.isPc28MutexBlocked('红波', '总和'), isTrue);
  });

  test('斜杠后面的大小单双下在球上，号码和大小不能混', () {
    expect(BetKeypadPanel.isPc28MutexBlocked('1/', '大'), isFalse);
    expect(BetKeypadPanel.isPc28MutexBlocked('123/', '小'), isFalse);
    expect(BetKeypadPanel.isPc28MutexBlocked('1/大', '小'), isFalse);
    expect(BetKeypadPanel.isPc28MutexBlocked('1/大', '5'), isTrue);
    expect(BetKeypadPanel.isPc28MutexBlocked('1/5', '大'), isTrue);
    expect(BetKeypadPanel.isPc28MutexBlocked('1/', '总和'), isTrue);
    expect(BetKeypadPanel.isPc28MutexBlocked('1/5', '/'), isFalse);
  });
}
