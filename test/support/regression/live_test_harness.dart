import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:letou_app/core/network/session_store.dart';
import 'package:letou_app/data/models/app_role.dart';
import 'package:letou_app/data/repositories/providers.dart';
import 'package:letou_app/features/lottery/providers/lottery_live_provider.dart';
import 'package:letou_app/features/lottery/utils/lottery_period_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'live_test_env.dart';

/// 真实联调：登录 → 进房 → provider 连 WS，与 App 进历史房间同路径。
abstract final class LiveTestHarness {
  static Future<({ProviderContainer container, String roomCode, String gameId})>
      bootstrapRoomSession() async {
    SharedPreferences.setMockInitialValues({});
    await SessionStore.instance.clear();

    final container = ProviderContainer();
    await container.read(authRepositoryProvider).login(
          username: LiveTestEnv.username,
          password: LiveTestEnv.password,
          captchaToken: '',
          expectedRole: AppRole.player,
        );

    final room = await container.read(roomRepositoryProvider).enterRoom(
          LiveTestEnv.roomCode,
        );
    final roomCode = room.id;
    final live = container.read(roomLotteryLiveProvider(roomCode).notifier);

    await live.ensureLoaded();
    await live.awaitPeriodLiveSync();

    final games = container.read(roomLotteryLiveProvider(roomCode)).games;
    final gameId = games
            .map((g) => g.id)
            .where((id) => id.isNotEmpty)
            .contains(LiveTestEnv.gameId)
        ? LiveTestEnv.gameId
        : (games.isNotEmpty ? games.first.id : LiveTestEnv.gameId);

    return (container: container, roomCode: roomCode, gameId: gameId);
  }

  /// 采样 [duration]，断言倒计时单调不减（允许相等，禁止 01:05↔01:00 回跳）。
  static Future<void> assertCountdownMonotonic({
    required ProviderContainer container,
    required String roomCode,
    required String gameId,
    Duration duration = const Duration(seconds: 20),
    Duration interval = const Duration(milliseconds: 500),
  }) async {
    final live = container.read(roomLotteryLiveProvider(roomCode).notifier);
    final samples = <int>[];
    final bettingSamples = <int>[];
    final deadline = DateTime.now().add(duration);

    while (DateTime.now().isBefore(deadline)) {
      final total = live.countdownFor(gameId);
      final display = live.displayGameFor(gameId);
      final betting = display == null
          ? 0
          : LotteryPeriodHelper.bettingCountdownSeconds(display);

      samples.add(total);
      bettingSamples.add(betting);

      if (samples.length >= 2) {
        final prev = samples[samples.length - 2];
        final cur = samples.last;
        if (cur > prev) {
          throw StateError(
            '倒计时回跳：${prev}s → ${cur}s（下注显示 '
            '${_mmss(bettingSamples[bettingSamples.length - 2])} → '
            '${_mmss(betting)}）samples=$samples',
          );
        }
      }

      await Future<void>.delayed(interval);
    }

    if (!live.isGameWsSynced(gameId)) {
      throw StateError('WS 未同步 gameId=$gameId，无法用联调数据验证倒计时');
    }
    if (samples.where((s) => s > 0).length < 3) {
      throw StateError('采样不足或倒计时始终为 0：$samples');
    }
  }

  /// 模拟历史房间再进：第二次 ensureLoaded 后倒计时仍单调。
  static Future<void> assertReenterMonotonic({
    required ProviderContainer container,
    required String roomCode,
    required String gameId,
  }) async {
    final live = container.read(roomLotteryLiveProvider(roomCode).notifier);
    final before = live.countdownFor(gameId);

    await live.ensureLoaded();
    await live.awaitPeriodLiveSync();

    final after = live.countdownFor(gameId);
    if (after > before + 1) {
      throw StateError('重进房后倒计时回跳：$before → $after');
    }

    await assertCountdownMonotonic(
      container: container,
      roomCode: roomCode,
      gameId: gameId,
      duration: Duration(seconds: LiveTestEnv.sampleSeconds ~/ 2),
    );
  }

  static String _mmss(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  static void dispose(ProviderContainer container) {
    container.dispose();
  }
}
