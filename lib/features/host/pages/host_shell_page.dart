import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../config/router/route_paths.dart';
import '../../../data/repositories/providers.dart';
import '../../../shared/widgets/emulator_safe_text_field.dart';
import '../../../shared/widgets/host_bottom_nav.dart';
import '../data/host_mock.dart';

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
  int _badge = 0;

  @override
  void initState() {
    super.initState();
    Future.microtask(_loadBadge);
  }

  Future<void> _loadBadge() async {
    try {
      final repo = ref.read(ownerRepositoryProvider);
      final results = await Future.wait([
        repo.getApplications('up', status: 'PENDING', pageSize: 1),
        repo.getApplications('down', status: 'PENDING', pageSize: 1),
        repo.getApplications('enter', status: 'PENDING', pageSize: 1),
      ]);
      var total = 0;
      for (final r in results) {
        final t = r['total'];
        if (t is num) {
          total += t.toInt();
        } else {
          total += hostRowsOf(r).length;
        }
      }
      if (mounted) setState(() => _badge = total);
    } catch (_) {}
  }

  int get _navIndex {
    final i = widget.navigationShell.currentIndex;
    return i == 0 ? -1 : i - 1;
  }

  void _onNavTap(int index) {
    final branch = index + 1;
    if (branch == widget.navigationShell.currentIndex) return;
    widget.navigationShell.goBranch(branch);
  }

  @override
  Widget build(BuildContext context) {
    return AppPageScaffold(
      body: widget.navigationShell,
      bottomNavigationBar: HostBottomNavBar(
        currentIndex: _navIndex,
        auditBadge: _badge,
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
