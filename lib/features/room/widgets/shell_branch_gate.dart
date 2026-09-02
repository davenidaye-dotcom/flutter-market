import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// IndexedStack 会一次性挂载所有分支并触发 initState。
/// 用本组件包裹非默认 Tab：仅当前分支可见时才挂载子页，避免进房瞬间并发多接口把 UI 卡死/黑屏。
class ShellBranchGate extends StatelessWidget {
  const ShellBranchGate({
    super.key,
    required this.branchIndex,
    required this.child,
  });

  final int branchIndex;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final shell = StatefulNavigationShell.maybeOf(context);
    if (shell != null && shell.currentIndex != branchIndex) {
      return const SizedBox.shrink();
    }
    return child;
  }
}
