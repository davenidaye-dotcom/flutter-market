import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/session_store.dart';

/// 大厅顶栏房间名。房主改名后两边都看这个，不再用账号昵称。
final hallRoomTitleProvider =
    NotifierProvider<HallRoomTitleNotifier, String>(HallRoomTitleNotifier.new);

class HallRoomTitleNotifier extends Notifier<String> {
  @override
  String build() => SessionStore.instance.roomName?.trim() ?? '';

  Future<void> show(String name) async {
    final n = name.trim();
    if (n.isEmpty) return;
    state = n;
    final store = SessionStore.instance;
    if ((store.roomName?.trim() ?? '') == n) return;
    await store.setRoom(
      roomId: store.roomId,
      roomCode: store.roomCode,
      roomName: n,
    );
  }
}
