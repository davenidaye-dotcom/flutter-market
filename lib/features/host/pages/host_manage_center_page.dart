import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import '../../../config/router/route_paths.dart';
import '../../../config/theme/app_colors.dart';
import '../../../data/repositories/providers.dart';
import '../../../shared/widgets/emulator_safe_dialog.dart';
import '../../../shared/widgets/emulator_safe_text_field.dart';
import '../../../shared/widgets/gradient_background.dart';
import '../../../shared/widgets/page_app_bar.dart';
import '../../../shared/widgets/red_count_badge.dart';
import '../../auth/providers/auth_session_provider.dart';
import '../../lottery/providers/lottery_live_provider.dart';
import '../providers/host_pending_audit_provider.dart';
import 'fly/fly_hub_page.dart';
import 'host_shell_page.dart';
import 'reports/rebate_report_page.dart';
import 'reports/room_report_page.dart';
import 'reports/score_flow_page.dart';

/// \u4e2a\u4eba\u4e2d\u5fc3 / \u7ba1\u7406\u4e2d\u5fc3
class HostManageCenterPage extends ConsumerStatefulWidget {
  const HostManageCenterPage({super.key, required this.roomId});

  final String roomId;

  @override
  ConsumerState<HostManageCenterPage> createState() => _HostManageCenterPageState();
}

