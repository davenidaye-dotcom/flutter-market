import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 底部「在线客服」未读条数。房主是玩家来信，玩家是房主回复。
final csUnreadCountProvider = NotifierProvider<CsUnreadNotifier, int>(CsUnreadNotifier.new);

class CsUnreadNotifier extends Notifier<int> {
  int _ts = 0;

  @override
  int build() => 0;

  void clear() {
    _ts = 0;
    state = 0;
  }

  void apply(int count, {int ts = 0}) {
    if (ts > 0 && _ts > 0 && ts < _ts) return;
    if (ts > _ts) _ts = ts;
    final next = count < 0 ? 0 : count;
    if (state != next) state = next;
  }

  void applyMap(Map<dynamic, dynamic> data) {
    final n = int.tryParse('${data['totalUnread'] ?? data['unreadCount'] ?? 0}') ?? 0;
    final ts = int.tryParse('${data['ts'] ?? 0}') ?? 0;
    apply(n, ts: ts);
  }
}
