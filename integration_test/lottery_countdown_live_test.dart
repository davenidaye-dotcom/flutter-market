import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/support/regression/live_test_env.dart';
import '../test/support/regression/live_test_harness.dart';

/// 真实联调（需网络）：登录测试服 → 进房 → 连 WS → 监控倒计时。
///
/// 运行: scripts/run_live_countdown_test.ps1
/// 或: flutter test integration_test/lottery_countdown_live_test.dart --dart-define=RUN_LIVE_TESTS=1
@Tags(['live'])
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('lottery countdown live (真实 HTTP+WS)', () {
    test(
      '进房后倒计时单调递减，禁止 75↔70 回跳',
      () async {
        if (!LiveTestEnv.enabled) return;
        final session = await LiveTestHarness.bootstrapRoomSession();
        try {
          await LiveTestHarness.assertCountdownMonotonic(
            container: session.container,
            roomCode: session.roomCode,
            gameId: session.gameId,
            duration: Duration(seconds: LiveTestEnv.sampleSeconds),
          );
        } finally {
          LiveTestHarness.dispose(session.container);
        }
      },
      skip: !LiveTestEnv.enabled ? LiveTestEnv.skipReason : false,
    );

    test(
      '历史房间再进 ensureLoaded 后倒计时仍单调',
      () async {
        if (!LiveTestEnv.enabled) return;
        final session = await LiveTestHarness.bootstrapRoomSession();
        try {
          await LiveTestHarness.assertReenterMonotonic(
            container: session.container,
            roomCode: session.roomCode,
            gameId: session.gameId,
          );
        } finally {
          LiveTestHarness.dispose(session.container);
        }
      },
      skip: !LiveTestEnv.enabled ? LiveTestEnv.skipReason : false,
    );
  });
}
