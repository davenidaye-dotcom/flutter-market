import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:letou_app/core/testing/regression_test_flags.dart';
import 'package:letou_app/data/models/app_role.dart';
import 'package:letou_app/data/models/lottery_game_model.dart';
import 'package:letou_app/data/models/user_model.dart';
import 'package:letou_app/data/repositories/providers.dart';
import 'package:letou_app/features/auth/providers/auth_session_provider.dart';
import 'package:letou_app/features/lottery/providers/lottery_live_provider.dart';
import 'package:letou_app/features/lottery/utils/lottery_period_ui.dart';

import '../../support/regression/fake_wallet_repository.dart';
import '../../support/regression/regression_fixtures.dart';

/// Provider 层回归：覆盖 engine 单测测不到的「进房 → WS 同步 → 再进房」链路。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const roomId = RegressionFixtures.roomId;
  const gameId = RegressionFixtures.gameId;

  late ProviderContainer container;
  late int openAtMs;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    final base = DateTime.now();
    openAtMs = base.add(const Duration(seconds: 75)).millisecondsSinceEpoch;
    final fakeLottery = FakeLotteryRepository(
      games: [
        LotteryGameModel(
          id: gameId,
          name: '极速赛车',
          currentIssue: '34136377',
          previousIssue: '34136376',
          countdownSeconds: 75,
          status: LotteryPeriodHelper.statusFromCountdown(75),
          previousResults: const [1, 2, 3, 4, 5, 6, 7, 8, 9, 10],
          openAtEpochMs: openAtMs,
        ),
      ],
    );
    container = ProviderContainer(
      overrides: [
        regressionSkipLiveWsProvider.overrideWithValue(true),
        lotteryRepositoryProvider.overrideWithValue(fakeLottery),
        walletRepositoryProvider.overrideWithValue(FakeWalletRepository()),
        authSessionProvider.overrideWith(_FixedAuthSessionNotifier.new),
      ],
    );
  });

  tearDown(() => container.dispose());

  test('ensureLoaded twice keeps monotonic countdown (simulates re-enter room)', () async {
    final live = container.read(roomLotteryLiveProvider(roomId).notifier);
    await live.ensureLoaded();

    live.debugInjectWsEvent({
      'event': 'PERIOD_TICK',
      'gameType': gameId,
      'data': {
        'issueNo': '34136377',
        'lastIssueNo': '34136376',
        'lastRanks': [1, 2, 3, 4, 5, 6, 7, 8, 9, 10],
        'countdownSeconds': 75,
        'openAtEpochMs': openAtMs,
      },
    });

    final cdBefore = live.countdownFor(gameId);
    expect(cdBefore, greaterThan(60));

    await Future<void>.delayed(const Duration(milliseconds: 1200));
    await live.ensureLoaded();

    final cdAfter = live.countdownFor(gameId);
    expect(cdAfter, lessThan(cdBefore));
    expect(cdAfter, greaterThan(cdBefore - 4));
  });

  test('cold load uses ws countdown not stale http after first tick', () async {
    final live = container.read(roomLotteryLiveProvider(roomId).notifier);
    await live.ensureLoaded();

    final httpCd = live.countdownFor(gameId);
    expect(httpCd, greaterThan(60));

    final wsOpenAt = DateTime.now().add(const Duration(seconds: 41));
    live.debugInjectWsEvent({
      'event': 'PERIOD_TICK',
      'gameType': gameId,
      'data': {
        'issueNo': '34136377',
        'lastIssueNo': '34136376',
        'lastRanks': [1, 2, 3, 4, 5, 6, 7, 8, 9, 10],
        'countdownSeconds': 41,
        'openAtEpochMs': wsOpenAt.millisecondsSinceEpoch,
      },
    });

    expect(live.isGameWsSynced(gameId), isTrue);
    final wsCd = live.countdownFor(gameId);
    expect(wsCd, lessThan(httpCd));
    expect(wsCd, lessThanOrEqualTo(41));
    expect(wsCd, greaterThan(35));

    // 模拟后续 WS 仍推整期 75 秒：不得回跳到 HTTP 值
    final openAt = wsOpenAt.millisecondsSinceEpoch;
    for (var i = 0; i < 5; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
      final before = live.countdownFor(gameId);
      live.debugInjectWsEvent({
        'event': 'PERIOD_TICK',
        'gameType': gameId,
        'data': {
          'issueNo': '34136377',
          'lastIssueNo': '34136376',
          'lastRanks': [1, 2, 3, 4, 5, 6, 7, 8, 9, 10],
          'countdownSeconds': 75,
          'openAtEpochMs': openAt,
        },
      });
      final after = live.countdownFor(gameId);
      expect(after, lessThanOrEqualTo(before));
    }
  });

  test('display keeps previousIssue strictly before currentIssue after ws sync', () async {
    final live = container.read(roomLotteryLiveProvider(roomId).notifier);
    await live.ensureLoaded();

    live.debugInjectWsEvent({
      'event': 'PERIOD_TICK',
      'gameType': gameId,
      'data': {
        'issueNo': '34136377',
        'lastIssueNo': '34136376',
        'lastRanks': [1, 2, 3, 4, 5, 6, 7, 8, 9, 10],
        'countdownSeconds': 50,
        'openAtEpochMs': openAtMs,
      },
    });

    final g = live.displayGameFor(gameId)!;
    expect(g.currentIssue, '34136377');
    expect(g.previousIssue, '34136376');
    expect(g.previousIssue, isNot(g.currentIssue));
  });
}

class _FixedAuthSessionNotifier extends AuthSessionNotifier {
  _FixedAuthSessionNotifier(super.ref) {
    state = AuthSession(
      user: UserModel(
        id: '10001',
        username: 'player01',
        nickname: 'player01',
        role: AppRole.player,
        roomId: RegressionFixtures.roomId,
      ),
    );
  }
}
