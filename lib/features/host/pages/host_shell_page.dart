import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../config/router/route_paths.dart';
import '../../../shared/widgets/emulator_safe_text_field.dart';
import '../../../shared/widgets/host_bottom_nav.dart';
import '../../lottery/providers/lottery_live_provider.dart';
import '../providers/host_pending_audit_provider.dart';

/// Host shell with pending audit badge from API
class HostShellPage extends ConsumerStatefulWidget {
  const HostShellPage({
    super.key,
    required this.roomId,
    required this.navigationShell,
  });

  final String roomId;
  final StatefulNavigationShell navigationShell;

  @override
  ConsumerState<HostShellPage> createState() => _HostShellPageState();
}

class _HostShellPageState extends ConsumerState<HostShellPage> {
  Timer? _badgeTimer;

  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      // 与玩家 RoomShell 一致：进壳即拉彩种，否则大厅 ready 永远 false 一直转圈
      final live = ref.read(roomLotteryLiveProvider(widget.roomId).notifier);
      await live.ensureLoaded();
      unawaited(live.ensureDrawHistoryPreloaded());
      unawaited(ref.read(hostPendingAuditProvider.notifier).refresh());
    });
    // 待审角标定时刷新
    _badgeTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted) return;
      unawaited(ref.read(hostPendingAuditProvider.notifier).refresh());
    });
  }

  @override
  void dispose() {
    _badgeTimer?.cancel();
    super.dispose();
  }

  int get _navIndex {
    final i = widget.navigationShell.currentIndex;
    return i == 0 ? -1 : i - 1;
  }

  void _onNavTap(int index) {
    final branch = index + 1;
    if (branch == widget.navigationShell.currentIndex) {
      // 再点个人中心/审核：刷新角标
      if (index == 2 || index == 3) {
        unawaited(ref.read(hostPendingAuditProvider.notifier).refresh());
      }
      return;
    }
    widget.navigationShell.goBranch(branch);
    if (index == 2 || index == 3) {
      unawaited(ref.read(hostPendingAuditProvider.notifier).refresh());
    }
  }

  @override
  Widget build(BuildContext context) {
    final badge = ref.watch(hostPendingAuditProvider).total;
    return AppPageScaffold(
      body: widget.navigationShell,
      bottomNavigationBar: HostBottomNavBar(
        currentIndex: _navIndex,
        auditBadge: badge,
        onTap: _onNavTap,
      ),
    );
  }
}

void goHostLottery(BuildContext context, String roomId) {
  final shell = StatefulNavigationShell.maybeOf(context);
  if (shell != null) {
    shell.goBranch(0);
    return;
  }
  if (roomId.isEmpty) return;
  context.go(RoutePaths.hostLottery(roomId));
}
