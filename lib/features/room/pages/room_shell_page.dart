import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../config/router/route_paths.dart';
import '../../../shared/widgets/emulator_safe_text_field.dart';
import '../../../shared/widgets/page_app_bar.dart';
import '../../../shared/widgets/user_bottom_nav.dart';
import '../../lottery/providers/lottery_live_provider.dart';

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
  @override
  void initState() {
    super.initState();
    // 进房即预拉彩种列表 + 全部彩种历史开奖/聊天缓存，下注页秒开
    Future.microtask(() async {
      final live = ref.read(roomLotteryLiveProvider(widget.roomId).notifier);
      await live.ensureLoaded();
      unawaited(live.ensureDrawHistoryPreloaded());
    });
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

  @override
  Widget build(BuildContext context) {
    return AppPageScaffold(
      body: widget.navigationShell,
      bottomNavigationBar: UserBottomNavBar(
        currentIndex: _navIndex,
        onTap: _onNavTap,
      ),
    );
  }
}

/// 房间子页返回：Overlay / 本地栈优先 pop，否则回彩种大厅 Tab
void appRoomBack(BuildContext context, String roomId) {
  final nav = Navigator.of(context);
  if (nav.canPop()) {
    nav.pop();
    return;
  }
  final closer = ShellCoverCloser.maybeOf(context);
  if (closer != null) {
    closer.close();
    return;
  }
  goRoomLottery(context, roomId);
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
