import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letou_app/config/theme/app_theme.dart';
import 'package:letou_app/core/network/session_store.dart';
import 'package:letou_app/core/testing/regression_test_flags.dart';
import 'package:letou_app/data/models/app_role.dart';
import 'package:letou_app/data/models/user_model.dart';
import 'package:letou_app/data/repositories/providers.dart';
import 'package:letou_app/features/auth/providers/auth_session_provider.dart';
import 'package:letou_app/features/lottery/pages/chat_bet_page.dart';
import 'package:letou_app/features/lottery/providers/lottery_live_provider.dart';
import 'package:letou_app/features/lottery/services/chat_push_cache.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/chat_test_helpers.dart';
import 'fake_wallet_repository.dart';
import 'regression_fixtures.dart';

/// 下注聊天页 UI 回归：假 HTTP + 注入 WS，不连真实网络。
class ChatBetRegressionHarness {
  ChatBetRegressionHarness._();

  static const roomId = RegressionFixtures.roomId;
  static const gameId = RegressionFixtures.gameId;

  static List<Override> defaultOverrides({
    FakeLotteryRepository? lottery,
    FakeWalletRepository? wallet,
  }) {
    final fakeLottery = lottery ??
        FakeLotteryRepository(
          games: RegressionFixtures.games(),
          chatMessages: parseApiChatMessages(RegressionFixtures.rawChatMessages()),
          drawHistory: RegressionFixtures.rawDrawHistory(),
        );
    return [
      regressionSkipLiveWsProvider.overrideWithValue(true),
      lotteryRepositoryProvider.overrideWithValue(fakeLottery),
      walletRepositoryProvider.overrideWithValue(wallet ?? FakeWalletRepository()),
      authSessionProvider.overrideWith(_FixedAuthSessionNotifier.new),
    ];
  }

  static Future<void> prepareSession() async {
    SharedPreferences.setMockInitialValues({});
    await ChatPushCache.instance.clearRoom(roomId);
    SessionStore.instance.accessToken = 'regression-test-token';
    SessionStore.instance.roomId = roomId;
    SessionStore.instance.roomCode = '679010';
  }

  static Widget app({List<Override> overrides = const []}) {
    return ProviderScope(
      overrides: [...defaultOverrides(), ...overrides],
      child: ScreenUtilInit(
        designSize: const Size(375, 812),
        minTextAdapt: true,
        builder: (_, __) => MaterialApp(
          theme: AppTheme.light,
          home: ChatBetPage(roomId: roomId, gameId: gameId),
        ),
      ),
    );
  }

  static RoomLotteryLiveNotifier liveNotifier(WidgetTester tester) {
    final element = tester.element(find.byType(ChatBetPage));
    return ProviderScope.containerOf(element)
        .read(roomLotteryLiveProvider(roomId).notifier);
  }

  static Future<void> pumpUntilChatReady(
    WidgetTester tester, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1.0;

    await tester.pumpWidget(app());
    await tester.pump();
    final live = liveNotifier(tester);
    await live.ensureLoaded();
    await live.prepareChatTimeline(gameId);
    await tester.pumpAndSettle(const Duration(seconds: 2));
  }

  static Future<void> injectWsSequence(WidgetTester tester) async {
    final live = liveNotifier(tester);
    live.debugInjectWsEvent(RegressionFixtures.wsPeriodTick());
    await tester.pump(const Duration(milliseconds: 100));
    live.debugInjectWsEvent(RegressionFixtures.wsSealWarn());
    await tester.pump(const Duration(milliseconds: 100));
    live.debugInjectWsEvent(RegressionFixtures.wsSealed());
    await tester.pump(const Duration(milliseconds: 100));
    live.debugInjectWsEvent(RegressionFixtures.wsDrawResult());
    await tester.pump(const Duration(milliseconds: 100));
    live.debugInjectWsEvent(RegressionFixtures.wsUserBet());
    await tester.pump(const Duration(milliseconds: 400));
  }

  static Future<void> flushPendingTimers(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 6));
  }
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
