import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../data/repositories/providers.dart';
import '../data/host_mock.dart';

class HostPendingAuditCounts {
  const HostPendingAuditCounts({
    this.up = 0,
    this.down = 0,
    this.enter = 0,
  });

  final int up;
  final int down;
  final int enter;

  int get total => up + down + enter;

  static const empty = HostPendingAuditCounts();

  HostPendingAuditCounts copyWith({int? up, int? down, int? enter}) {
    return HostPendingAuditCounts(
      up: up ?? this.up,
      down: down ?? this.down,
      enter: enter ?? this.enter,
    );
  }
}

int _totalOf(Map<String, dynamic> page) {
  final t = page['total'];
  if (t is num) return t.toInt();
  final parsed = int.tryParse('$t');
  if (parsed != null) return parsed;
  return hostRowsOf(page).length;
}

final hostPendingAuditProvider =
    NotifierProvider<HostPendingAuditNotifier, HostPendingAuditCounts>(
  HostPendingAuditNotifier.new,
);

class HostPendingAuditNotifier extends Notifier<HostPendingAuditCounts> {
  @override
  HostPendingAuditCounts build() {
    Future.microtask(refresh);
    return HostPendingAuditCounts.empty;
  }

  /// 审核通过/拒绝后立刻减角标，避免等接口回来前数字卡住
  void onReviewed(AuditType type) {
    final c = state;
    switch (type) {
      case AuditType.up:
        state = c.copyWith(up: math.max(0, c.up - 1));
      case AuditType.down:
        state = c.copyWith(down: math.max(0, c.down - 1));
      case AuditType.join:
        state = c.copyWith(enter: math.max(0, c.enter - 1));
    }
  }

  Future<void> refresh() async {
    try {
      final repo = ref.read(ownerRepositoryProvider);
      final results = await Future.wait([
        repo.getApplications('up', status: 'PENDING', pageSize: 1),
        repo.getApplications('down', status: 'PENDING', pageSize: 1),
        repo.getApplications('enter', status: 'PENDING', pageSize: 1),
      ]);
      state = HostPendingAuditCounts(
        up: _totalOf(results[0]),
        down: _totalOf(results[1]),
        enter: _totalOf(results[2]),
      );
    } catch (_) {
      // 保持现有角标，避免闪成 0
    }
  }
}
