import 'package:flutter_test/flutter_test.dart';

import 'support/regression/chat_bet_test_harness.dart';

/// 聊天下注页 UI 回归（VM / 模拟器均可跑）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await ChatBetRegressionHarness.prepareSession();
  });

  group('ChatBetPage UI 回归', () {
    testWidgets('HTTP 加载后显示开奖卡片与用户下注', (tester) async {
      await ChatBetRegressionHarness.pumpUntilChatReady(tester);

      expect(find.textContaining('第4730期'), findsWidgets);
      expect(find.text('大100'), findsOneWidget);
      expect(find.text('开奖结果'), findsWidgets);
      expect(find.textContaining('停止战斗'), findsWidgets);

      await ChatBetRegressionHarness.flushPendingTimers(tester);
    });

    testWidgets('WS 推送后聊天更新且不重复刷屏封盘', (tester) async {
      await ChatBetRegressionHarness.pumpUntilChatReady(tester);
      await ChatBetRegressionHarness.injectWsSequence(tester);
      await tester.pumpAndSettle(const Duration(milliseconds: 800));

      expect(find.text('小50'), findsOneWidget);
      expect(
        find.textContaining('停止战斗').evaluate().length,
        lessThanOrEqualTo(3),
      );

      await ChatBetRegressionHarness.flushPendingTimers(tester);
    });

    testWidgets('顶栏期号可见', (tester) async {
      await ChatBetRegressionHarness.pumpUntilChatReady(tester);
      expect(find.text('4731'), findsWidgets);
      await ChatBetRegressionHarness.flushPendingTimers(tester);
    });
  });
}
