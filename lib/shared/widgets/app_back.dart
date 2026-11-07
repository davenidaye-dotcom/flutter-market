import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';

import '../../config/router/route_paths.dart';
import '../../config/theme/app_colors.dart';
import '../../features/auth/device_login_store.dart';
import '../../features/auth/providers/auth_session_provider.dart';
import '../../features/lottery/providers/lottery_live_provider.dart';
import 'emulator_safe_dialog.dart';
import 'page_app_bar.dart';

/// 统一返回：页内按钮与系统返回共用，一次只退一层。
/// 抽屉 → 键盘 → 浮层（弹窗 / 盖层 / 聊天）→ 分支弹层和子页 → 页内下钻
/// → 代理侧栏上一页 → 玩家/房主主目录确认离开 → 路由栈上一页 → 退出登录。
/// 登录页再返回退出软件。栈已经走完时，2 秒内再按一次也退出软件。
DateTime? _lastRootBack;
bool _exiting = false;
bool _leaveDialogOpen = false;

void appHandleBack(BuildContext context) {
  // 抽屉不是路由。系统返回的 context 在 Scaffold 外面，要往下找。
  if (_closeOpenDrawer(context)) return;

  // 键盘单独占一次返回，避免和翻页挤在同一次里把输入法打乱。
  if (MediaQuery.viewInsetsOf(context).bottom > 0) {
    FocusManager.instance.primaryFocus?.unfocus();
    SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
    return;
  }

  // 盖在壳上面的浮层：审核弹窗、壳盖层、下注聊天。先于底栏里的弹层。
  if (tryAppBackLayers(overlay: true)) return;

  // 底栏分支 / 本地压栈里的弹层和子页，一次只弹一层。
  if (_popNestedNavigator(context)) return;

  // 页内下钻（代理报表、房主客服会话），不在 Navigator 上。
  if (tryAppBackLayers(overlay: false)) return;

  final closer = ShellCoverCloser.maybeOf(context);
  if (closer != null) {
    closer.close();
    return;
  }

  // 代理侧栏仍按自己的路径栈退，不弹房间这套确认。
  final pathBack = AgentShellPathBack.maybeOf(context);
  if (pathBack != null && pathBack.tryBack()) return;

  // 玩家 / 房主壳的五个主目录：子页面已经在上面退完。
  // 这里不再顺着底栏历史切栏目，单击和系统返回都先确认。
  if (ShellTabBack.maybeOf(context) != null) {
    unawaited(_confirmLeaveShell(context));
    return;
  }

  if (_tryPopRoute(context)) return;

  _onStackEmpty(context);
}

