import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../shared/widgets/emulator_safe_text_field.dart';
import '../widgets/agent_ui.dart';

/// 代理壳 — 侧栏导航 + 顶栏由各页 AgentPageFrame 提供
class AgentShellPage extends StatelessWidget {
  const AgentShellPage({super.key, required this.roomId, required this.child});

  final String roomId;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.toString();
    return AppPageScaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      drawer: AgentDrawer(roomId: roomId, currentRoute: location),
      body: child,
    );
  }
}
