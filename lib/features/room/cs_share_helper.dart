import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/session_store.dart';
import '../../shared/widgets/page_app_bar.dart';
import 'cs_pending_share.dart';

/// 业务页「发给客服」：只带草稿跳转客服页，不在此发送。
Future<void> shareToCustomerService(
  BuildContext context,
  WidgetRef ref, {
  String? roomId,
  required String refType,
  required String refId,
  String? preview,
}) async {
  final rid = (roomId?.trim().isNotEmpty == true)
      ? roomId!.trim()
      : (GoRouterState.of(context).pathParameters['roomId'] ??
          SessionStore.instance.roomId ??
          '');
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
  ref.read(pendingCsShareProvider.notifier).state = PendingCsShare(
    refType: type,
    refId: id,
    preview: preview?.trim() ?? '',
  );
  if (!context.mounted) return;
  context.go('/room/$rid/service');
}
