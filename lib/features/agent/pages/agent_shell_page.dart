import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../shared/widgets/app_back.dart';
import '../../../shared/widgets/emulator_safe_text_field.dart';
import '../widgets/agent_ui.dart';

/// 代理壳 — 侧栏导航 + 顶栏由各页 AgentPageFrame 提供
class AgentShellPage extends StatefulWidget {
  const AgentShellPage({super.key, required this.roomId, required this.child});

  final String roomId;
  final Widget child;

  @override
  State<AgentShellPage> createState() => _AgentShellPageState();
}

class _AgentShellPageState extends State<AgentShellPage> {
  /// 侧栏切换历史（不含当前），返回时 go 回上一路径
  final List<String> _pathHistory = <String>[];
  String? _lastPath;
  /// 这次返回要去的路径，避免再记成新的一页
  String? _backTo;

  String _norm(String path) =>
      path.endsWith('/') && path.length > 1 ? path.substring(0, path.length - 1) : path;

  void _notePath(String path) {
    final prev = _lastPath;
    if (prev != null && path != prev) {
      if (_backTo == path) {
        _backTo = null;
      } else {
        _backTo = null;
        if (_pathHistory.isEmpty || _pathHistory.last != prev) {
          _pathHistory.add(prev);
        }
      }
    }
    _lastPath = path;
  }

  void _rememberAndGo(String path) {
    final current = _norm(GoRouterState.of(context).uri.path);
    final target = _norm(path);
    if (current == target) return;
    context.go(target);
  }

  bool _tryPathBack() {
    if (_pathHistory.isEmpty) return false;
    final prev = _pathHistory.removeLast();
    _backTo = prev;
    context.go(prev);
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.toString();
    _notePath(_norm(GoRouterState.of(context).uri.path));
    return AgentShellPathBack(
      rememberAndGo: _rememberAndGo,
      tryBack: _tryPathBack,
      child: AppBackScope(
        child: AppPageScaffold(
          backgroundColor: const Color(0xFFF5F5F5),
          drawer: AgentDrawer(roomId: widget.roomId, currentRoute: location),
          body: widget.child,
        ),
      ),
    );
  }
}
