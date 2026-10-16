import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/audio/bgm_prompt.dart';
import '../../../config/router/route_paths.dart';
import '../../../shared/widgets/app_back.dart';
import '../../../shared/widgets/emulator_safe_text_field.dart';
import '../../../data/repositories/providers.dart';
import '../../../shared/widgets/host_bottom_nav.dart';
import '../../lottery/providers/lottery_live_provider.dart';
import '../../room/cs_unread.dart';
import '../providers/host_apply_notice_provider.dart';
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
  int _prevBranch = -1;
  /// 底栏浏览历史（不含当前），返回时回到上一 Tab
  final List<int> _tabHistory = <int>[];
  /// 这次返回要去的分支，避免再记成新的一页
  int? _backTo;

  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      unawaited(BgmPrompt.refreshHost());
      // 与玩家 RoomShell 一致：进壳即拉彩种，否则大厅 ready 永远 false 一直转圈
      final live = ref.read(roomLotteryLiveProvider(widget.roomId).notifier);
      await live.ensureLoaded();
      if (!mounted) return;
      unawaited(live.ensureDrawHistoryPreloaded());
      unawaited(ref.read(hostPendingAuditProvider.notifier).refresh());
      unawaited(ref.read(hostApplyNoticeProvider.notifier).syncRecentPending());
      unawaited(_refreshCsUnread());
    });
    // 角标、以及 WS 漏掉的近期待审弹窗
    _badgeTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted) return;
      unawaited(ref.read(hostPendingAuditProvider.notifier).refresh());
      unawaited(ref.read(hostApplyNoticeProvider.notifier).syncRecentPending());
      unawaited(_refreshCsUnread());
    });
  }

  Future<void> _refreshCsUnread() async {
    try {
      final data = await ref.read(ownerRepositoryProvider).getCsUnread();
      if (!mounted) return;
      ref.read(csUnreadCountProvider.notifier).applyMap(data);
    } catch (_) {}
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

  void _bumpAuditListRefresh() {
    ref.read(hostAuditListRefreshTickProvider.notifier).state++;
  }

  void _onNavTap(int index) {
    final branch = index + 1;
    if (branch == widget.navigationShell.currentIndex) {
      // 再点个人中心/审核：刷新角标；审核页再拉列表
      if (index == 2 || index == 3) {
        unawaited(ref.read(hostPendingAuditProvider.notifier).refresh());
      }
      if (index == 3) _bumpAuditListRefresh();
      return;
    }
    widget.navigationShell.goBranch(branch);
    if (index == 2 || index == 3) {
      unawaited(ref.read(hostPendingAuditProvider.notifier).refresh());
    }
  }

  /// 底栏、goBranch、路由切分支都记上一页，返回时按进入顺序退。
  void _noteBranch(int branch) {
    if (_prevBranch >= 0 && branch != _prevBranch) {
      if (_backTo == branch) {
        _backTo = null;
      } else {
        _backTo = null;
        if (_tabHistory.isEmpty || _tabHistory.last != _prevBranch) {
          _tabHistory.add(_prevBranch);
        }
      }
    }
    _prevBranch = branch;
  }

  bool _tryTabBack() {
    if (_tabHistory.isEmpty) return false;
    final prev = _tabHistory.removeLast();
    _backTo = prev;
    widget.navigationShell.goBranch(prev);
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final branch = widget.navigationShell.currentIndex;
    // 进入审核 Tab（含从其它页 go 进来）→ 申请记录自动刷新
    if (branch == 4 && _prevBranch != 4) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _bumpAuditListRefresh();
      });
    }
    _noteBranch(branch);

    final badge = ref.watch(hostPendingAuditProvider).total;
    final csUnread = ref.watch(csUnreadCountProvider);
    return ShellTabBack(
      tryBack: _tryTabBack,
      child: AppBackScope(
        child: AppPageScaffold(
          body: widget.navigationShell,
          bottomNavigationBar: HostBottomNavBar(
            currentIndex: _navIndex,
            auditBadge: badge,
            csBadge: csUnread,
            onTap: _onNavTap,
          ),
        ),
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
