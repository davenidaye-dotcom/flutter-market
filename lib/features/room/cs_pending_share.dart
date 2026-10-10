import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 业务页「发给客服」草稿：进客服页后再二次确认发送。
class PendingCsShare {
  const PendingCsShare({
    required this.refType,
    required this.refId,
    this.preview = '',
  });

  final String refType;
  final String refId;
  final String preview;
}

final pendingCsShareProvider = StateProvider<PendingCsShare?>((ref) => null);

/// 清空/隐藏客服历史后递增，客服页 listen 后丢掉本地缓存并重拉。
final csHistoryRevisionProvider = StateProvider<int>((ref) => 0);

void bumpCsHistoryRevision(WidgetRef ref) {
  ref.read(csHistoryRevisionProvider.notifier).state++;
}
