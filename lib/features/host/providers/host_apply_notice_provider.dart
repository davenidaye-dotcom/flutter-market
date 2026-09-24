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
  });

  final String applicationId;
  /// UP / DOWN / ENTER
  final String applyType;
  final String applicantAccountId;
  final double? amount;
  final String nickname;
  final String? avatar;

  bool get isDown => applyType.toUpperCase() == 'DOWN';

  AuditType get auditType =>
      isDown ? AuditType.down : AuditType.up;

  String get actionLabel => isDown ? '申请下分' : '申请上分';

  HostApplyNotice copyWith({
    String? nickname,
    String? avatar,
    double? amount,
  }) {
    return HostApplyNotice(
      applicationId: applicationId,
      applyType: applyType,
      applicantAccountId: applicantAccountId,
      amount: amount ?? this.amount,
      nickname: nickname ?? this.nickname,
      avatar: avatar ?? this.avatar,
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

  /// 由 lottery WS 转发：仅 PENDING 上/下分入队弹窗。
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

    // 进房等其它类型：只刷角标
    if (applyType != 'UP' && applyType != 'DOWN') {
      await ref.read(hostPendingAuditProvider.notifier).refresh();
      return;
    }

    if (_seenIds.contains(applicationId) ||
        state?.applicationId == applicationId ||
        _queue.any((e) => e.applicationId == applicationId)) {
      return;
    }

    final amountRaw = payload['amount'];
    final amount = amountRaw is num
        ? amountRaw.toDouble()
        : double.tryParse('$amountRaw');
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

    var notice = HostApplyNotice(
      applicationId: applicationId,
      applyType: applyType,
      applicantAccountId: accountId,
      amount: amount,
      nickname: wsNick,
      avatar: wsAvatar.isEmpty ? null : wsAvatar,
    );
    // WS 已带齐昵称/头像则跳过二次拉取；否则补全
    if (wsNick.isEmpty || wsAvatar.isEmpty) {
      notice = await _enrich(notice);
    } else if (notice.nickname.isEmpty) {
      notice = notice.copyWith(nickname: '玩家');
    }
    _seenIds.add(applicationId);

    if (state == null) {
      state = notice;
    } else {
      _queue.add(notice);
    }

    final badge = ref.read(hostPendingAuditProvider.notifier);
    if (applyType == 'UP') {
      badge.bump(AuditType.up);
    } else {
      badge.bump(AuditType.down);
    }
    Future.microtask(() {
      ref.read(hostPendingAuditProvider.notifier).refresh();
    });
  }

  Future<HostApplyNotice> _enrich(HostApplyNotice notice) async {
    try {
      final repo = ref.read(ownerRepositoryProvider);
      final kind = notice.isDown ? 'down' : 'up';
      var nick = notice.nickname;
      var amount = notice.amount;
      String? avatar = notice.avatar;

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
          final a = row['amount'];
          if (a is num) {
            amount = a.toDouble();
          } else {
            amount = double.tryParse('$a') ?? amount;
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
      return notice.copyWith(nickname: nick, avatar: avatar, amount: amount);
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

  void dismissCurrent() {
    final cur = state;
    if (cur != null) _seenIds.remove(cur.applicationId);
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
