import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 管理中心看板脏信号：WS `ROOM_WALLET_SUMMARY` / `OWNER_DASH_DIRTY` 时 +1。
/// [HostManageCenterPage] 监听后防抖重拉 dashboard。
final hostDashDirtyProvider =
    StateProvider.autoDispose.family<int, String>((ref, roomId) => 0);
