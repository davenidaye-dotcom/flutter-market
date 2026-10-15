import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../config/router/route_paths.dart';
import '../../features/auth/device_login_store.dart';
import '../../features/auth/providers/auth_session_provider.dart';
import 'page_app_bar.dart';

/// 统一返回：页内按钮与系统返回共用，一次只退一层。
/// 抽屉 → 键盘 → 浮层（弹窗 / 盖层 / 聊天）→ 分支弹层和子页 → 页内下钻
/// → 底栏或侧栏上一页 → 路由栈上一页 → 退出登录。
/// 登录页再返回退出软件。栈已经走完时，2 秒内再按一次也退出软件。
DateTime? _lastRootBack;
bool _exiting = false;

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

  // 代理侧栏路径 / 房主·会员底栏，各退一页。
  final pathBack = AgentShellPathBack.maybeOf(context);
  if (pathBack != null && pathBack.tryBack()) return;
  final tabBack = ShellTabBack.maybeOf(context);
  if (tabBack != null && tabBack.tryBack()) return;

  if (_tryPopRoute(context)) return;

  _onStackEmpty(context);
}

void _onStackEmpty(BuildContext context) {
  final now = DateTime.now();
  final again = _lastRootBack != null &&
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
  return ProviderScope.containerOf(context, listen: false)
      .read(authSessionProvider)
      .isLoggedIn;
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
  const ShellTabBack({
    super.key,
    required this.tryBack,
    required super.child,
  });

  final bool Function() tryBack;

  static ShellTabBack? maybeOf(BuildContext context) {
    // 从返回回调取，勿用 dependOn（非 build 阶段）
    return context.getInheritedWidgetOfExactType<ShellTabBack>();
  }

  @override
  bool updateShouldNotify(ShellTabBack oldWidget) => tryBack != oldWidget.tryBack;
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

String _normPath(String path) =>
    path.endsWith('/') && path.length > 1 ? path.substring(0, path.length - 1) : path;

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
