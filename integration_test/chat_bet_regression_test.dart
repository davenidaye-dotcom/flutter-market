import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/support/regression/chat_bet_test_harness.dart';

/// 模拟器/真机 UI 回归：与 [test/chat_bet_ui_regression_test.dart] 同套断言。
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await ChatBetRegressionHarness.prepareSession();
  });

  group('ChatBetPage 模拟器回归', () {
    testWidgets('HTTP+WS 聊天显示正常', (tester) async {
      await ChatBetRegressionHarness.pumpUntilChatReady(tester);
      await ChatBetRegressionHarness.injectWsSequence(tester);
      await tester.pumpAndSettle(const Duration(seconds: 2));

      expect(find.textContaining('第4730期'), findsWidgets);
      expect(find.text('大100'), findsOneWidget);
      expect(find.text('小50'), findsOneWidget);
      expect(find.textContaining('停止战斗'), findsWidgets);

      await ChatBetRegressionHarness.flushPendingTimers(tester);
    });
  });
}
