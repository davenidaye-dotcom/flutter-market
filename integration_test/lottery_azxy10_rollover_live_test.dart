import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/support/regression/live_rollover_harness.dart';
import '../test/support/regression/live_test_env.dart';
import '../test/support/regression/live_test_harness.dart';

/// AZXY10 / 任意彩种换期 UI 真实联调：开奖中 → 球号露出 → 距封盘，期号单调。
///
/// ```bash
/// flutter test integration_test/lottery_azxy10_rollover_live_test.dart \
///   --dart-define=RUN_LIVE_TESTS=1 \
///   --dart-define=LIVE_TEST_GAME_ID=AZXY10 \
///   --dart-define=LIVE_TEST_ROLLOVER_MAX_SEC=330
/// ```
@Tags(['live'])
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('AZXY10 rollover UI (真实 HTTP+WS+Provider)', () {
    test(
      '换期经历开奖中且 currentIssue > previousIssue',
      () async {
        if (!LiveTestEnv.enabled) return;
        final session = await LiveTestHarness.bootstrapRoomSession();
        try {
          await LiveRolloverHarness.assertRolloverDrawingAndIssueConsistency(
            container: session.container,
            roomCode: session.roomCode,
            gameId: session.gameId,
            maxWait: Duration(seconds: LiveTestEnv.rolloverMaxWaitSeconds),
          );
        } finally {
          LiveTestHarness.dispose(session.container);
        }
      },
      skip: !LiveTestEnv.enabled ? LiveTestEnv.skipReason : false,
    );
  });
}
