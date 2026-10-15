import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../config/theme/app_colors.dart';
import '../../../data/repositories/providers.dart';
import '../../../shared/format/display_number.dart';
import '../../../shared/widgets/page_app_bar.dart';
import '../../../shared/widgets/user_avatar.dart';
import '../providers/host_apply_notice_provider.dart';
import '../providers/host_pending_audit_provider.dart';
import '../services/host_audit_alert_sound.dart';

/// 竞品「审核提醒」：上/下分待审弹窗（通过 / 拒绝）。
///
/// 用 root Overlay 顶层插入，盖过聊天 Overlay / ShellCover，避免 showDialog 被挡住。
Future<void> showHostApplyNoticeDialog(
  BuildContext context,
  WidgetRef ref,
  HostApplyNotice notice,
) async {
  unawaited(HostAuditAlertSound.playOnce());
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;

  final done = Completer<void>();
  late OverlayEntry entry;
  late final AppBackLayer backLayer;
  var closed = false;

  void close() {
    if (closed) return;
    closed = true;
    unregisterAppBackLayer(backLayer);
    entry.remove();
    if (!done.isCompleted) done.complete();
  }

  backLayer = AppBackLayer(() {
    close();
    return true;
  }, overlay: true);

  entry = OverlayEntry(
    builder: (ctx) => Material(
      type: MaterialType.transparency,
      child: AppToastScope(
        child: Stack(
          children: [
            Positioned.fill(
              child: ColoredBox(
                color: Colors.black.withValues(alpha: 0.45),
              ),
            ),
            Center(
              child: _HostApplyNoticeDialog(
                notice: notice,
                parentRef: ref,
                onClose: close,
              ),
            ),
          ],
        ),
      ),
    ),
  );
  overlay.insert(entry);
  registerAppBackLayer(backLayer);
  await done.future;
}

class _HostApplyNoticeDialog extends ConsumerStatefulWidget {
  const _HostApplyNoticeDialog({
    required this.notice,
    required this.parentRef,
    required this.onClose,
  });

  final HostApplyNotice notice;
  final WidgetRef parentRef;
  final VoidCallback onClose;

  @override
  ConsumerState<_HostApplyNoticeDialog> createState() =>
      _HostApplyNoticeDialogState();
}

class _HostApplyNoticeDialogState
    extends ConsumerState<_HostApplyNoticeDialog> {
  bool _acting = false;

  HostApplyNotice get notice => widget.notice;

  void _cancel() {
    if (_acting) return;
    widget.parentRef.read(hostApplyNoticeProvider.notifier).dismissCurrent();
    widget.onClose();
  }

  Future<void> _decide({required bool approve}) async {
    if (_acting || notice.applicationId.isEmpty) return;
    setState(() => _acting = true);
    try {
      final repo = widget.parentRef.read(ownerRepositoryProvider);
      if (approve) {
        await repo.approveApplication(notice.applicationId);
        AppToast.success('已通过');
      } else {
        await repo.rejectApplication(notice.applicationId);
        AppToast.info('已拒绝');
      }
      widget.parentRef
          .read(hostPendingAuditProvider.notifier)
          .onReviewed(notice.auditType);
      widget.parentRef
          .read(hostApplyNoticeProvider.notifier)
          .onReviewed(notice.applicationId);
      widget.onClose();
    } catch (e) {
      AppToast.error(e.toString());
      await widget.parentRef.read(hostPendingAuditProvider.notifier).refresh();
      if (mounted) setState(() => _acting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final amountText = notice.isEnter || notice.amount == null
        ? ''
        : displayNumber(notice.amount);
    final nick =
        notice.nickname.isEmpty ? '玩家' : notice.nickname;

    // 方案 C：标题单独居中；X 略出白卡片右上角
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 36.w),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: double.infinity,
            padding: EdgeInsets.fromLTRB(20.w, 22.h, 20.w, 18.h),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16.r),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '审核提醒',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 18.sp,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF1A1A1A),
                  ),
                ),
                SizedBox(height: 16.h),
                UserAvatar(codeOrUrl: notice.avatar, radius: 36.r),
                SizedBox(height: 14.h),
                Text.rich(
                  TextSpan(
                    style: TextStyle(
                      fontSize: 15.sp,
                      height: 1.4,
                      color: const Color(0xFF333333),
                    ),
                    children: [
                      TextSpan(text: '$nick ${notice.actionLabel}'),
                      if (amountText.isNotEmpty) ...[
                        const TextSpan(text: ' 「'),
                        TextSpan(
                          text: amountText,
                          style: const TextStyle(
                            color: Color(0xFF2ABB5B),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const TextSpan(text: '」'),
                      ],
                      const TextSpan(text: '！'),
                    ],
                  ),
                  textAlign: TextAlign.center,
                ),
                if (notice.remark.trim().isNotEmpty) ...[
                  SizedBox(height: 10.h),
                  Text(
                    '备注：${notice.remark.trim()}',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13.sp,
                      height: 1.35,
                      color: const Color(0xFF888888),
                    ),
                  ),
                ],
                SizedBox(height: 20.h),
                Row(
                  children: [
                    Expanded(
                      child: _ActionBtn(
                        label: '拒绝',
                        filled: false,
                        enabled: !_acting,
                        onTap: () => _decide(approve: false),
                      ),
                    ),
                    SizedBox(width: 12.w),
                    Expanded(
                      child: _ActionBtn(
                        label: '通过',
                        filled: true,
                        enabled: !_acting,
                        onTap: () => _decide(approve: true),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Positioned(
            right: -10.w,
            top: -10.h,
            child: GestureDetector(
              onTap: _acting ? null : _cancel,
              behavior: HitTestBehavior.opaque,
              child: Container(
                width: 28.w,
                height: 28.w,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFFE0E0E0)),
                ),
                child: Icon(
                  Icons.close,
                  size: 16.sp,
                  color: const Color(0xFF999999),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  const _ActionBtn({
    required this.label,
    required this.filled,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final bool filled;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bg = filled
        ? (enabled ? AppColors.navBlue : const Color(0xFFBDBDBD))
        : const Color(0xFFFFEBEE);
    final fg = filled
        ? Colors.white
        : (enabled ? const Color(0xFFE53935) : const Color(0xFFBDBDBD));
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        height: 44.h,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(22.r),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 16.sp,
            fontWeight: FontWeight.w600,
            color: fg,
          ),
        ),
      ),
    );
  }
}
