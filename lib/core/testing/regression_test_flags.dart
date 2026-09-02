import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 集成/回归测试：跳过真实 WS，用 [RoomLotteryLiveNotifier.debugInjectWsEvent] 注入事件。
final regressionSkipLiveWsProvider = Provider<bool>((ref) => false);
