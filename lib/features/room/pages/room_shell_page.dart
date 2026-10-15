import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/audio/bgm_prompt.dart';
import '../../../config/router/route_paths.dart';
import '../../../shared/widgets/app_back.dart';
import '../../../shared/widgets/emulator_safe_text_field.dart';
import '../../../data/repositories/providers.dart';
import '../../../shared/widgets/user_bottom_nav.dart';
import '../../lottery/providers/lottery_live_provider.dart';
import '../cs_unread.dart';

/// 用户端房间 Shell（IndexedStack 保活各 Tab，切回彩种大厅不重载）
/// 分支：0 彩种 / 1 客服 / 2 钱包 / 3 介绍 / 4 个人
class RoomShellPage extends ConsumerStatefulWidget {
  const RoomShellPage({
    super.key,
    required this.roomId,
    required this.navigationShell,
  });

  final String roomId;
  final StatefulNavigationShell navigationShell;

  @override
  ConsumerState<RoomShellPage> createState() => _RoomShellPageState();
}

class _RoomShellPageState extends ConsumerState<RoomShellPage> {
  Timer? _csTimer;
  /// 底栏浏览历史（不含当前），返回时回到上一 Tab
  final List<int> _tabHistory = <int>[];
  int _prevBranch = -1;
  /// 这次返回要去的分支，避免再记成新的一页
  int? _backTo;

  @override
  void initState() {
    super.initState();
    // 进房拉彩种列表，并预拉每个彩种最近 15 期开奖/聊天，避免第一次点进彩种只有本地封盘。
    Future.microtask(() async {
      unawaited(BgmPrompt.refreshPlayer());
      final live = ref.read(roomLotteryLiveProvider(widget.roomId).notifier);
      await live.ensureLoaded();
      if (!mounted) return;
      unawaited(live.ensureDrawHistoryPreloaded());
      unawaited(_refreshCsUnread());
    });
    _csTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted) return;
      unawaited(_refreshCsUnread());
    });
  }

  @override
  void dispose() {
    _csTimer?.cancel();
    super.dispose();
  }

  Future<void> _refreshCsUnread() async {
    try {
      final data = await ref.read(memberRepositoryProvider).getCsUnread();
      if (!mounted) return;
      ref.read(csUnreadCountProvider.notifier).applyMap(data);
    } catch (_) {}
  }

  /// 底栏 index：-1 彩种大厅；0~3 对应客服/钱包/介绍/个人
  int get _navIndex {
    final i = widget.navigationShell.currentIndex;
    return i == 0 ? -1 : i - 1;
  }

  void _onNavTap(int index) {
    // 底栏 0~3 → 分支 1~4；勿 initialLocation:true，否则会重置分支丢掉保活 State
    final branch = index + 1;
    if (branch == widget.navigationShell.currentIndex) return;
    widget.navigationShell.goBranch(branch);
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
    final unread = ref.watch(csUnreadCountProvider);
    _noteBranch(widget.navigationShell.currentIndex);
    return ShellTabBack(
      tryBack: _tryTabBack,
      child: AppBackScope(
        child: AppPageScaffold(
          body: widget.navigationShell,
          bottomNavigationBar: UserBottomNavBar(
            currentIndex: _navIndex,
            // 正在看客服时数字让给对话本身，离开这一栏再显示未读
            csBadge: _navIndex == 0 ? 0 : unread,
            onTap: _onNavTap,
          ),
        ),
      ),
    );
  }
}

/// 房间子页返回：与系统返回同一套 [appHandleBack]
void appRoomBack(BuildContext context, String roomId) {
  appHandleBack(context);
}

/// 切回房间彩种大厅（优先 goBranch 保活，避免整页重载闪烁）
void goRoomLottery(BuildContext context, String roomId) {
  final shell = StatefulNavigationShell.maybeOf(context);
  if (shell != null) {
    shell.goBranch(0);
    return;
  }
  if (roomId.isEmpty) return;
  context.go(RoutePaths.roomLottery(roomId));
}
