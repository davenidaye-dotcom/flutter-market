import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/router/app_router.dart';
import '../../core/network/session_store.dart';
import '../../shared/widgets/page_app_bar.dart';
import 'cs_pending_share.dart';

/// 业务页「发给客服」：只带草稿跳转客服页，不在此发送。
///
/// 报表页常在 Overlay/本地 Navigator 里打开，没有 GoRouterState，
/// 因此只用 SessionStore + 全局 GoRouter，并先关掉 Shell 盖层。
Future<void> shareToCustomerService(
  BuildContext context,
  WidgetRef ref, {
  String? roomId,
  required String refType,
  required String refId,
  String? preview,
}) async {
  final rid = (roomId != null && roomId.trim().isNotEmpty)
      ? roomId.trim()
      : (SessionStore.instance.roomId ?? '').trim();
  if (rid.isEmpty) {
    AppToast.error('房间无效');
    return;
  }
  final type = refType.trim().toUpperCase();
  final id = refId.trim();
  if (type.isEmpty || id.isEmpty) {
    AppToast.error('分享内容无效');
    return;
  }

  // 先关掉盖层/本地栈，再写草稿，避免确认框弹在报表下面
  dismissAllShellCovers();
  if (context.mounted) {
    final nav = Navigator.of(context);
    var guard = 0;
    while (nav.canPop() && guard < 8) {
      nav.pop();
      guard++;
    }
  }

  ref.read(pendingCsShareProvider.notifier).state = PendingCsShare(
    refType: type,
    refId: id,
    preview: preview?.trim() ?? '',
  );
  ref.read(routerProvider).go('/room/$rid/service');
}
