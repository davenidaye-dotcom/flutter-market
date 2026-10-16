import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories/providers.dart';
import '../../auth/providers/auth_session_provider.dart';
import '../data/host_mock.dart';
import 'host_pending_audit_provider.dart';

/// WS `APPLY_NOTICE` 待弹窗（房主端全局，一次一条，其余排队）。
class HostApplyNotice {
  const HostApplyNotice({
    required this.applicationId,
    required this.applyType,
    required this.applicantAccountId,
    this.amount,
    this.nickname = '',
    this.avatar,
    this.remark = '',
  });

  final String applicationId;
  /// UP / DOWN / ENTER
  final String applyType;
  final String applicantAccountId;
  final double? amount;
  final String nickname;
  final String? avatar;
  /// 玩家申请备注（进房说明等）
  final String remark;

  bool get isDown => applyType.toUpperCase() == 'DOWN';

  bool get isEnter => applyType.toUpperCase() == 'ENTER';

  AuditType get auditType {
    final t = applyType.toUpperCase();
    if (t == 'DOWN') return AuditType.down;
    if (t == 'ENTER') return AuditType.join;
    return AuditType.up;
  }

  String get actionLabel {
    switch (applyType.toUpperCase()) {
      case 'DOWN':
        return '申请下分';
      case 'ENTER':
        return '申请进房';
      default:
        return '申请上分';
    }
  }

  HostApplyNotice copyWith({
    String? nickname,
    String? avatar,
    double? amount,
    String? remark,
  }) {
    return HostApplyNotice(
      applicationId: applicationId,
      applyType: applyType,
      applicantAccountId: applicantAccountId,
      amount: amount ?? this.amount,
      nickname: nickname ?? this.nickname,
      avatar: avatar ?? this.avatar,
      remark: remark ?? this.remark,
    );
  }
}

final hostApplyNoticeProvider =
    NotifierProvider<HostApplyNoticeNotifier, HostApplyNotice?>(
  HostApplyNoticeNotifier.new,
);

class HostApplyNoticeNotifier extends Notifier<HostApplyNotice?> {
  final List<HostApplyNotice> _queue = [];
  final Set<String> _seenIds = {};
  final Set<String> _inflight = {};
  bool _syncing = false;

  @override
  HostApplyNotice? build() => null;

  /// 由 lottery WS 转发：PENDING 上/下分/进房立刻入队。房间频道和 user 频道会各来一次。
  Future<void> onWsApplyNotice(
    Map<String, dynamic> payload, {
    bool bumpBadge = true,
  }) async {
    final status = (payload['status'] ?? '').toString().toUpperCase();
    final applyType = (payload['applyType'] ?? '').toString().toUpperCase();
    final applicationId =
        (payload['applicationId'] ?? payload['id'] ?? '').toString();
    if (applicationId.isEmpty) return;

    if (status != 'PENDING') {
      // 房间频道和 user 频道会各推一次。先同步关掉，避免两次都把队列往下拨。
      _finish(applicationId);
      Future.microtask(() {
        ref.read(hostPendingAuditProvider.notifier).refresh();
      });
      return;
    }

    if (applyType != 'UP' && applyType != 'DOWN' && applyType != 'ENTER') {
      await ref.read(hostPendingAuditProvider.notifier).refresh();
      return;
    }

    if (_alreadyQueued(applicationId) || _inflight.contains(applicationId)) {
      return;
    }
    _inflight.add(applicationId);

    final amountRaw = payload['amount'];
    final amount = applyType == 'ENTER'
        ? null
        : (amountRaw is num
            ? amountRaw.toDouble()
            : double.tryParse('$amountRaw'));
    final accountId =
        (payload['applicantAccountId'] ?? payload['accountId'] ?? '')
            .toString();
    final wsNick = (payload['nickname'] ??
            payload['applicantName'] ??
            payload['displayName'] ??
            '')
        .toString()
        .trim();
    final wsAvatar = (payload['avatar'] ?? payload['avatarUrl'] ?? '')
        .toString()
        .trim();
    final wsRemark = (payload['remark'] ?? '').toString().trim();

    var notice = HostApplyNotice(
      applicationId: applicationId,
      applyType: applyType,
      applicantAccountId: accountId,
      amount: amount,
      nickname: wsNick,
      avatar: wsAvatar.isEmpty ? null : wsAvatar,
      remark: wsRemark,
    );
    // 先弹。补资料放在后面，避免接口没返回时弹窗一直不出现。
    _enqueue(notice, bumpBadge: bumpBadge);
    try {
      if (wsNick.isEmpty ||
          wsAvatar.isEmpty ||
          (applyType == 'ENTER' && wsRemark.isEmpty)) {
        notice = await _enrich(notice);
        _replaceIfQueued(notice);
      }
    } finally {
      _inflight.remove(applicationId);
    }
  }

