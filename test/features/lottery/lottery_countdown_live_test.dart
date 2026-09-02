import 'package:flutter_test/flutter_test.dart';

import '../../support/regression/live_test_env.dart';

/// 单元测试目录下的占位：真实联调在 [integration_test/lottery_countdown_live_test.dart]。
/// `flutter test` 会拦截 HTTP，无法在此文件里连真实 WS。
///
/// 请运行: `scripts/run_live_countdown_test.ps1`
/// 或探针: `dart run scripts/lottery_countdown_live_probe.dart`
void main() {
  test(
    '指向 integration_test 联调',
    () {},
    skip: LiveTestEnv.enabled
        ? '请改用 scripts/run_live_countdown_test.ps1（integration_test 才允许真实网络）'
        : LiveTestEnv.skipReason,
  );
}
