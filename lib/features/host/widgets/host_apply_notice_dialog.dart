import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../config/theme/app_colors.dart';
import '../../../data/repositories/providers.dart';
import '../../../shared/widgets/page_app_bar.dart';
import '../../../shared/widgets/user_avatar.dart';
import '../providers/host_apply_notice_provider.dart';
import '../providers/host_pending_audit_provider.dart';
import '../services/host_audit_alert_sound.dart';

/// 竞品「审核提醒」：上/下分待审弹窗（通过 / 拒绝）。
Future<void> showHostApplyNoticeDialog(
  BuildContext context,
  WidgetRef ref,
  HostApplyNotice notice,
) async {
  unawaited(HostAuditAlertSound.playOnce());
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black.withValues(alpha: 0.45),
    builder: (ctx) => _HostApplyNoticeDialog(notice: notice, parentRef: ref),
  );
}

class _HostApplyNoticeDialog extends ConsumerStatefulWidget {
  const _HostApplyNoticeDialog({
    required this.notice,
    required this.parentRef,
  });

  final HostApplyNotice notice;
  final WidgetRef parentRef;

  @override
  ConsumerState<_HostApplyNoticeDialog> createState() =>
      _HostApplyNoticeDialogState();
}

class _HostApplyNoticeDialogState
    extends ConsumerState<_HostApplyNoticeDialog> {
  bool _acting = false;

  HostApplyNotice get notice => widget.notice;

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
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      AppToast.error(e.toString());
      await widget.parentRef.read(hostPendingAuditProvider.notifier).refresh();
      if (mounted) setState(() => _acting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final amountText = notice.amount == null
        ? ''
        : (notice.amount! == notice.amount!.truncateToDouble()
            ? notice.amount!.toInt().toString()
            : notice.amount!.toString());
    final nick =
        notice.nickname.isEmpty ? '玩家' : notice.nickname;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.symmetric(horizontal: 36.w),
      child: Container(
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