  /// 漏掉 WS 时，用近 15 分钟内仍待审的单补弹。已关掉的单不会再弹。
  Future<void> syncRecentPending() async {
    if (!ref.read(authSessionProvider).isHostSide) return;
    if (_syncing) return;
    _syncing = true;
    try {
      final repo = ref.read(ownerRepositoryProvider);
      final pages = await Future.wait([
        repo.getApplications('up', status: 'PENDING', pageSize: 20),
        repo.getApplications('down', status: 'PENDING', pageSize: 20),
        repo.getApplications('enter', status: 'PENDING', pageSize: 20),
      ]);
      const types = ['UP', 'DOWN', 'ENTER'];
      final now = DateTime.now();
      for (var i = 0; i < pages.length; i++) {
        for (final row in hostRowsOf(pages[i])) {
          final created = _parseCreatedAt(row['createdAt']);
          if (created == null) continue;
          if (now.difference(created) > const Duration(minutes: 15)) continue;
          await onWsApplyNotice(
            {
              'applicationId': row['applicationId'] ?? row['id'],
              'applyType': (row['applyType'] ?? types[i]).toString(),
              'status': 'PENDING',
              'applicantAccountId':
                  row['applicantAccountId'] ?? row['accountId'],
              'amount': row['amount'],
              'nickname': row['applicantName'] ?? row['nickname'],
              'remark': row['remark'],
            },
            bumpBadge: false,
          );
        }
      }
    } catch (_) {
    } finally {
      _syncing = false;
    }
  }

  void clear() {
    _queue.clear();
    _seenIds.clear();
    _inflight.clear();
    state = null;
  }

  bool _alreadyQueued(String applicationId) {
    return _seenIds.contains(applicationId) ||
        state?.applicationId == applicationId ||
        _queue.any((e) => e.applicationId == applicationId);
  }

  void _replaceIfQueued(HostApplyNotice notice) {
    if (state?.applicationId == notice.applicationId) {
      state = notice;
      return;
    }
    final i = _queue.indexWhere((e) => e.applicationId == notice.applicationId);
    if (i >= 0) _queue[i] = notice;
  }

  void _enqueue(HostApplyNotice notice, {required bool bumpBadge}) {
    if (_alreadyQueued(notice.applicationId)) return;
    _seenIds.add(notice.applicationId);
    if (state == null) {
      state = notice;
    } else {
      _queue.add(notice);
    }
    if (bumpBadge) {
      ref.read(hostPendingAuditProvider.notifier).bump(notice.auditType);
      Future.microtask(() {
        ref.read(hostPendingAuditProvider.notifier).refresh();
      });
    }
  }

  Future<HostApplyNotice> _enrich(HostApplyNotice notice) async {
    try {
      final repo = ref.read(ownerRepositoryProvider);
      final kind = notice.isEnter
          ? 'enter'
          : (notice.isDown ? 'down' : 'up');
      var nick = notice.nickname;
      var amount = notice.amount;
      String? avatar = notice.avatar;
      var remark = notice.remark;

      try {
        final page = await repo.getApplications(
          kind,
          status: 'PENDING',
          pageSize: 50,
        );
        for (final row in hostRowsOf(page)) {
          final id = (row['applicationId'] ?? row['id'] ?? '').toString();
          if (id != notice.applicationId) continue;
          final n = (row['applicantName'] ??
                  row['nickname'] ??
                  row['displayName'] ??
                  row['applicantUsername'] ??
                  row['username'] ??
                  '')
              .toString();
          if (n.isNotEmpty) nick = n;
          final r = (row['remark'] ?? '').toString().trim();
          if (r.isNotEmpty) remark = r;
          if (!notice.isEnter) {
            final a = row['amount'];
            if (a is num) {
              amount = a.toDouble();
            } else {
              amount = double.tryParse('$a') ?? amount;
            }
          }
          break;
        }
      } catch (_) {}

      if (notice.applicantAccountId.isNotEmpty) {
        try {
          final detail =
              await repo.getMemberDetail(notice.applicantAccountId);
          final n = (detail['nickname'] ??
                  detail['displayName'] ??
                  detail['username'] ??
                  '')
              .toString();
          if (nick.isEmpty && n.isNotEmpty) nick = n;
          final av =
              (detail['avatar'] ?? detail['avatarUrl'] ?? '').toString().trim();
          if (av.isNotEmpty) avatar = av;
        } catch (_) {}
      }

      if (nick.isEmpty) {
        nick = notice.applicantAccountId.isNotEmpty
            ? notice.applicantAccountId
            : '玩家';
      }
      return notice.copyWith(
        nickname: nick,
        avatar: avatar,
        amount: amount,
        remark: remark,
      );
    } catch (_) {
      return notice.copyWith(
        nickname: notice.nickname.isEmpty ? '玩家' : notice.nickname,
      );
    }
  }

  void onReviewed(String applicationId) {
    // 保留 seen。通过/拒绝后近 15 分钟的补拉不能把同一单再弹出来。
    _finish(applicationId);
  }

  /// 这单已经结束（审核、撤销、或另一端已处理）。重复通知只关一次。
  void _finish(String applicationId) {
    if (applicationId.isEmpty) return;
    _seenIds.add(applicationId);
    _inflight.remove(applicationId);
    if (state?.applicationId == applicationId) {
      _advance();
      return;
    }
    _queue.removeWhere((e) => e.applicationId == applicationId);
  }

  /// 点 X 取消：关掉当前弹窗，不审核；保留 seen，避免同单再弹。
  void dismissCurrent() {
    _advance();
  }

  void _advance() {
    if (_queue.isEmpty) {
      state = null;
      return;
    }
    state = _queue.removeAt(0);
  }
}

DateTime? _parseCreatedAt(dynamic raw) {
  if (raw == null) return null;
  if (raw is num) {
    final ms = raw.toInt();
    if (ms <= 0) return null;
    return DateTime.fromMillisecondsSinceEpoch(ms);
  }
  final text = raw.toString().trim();
  if (text.isEmpty) return null;
  return DateTime.tryParse(text.replaceFirst(' ', 'T'));
}