/// 主目录根上的离开确认。玩家回进房页，房主（含协管）退出到登录页。
Future<void> _confirmLeaveShell(BuildContext context) async {
  if (_leaveDialogOpen || _exiting) return;
  _leaveDialogOpen = true;
  bool? ok;
  try {
    ok = await showEmulatorSafeDialog<bool>(
      context: context,
      barrierColor: const Color(0x73000000),
      builder: (ctx) => Dialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        insetPadding: EdgeInsets.symmetric(horizontal: 24.w),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16.r),
        ),
        child: SizedBox(
          width: 280.w,
          child: Padding(
            padding: EdgeInsets.fromLTRB(22.w, 22.h, 22.w, 22.h),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '是否确定退出登录？',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16.sp,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                SizedBox(height: 18.h),
                Row(
                  children: [
                    Expanded(
                      child: _LeaveChoice(
                        label: '取消',
                        background: AppColors.sidebarInactive,
                        foreground: AppColors.textPrimary,
                        onTap: safeDialogPop(ctx, false),
                      ),
                    ),
                    SizedBox(width: 12.w),
                    Expanded(
                      child: _LeaveChoice(
                        label: '确定',
                        background: AppColors.primary,
                        foreground: Colors.white,
                        onTap: safeDialogPop(ctx, true),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  } finally {
    _leaveDialogOpen = false;
  }
  if (ok != true || !context.mounted) return;

  final container = ProviderScope.containerOf(context, listen: false);
  final session = container.read(authSessionProvider);
  final roomKey = _shellRoomKey(context) ?? session.user?.roomId;
  dismissAllShellCovers();
  if (roomKey != null && roomKey.isNotEmpty) {
    container.invalidate(roomLotteryLiveProvider(roomKey));
  }
  if (session.isHostSide) {
    await container.read(authSessionProvider.notifier).logout();
    if (!context.mounted) return;
    if (container.read(authSessionProvider).isLoggedIn) return;
    appGoLoginClearingStack(context);
    return;
  }
  context.go(RoutePaths.home);
}

String? _shellRoomKey(BuildContext context) {
  final segs = GoRouterState.of(context).uri.pathSegments;
  if (segs.length >= 2 && (segs[0] == 'room' || segs[0] == 'host')) {
    final id = segs[1].trim();
    if (id.isNotEmpty) return id;
  }
  return null;
}

class _LeaveChoice extends StatelessWidget {
  const _LeaveChoice({
    required this.label,
    required this.background,
    required this.foreground,
    required this.onTap,
  });

  final String label;
  final Color background;
  final Color foreground;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 40.h,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(20.r),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 14.sp,
            color: foreground,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

void _onStackEmpty(BuildContext context) {
  final now = DateTime.now();
  final again =
      _lastRootBack != null &&
      now.difference(_lastRootBack!) < const Duration(seconds: 2);
  _lastRootBack = now;

  final path = GoRouterState.of(context).uri.path;
  final onLogin = path == RoutePaths.login;
  // 已经在登录页：再返回就离开软件。栈底 2 秒内再按一次同样离开。
  if (onLogin || again) {
    _exiting = true;
    _lastRootBack = null;
    SystemNavigator.pop();
    return;
  }
  if (_isLoggedIn(context)) {
    unawaited(_leaveToLogin(context));
    return;
  }
  appGoLoginClearingStack(context);
}

bool _isLoggedIn(BuildContext context) {
  return ProviderScope.containerOf(
    context,
    listen: false,
  ).read(authSessionProvider).isLoggedIn;
}

Future<void> _leaveToLogin(BuildContext context) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final user = container.read(authSessionProvider).user;
  if (user == null) {
    if (context.mounted) appGoLoginClearingStack(context);
    return;
  }
  final username = user.username;
  // 先丢掉设备令牌，登录页挂上时才不会静默登回去。
  await DeviceLoginStore.clear(username);
  if (_exiting) return;
  await container.read(authSessionProvider.notifier).logout();
  if (_exiting || !context.mounted) return;
  if (container.read(authSessionProvider).isLoggedIn) return;
  appGoLoginClearingStack(context);
}

bool _closeOpenDrawer(BuildContext context) {
  final above = Scaffold.maybeOf(context);
  if (above != null && (above.isDrawerOpen || above.isEndDrawerOpen)) {
    if (above.isDrawerOpen) above.closeDrawer();
    if (above.isEndDrawerOpen) above.closeEndDrawer();
    return true;
  }
  ScaffoldState? open;
  void visit(Element el) {
    if (el is StatefulElement && el.state is ScaffoldState) {
      final state = el.state as ScaffoldState;
      if (state.isDrawerOpen || state.isEndDrawerOpen) open = state;
    }
    el.visitChildElements(visit);
  }

  context.visitChildElements(visit);
  final below = open;
  if (below == null) return false;
  if (below.isDrawerOpen) below.closeDrawer();
  if (below.isEndDrawerOpen) below.closeEndDrawer();
  return true;
}

/// 只弹嵌套 Navigator（分支里的底部弹层、本地压栈），不把整个壳退掉。
bool _popNestedNavigator(BuildContext context) {
  final nearest = Navigator.of(context);
  // 标题栏在子页里：最近的就是壳内 Navigator，弹一层即回到上一页。
  // 系统返回的 context 在根 Navigator 上，根上还能 pop 时是「退出房间」，留给后面的路由栈。
  final nestedSelf =
      nearest.context.findAncestorStateOfType<NavigatorState>() != null;
  if (nestedSelf && nearest.canPop()) {
    nearest.pop();
    return true;
  }

  NavigatorState? target;
  void visit(Element el) {
    final widget = el.widget;
    if (widget is Offstage && widget.offstage) return;
    if (el is StatefulElement && el.state is NavigatorState) {
      final nav = el.state as NavigatorState;
      if (!identical(nav, nearest) && nav.canPop()) target = nav;
    }
    el.visitChildElements(visit);
  }

  context.visitChildElements(visit);
  final nav = target;
  if (nav == null) return false;
  nav.pop();
  return true;
}

bool _tryPopRoute(BuildContext context) {
  final router = GoRouter.maybeOf(context);
  if (router != null && router.canPop()) {
    router.pop();
    return true;
  }
  return false;
}

/// 壳级系统返回拦截。
class AppBackScope extends StatefulWidget {
  const AppBackScope({super.key, required this.child});

  final Widget child;

  @override
  State<AppBackScope> createState() => _AppBackScopeState();
}

class _AppBackScopeState extends State<AppBackScope> {
  final _innerKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        final inner = _innerKey.currentContext;
        appHandleBack(inner ?? context);
      },
      child: KeyedSubtree(key: _innerKey, child: widget.child),
    );
  }
}

/// 房主/会员 StatefulShell 底栏浏览历史：返回上一个 Tab。
class ShellTabBack extends InheritedWidget {
  const ShellTabBack({super.key, required this.tryBack, required super.child});

  final bool Function() tryBack;

  static ShellTabBack? maybeOf(BuildContext context) {
    // 从返回回调取，勿用 dependOn（非 build 阶段）
    return context.getInheritedWidgetOfExactType<ShellTabBack>();
  }

  @override
  bool updateShouldNotify(ShellTabBack oldWidget) =>
      tryBack != oldWidget.tryBack;
}

/// 代理侧栏「入栈」：ShellRoute 下用 go 换页 + 自建路径栈（等同上一页历史）。
void agentShellPush(BuildContext context, String path) {
  final pathBack = AgentShellPathBack.maybeOf(context);
  if (pathBack != null) {
    pathBack.rememberAndGo(path);
    return;
  }
  final current = GoRouterState.of(context).uri.path;
  final norm = _normPath(path);
  if (_normPath(current) == norm) return;
  context.push(path);
}

String _normPath(String path) => path.endsWith('/') && path.length > 1
    ? path.substring(0, path.length - 1)
    : path;

/// 代理壳路径浏览历史。
class AgentShellPathBack extends InheritedWidget {
  const AgentShellPathBack({
    super.key,
    required this.rememberAndGo,
    required this.tryBack,
    required super.child,
  });

  final void Function(String path) rememberAndGo;
  final bool Function() tryBack;

  static AgentShellPathBack? maybeOf(BuildContext context) {
    return context.getInheritedWidgetOfExactType<AgentShellPathBack>();
  }

  @override
  bool updateShouldNotify(AgentShellPathBack oldWidget) =>
      rememberAndGo != oldWidget.rememberAndGo || tryBack != oldWidget.tryBack;
}

/// 安全退出到登录并清掉业务栈（go 替换，避免 pop 回已退出账号）。
void appGoLoginClearingStack(BuildContext context) {
  dismissAllShellCovers();
  _lastRootBack = null;
  context.go(RoutePaths.login);
}
