import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories/providers.dart';
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

  @override
  HostApplyNotice? build() => null;

  /// 由 lottery WS 转发：PENDING 上/下分/进房入队弹窗。
  Future<void> onWsApplyNotice(Map<String, dynamic> payload) async {
    final status = (payload['status'] ?? '').toString().toUpperCase();
    final applyType = (payload['applyType'] ?? '').toString().toUpperCase();
    final applicationId =
        (payload['applicationId'] ?? payload['id'] ?? '').toString();
    if (applicationId.isEmpty) return;

    if (status != 'PENDING') {
      await ref.read(hostPendingAuditProvider.notifier).refresh();
      if (state?.applicationId == applicationId) {
        _advance();
      } else {
        _queue.removeWhere((e) => e.applicationId == applicationId);
        _seenIds.remove(applicationId);
      }
      return;
    }

    if (applyType != 'UP' && applyType != 'DOWN' && applyType != 'ENTER') {
      await ref.read(hostPendingAuditProvider.notifier).refresh();
      return;
    }

    if (_alreadyQueued(applicationId)) return;

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
    // WS 缺昵称/头像/备注时补全
    if (wsNick.isEmpty || wsAvatar.isEmpty || (applyType == 'ENTER' && wsRemark.isEmpty)) {
      notice = await _enrich(notice);
    } else if (notice.nickname.isEmpty) {
      notice = notice.copyWith(nickname: '玩家');
    }

    _enqueue(notice, bumpBadge: true);
  }

  bool _alreadyQueued(String applicationId) {
    return _seenIds.contains(applicationId) ||
        state?.applicationId == applicationId ||
        _queue.any((e) => e.applicationId == applicationId);
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
    _seenIds.remove(applicationId);
    if (state?.applicationId == applicationId) {
      _advance();
    } else {
      _queue.removeWhere((e) => e.applicationId == applicationId);
    }
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
