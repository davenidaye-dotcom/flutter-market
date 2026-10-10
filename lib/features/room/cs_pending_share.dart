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
