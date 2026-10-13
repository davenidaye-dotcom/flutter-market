import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../config/router/route_paths.dart';
import 'page_app_bar.dart';

/// 统一返回：页内按钮与系统侧滑/实体返回共用。
/// 有栈 pop → 关 cover → 壳 Tab 上一页 → 登录页/栈底双击退出。
/// 不再硬跳「壳首页」。
DateTime? _lastExitAttempt;

void appHandleBack(BuildContext context) {
  FocusManager.instance.primaryFocus?.unfocus();
  SystemChannels.textInput.invokeMethod<void>('TextInput.hide');

  // 抽屉开着时 Navigator.canPop 为 true，pop 会先关抽屉
  if (_tryPop(context)) return;

  final closer = ShellCoverCloser.maybeOf(context);
  if (closer != null) {
    closer.close();
    return;
  }

  // 代理侧栏路径栈 / 房主·会员底栏 Tab 栈
  final pathBack = AgentShellPathBack.maybeOf(context);
  if (pathBack != null && pathBack.tryBack()) return;
  final tabBack = ShellTabBack.maybeOf(context);
  if (tabBack != null && tabBack.tryBack()) return;

  final path = GoRouterState.of(context).uri.path;
  // 登录页或业务栈底：双击退出 App
  if (path == RoutePaths.login || path.startsWith('${RoutePaths.login}?')) {
    _doubleBackExit();
    return;
  }

  _doubleBackExit();
}

void _doubleBackExit() {
  final now = DateTime.now();
  if (_lastExitAttempt != null &&
      now.difference(_lastExitAttempt!) < const Duration(seconds: 2)) {
    _lastExitAttempt = null;
    SystemNavigator.pop();
    return;
  }
  _lastExitAttempt = now;
  AppToast.info('再按一次退出');
}

bool _tryPop(BuildContext context) {
  final nav = Navigator.of(context);
  if (nav.canPop()) {
    nav.pop();
    return true;
  }
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
  _lastExitAttempt = null;
  context.go(RoutePaths.login);
}