class _HostManageCenterPageState extends ConsumerState<HostManageCenterPage>
    with AutomaticKeepAliveClientMixin {
  Map<String, dynamic> _dash = {};
  bool _loading = true;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    Future.microtask(_loadDash);
  }

  Future<void> _loadDash() async {
    try {
      final data = await ref.read(ownerRepositoryProvider).getDashboard();
      if (!mounted) return;
      setState(() {
        _dash = data;
        _loading = false;
      });
      await ref.read(hostPendingAuditProvider.notifier).refresh();
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      AppToast.error(e.toString());
    }
  }

  Future<void> _sendRedpack() async {
    final titleCtrl = TextEditingController(text: '红包');
    final totalCtrl = TextEditingController(text: '100');
    final countCtrl = TextEditingController(text: '10');
    final ok = await showEmulatorSafeDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('发红包'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            EmulatorSafeTextField(
              controller: titleCtrl,
              decoration: const InputDecoration(labelText: '标题'),
            ),
            EmulatorSafeTextField(
              controller: totalCtrl,
              decoration: const InputDecoration(labelText: '总金额'),
              keyboardType: TextInputType.number,
            ),
            EmulatorSafeTextField(
              controller: countCtrl,
              decoration: const InputDecoration(labelText: '个数'),
              keyboardType: TextInputType.number,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: safeDialogPop(ctx, false), child: const Text('取消')),
          TextButton(onPressed: safeDialogPop(ctx, true), child: const Text('确定')),
        ],
      ),
    );
    if (ok != true) {
      titleCtrl.dispose();
      totalCtrl.dispose();
      countCtrl.dispose();
      return;
    }
    try {
      await ref.read(ownerRepositoryProvider).createRedpack({
        'title': titleCtrl.text.trim(),
        'totalAmount': num.tryParse(totalCtrl.text) ?? 0,
        'count': int.tryParse(countCtrl.text) ?? 1,
      });
      AppToast.success('红包已发送');
    } catch (e) {
      AppToast.error(e.toString());
    } finally {
      titleCtrl.dispose();
      totalCtrl.dispose();
      countCtrl.dispose();
    }
  }

  String _n(String key) {
    final v = _dash[key];
    if (v == null) return '0';
    if (v is num) return v is int ? '$v' : v.toStringAsFixed(0);
    return '$v';
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final roomId = widget.roomId;
    final pending = ref.watch(hostPendingAuditProvider);
    return AppPageScaffold(
      body: GradientBackground(
        child: SafeArea(
          child: Column(
            children: [
              PageAppBar(
                title: '\u7ba1\u7406\u4e2d\u5fc3',
                onBack: () => goHostLottery(context, roomId),
              ),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : ListView(
                  padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 16.h),
                  children: [
                    Container(
                      padding: EdgeInsets.fromLTRB(16.w, 14.h, 16.w, 16.h),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.88),
                        borderRadius: BorderRadius.circular(16.r),
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Text('\u4eca\u65e5\u76c8\u4e8f', style: TextStyle(fontSize: 14.sp, color: AppColors.textPrimary)),
                              SizedBox(width: 8.w),
                              Text(_n('todayProfitLoss'), style: TextStyle(fontSize: 22.sp, fontWeight: FontWeight.w700)),
                              const Spacer(),
                              GestureDetector(
                                onTap: _loadDash,
                                child: Container(
                                  padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
                                  decoration: BoxDecoration(
                                    color: AppColors.navBlue.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(12.r),
                                  ),
                                  child: Text('\u4eca\u65e5\u7edf\u8ba1', style: TextStyle(fontSize: 12.sp, color: AppColors.navBlue)),
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: 14.h),
                          Row(
                            children: [
                              _stat('\u4e0a\u5206', _n('upAmount'), sub: '\u4f59\u989d: ${_n('balance')}'),
                              _stat('\u4e0b\u5206', _n('downAmount'), valueColor: AppColors.success, sub: '\u98de\u5355: ${_n('flyOrderAmount')}'),
                              _stat('\u6d41\u6c34', _n('turnover'), valueColor: AppColors.danger, sub: '\u98de\u5355\u6d41\u6c34: ${_n('flyOrderTurnover')}'),
                            ],
                          ),
                          SizedBox(height: 16.h),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              _circleAction(
                                Icons.arrow_upward,
                                '申请上分',
                                () {
                                  final shell =
                                      StatefulNavigationShell.maybeOf(context);
                                  if (shell != null) {
                                    shell.goBranch(4);
                                    return;
                                  }
                                  context.go(RoutePaths.hostAudit(roomId));
                                },
                                badge: pending.up,
                              ),
                              _circleAction(
                                Icons.arrow_downward,
                                '申请下分',
                                () {
                                  final shell =
                                      StatefulNavigationShell.maybeOf(context);
                                  if (shell != null) {
                                    shell.goBranch(4);
                                    return;
                                  }
                                  context.go(RoutePaths.hostAudit(roomId));
                                },
                                badge: pending.down,
                              ),
                              _circleAction(
                                Icons.person_add_alt_1,
                                '进房审核',
                                () {
                                  final shell =
                                      StatefulNavigationShell.maybeOf(context);
                                  if (shell != null) {
                                    shell.goBranch(4);
                                    return;
                                  }
                                  context.go(RoutePaths.hostAudit(roomId));
                                },
                                badge: pending.enter,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: 12.h),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16.r),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        children: [
                          _menu('\u98de\u76d8\u52a9\u624b', () => pushHostPage(context, FlyHubPage(roomId: roomId))),
                          _div(),
                          _menu('\u53d1\u7ea2\u5305', _sendRedpack),
                          _div(),
                          _menu('\u7ade\u731c\u62a5\u8868', () => pushHostPage(context, RoomReportPage(roomId: roomId))),
                          _div(),
                          _menu('\u798f\u5229\u62a5\u8868', () => pushHostPage(context, RebateReportPage(roomId: roomId))),
                          _div(),
                          _menu('\u4e0a\u4e0b\u5206\u62a5\u8868', () => pushHostPage(context, ScoreFlowPage(roomId: roomId))),
                          _div(),
                          _menu('APP\u5206\u4eab', () => AppToast.info('APP\u5206\u4eab\u5f85\u5bf9\u63a5')),
                        ],
                      ),
                    ),
                    SizedBox(height: 28.h),
                    GestureDetector(
                      onTap: () async {
                        dismissAllShellCovers();
                        ref.invalidate(roomLotteryLiveProvider(roomId));
                        await ref.read(authSessionProvider.notifier).logout();
                        if (context.mounted) context.go(RoutePaths.login);
                      },
                      child: Container(
                        height: 44.h,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: AppColors.navBlue,
                          borderRadius: BorderRadius.circular(22.r),
                        ),
                        child: Text('\u9000\u51fa', style: TextStyle(fontSize: 16.sp, color: Colors.white, fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _stat(String label, String value, {String? sub, Color? valueColor}) {
    return Expanded(
      child: Column(
        children: [
          Text(label, style: TextStyle(fontSize: 12.sp, color: AppColors.textSecondary)),
          SizedBox(height: 4.h),
          Text(value, style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.w600, color: valueColor ?? AppColors.textPrimary)),
          if (sub != null) ...[
            SizedBox(height: 2.h),
            Text(sub, style: TextStyle(fontSize: 11.sp, color: AppColors.textHint)),
          ],
        ],
      ),
    );
  }

  Widget _circleAction(
    IconData icon,
    String label,
    VoidCallback onTap, {
    int badge = 0,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          BadgedIcon(
            count: badge,
            right: -2,
            top: -2,
            child: Container(
              width: 48.w,
              height: 48.w,
              decoration: const BoxDecoration(
                color: AppColors.navBlue,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: Colors.white, size: 24.sp),
            ),
          ),
          SizedBox(height: 6.h),
          Text(
            label,
            style: TextStyle(fontSize: 12.sp, color: AppColors.textPrimary),
          ),
        ],
      ),
    );
  }

  Widget _menu(String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
        child: Row(
          children: [
            Expanded(child: Text(label, style: TextStyle(fontSize: 15.sp))),
            Icon(Icons.chevron_right, color: AppColors.textHint, size: 18.sp),
          ],
        ),
      ),
    );
  }

  Widget _div() => const Divider(height: 1, indent: 16, endIndent: 16, color: AppColors.divider);
}
