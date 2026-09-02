/// 联调测试环境配置（真实 HTTP + WS，非 mock）。
///
/// 运行示例：
/// ```bash
/// flutter test test/features/lottery/lottery_countdown_live_test.dart \
///   --dart-define=RUN_LIVE_TESTS=1 \
///   --dart-define=APP_ENV=test
/// ```
///
/// 可选覆盖账号/房间：
/// `--dart-define=LIVE_TEST_USER=player01`
/// `--dart-define=LIVE_TEST_PASSWORD=Pass1234`
/// `--dart-define=LIVE_TEST_ROOM_CODE=679010`
/// `--dart-define=LIVE_TEST_GAME_ID=JS_SC`
/// `--dart-define=LIVE_TEST_SAMPLE_SECONDS=20`
abstract final class LiveTestEnv {
  static const _runFlag =
      String.fromEnvironment('RUN_LIVE_TESTS', defaultValue: '');

  static bool get enabled {
    final v = _runFlag.toLowerCase();
    return v == '1' || v == 'true' || v == 'yes';
  }

  static const username =
      String.fromEnvironment('LIVE_TEST_USER', defaultValue: 'player01');

  static const password =
      String.fromEnvironment('LIVE_TEST_PASSWORD', defaultValue: 'Pass1234');

  static const roomCode =
      String.fromEnvironment('LIVE_TEST_ROOM_CODE', defaultValue: '679010');

  static const gameId =
      String.fromEnvironment('LIVE_TEST_GAME_ID', defaultValue: 'JS_SC');

  static const sampleSeconds =
      int.fromEnvironment('LIVE_TEST_SAMPLE_SECONDS', defaultValue: 20);

  static const rolloverMaxWaitSeconds =
      int.fromEnvironment('LIVE_TEST_ROLLOVER_MAX_SEC', defaultValue: 330);

  static String get skipReason =>
      '未启用联调：加 --dart-define=RUN_LIVE_TESTS=1（需可访问 ${const String.fromEnvironment('APP_ENV', defaultValue: 'test')} 环境）';
}
