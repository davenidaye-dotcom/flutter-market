import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/session_store.dart';
import '../../data/repositories/providers.dart';
import '../../shared/widgets/page_app_bar.dart';

/// 业务页「发给客服」：确认 → SHARE → 打开会员客服页。
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
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('发给客服'),
      content: Text(
        preview == null || preview.isEmpty
            ? '确认将该记录分享到本房客服？'
            : '确认分享到客服？\n$preview',
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消')),
        TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('发送')),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;
  try {
    await ref.read(memberRepositoryProvider).sendCsMessage(
          preview ?? '',
          msgType: 'SHARE',
          refType: refType,
          refId: refId,
        );
    if (!context.mounted) return;
    AppToast.success('已发送到客服');
    context.go('/room/$rid/service');
  } catch (e) {
    AppToast.error(e.toString());
  }
}
