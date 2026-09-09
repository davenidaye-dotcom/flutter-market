// 房主端列表解析 helpers（页面统一用 API 数据，不再使用静态假列表）

class _Member {
  const _Member(
    this.id,
    this.nickname,
    this.username,
    this.userId,
    this.roleLabel,
    this.points, {
    this.online = false,
    this.isMood = false,
    this.isTrial = false,
    this.disabled = false,
    this.isAgent = false,
    this.status = 'NORMAL',
  });

  final String id;
  final String nickname;
  final String username;
  final String userId;
  final String roleLabel;
  final int points;
  final bool online;
  final bool isMood;
  final bool isTrial;
  final bool disabled;
  final bool isAgent;
  /// NORMAL / FROZEN / BAN_ENTER / DISABLED
  final String status;

  String get statusLabel {
    switch (status.toUpperCase()) {
      case 'FROZEN':
        return '已冻结';
      case 'BAN_ENTER':
        return '禁止进房';
      case 'DISABLED':
        return '已禁用';
      case 'NORMAL':
      case '':
        return '正常';
      default:
        return status;
    }
  }
}

typedef HostMember = _Member;

enum AuditType { join, up, down }

class _Audit {
  const _Audit(
    this.id,
    this.type,
    this.nickname,
    this.username,
    this.summary,
    this.time, {
    this.amount,
    this.points,
    this.status = 'PENDING',
  });

  final String id;
  final AuditType type;
  final String nickname;
  final String username;
  final String summary;
  final String time;
  final double? amount;
  final int? points;
  final String status;
}

typedef HostAuditItem = _Audit;

/// Map owner application row to [HostAuditItem].
HostAuditItem hostAuditFromMap(Map<String, dynamic> m, AuditType type) {
  final amount = m['amount'];
  final points = m['points'] ?? m['balance'];
  final amt = amount is num ? amount.toDouble() : double.tryParse('$amount');
  final pts = points is num ? points.toInt() : int.tryParse('$points');
  final nick = (m['applicantName'] ?? m['nickname'] ?? m['displayName'] ?? '').toString();
  final user = (m['applicantUsername'] ?? m['username'] ?? '').toString();
  final id = (m['applicationId'] ?? m['id'] ?? '').toString();
  final time = (m['createdAt'] ?? m['applyTime'] ?? '').toString();
  final status = (m['status'] ?? 'PENDING').toString();
  var summary = switch (type) {
    AuditType.up => '申请上分 ${amt ?? ''}',
    AuditType.down => '申请下分 ${amt ?? ''}',
    AuditType.join => '申请加入房间',
  };
  if ((m['summary'] ?? m['remark'] ?? '').toString().isNotEmpty) {
    summary = (m['summary'] ?? m['remark']).toString();
  }
  return HostAuditItem(
    id,
    type,
    nick.isEmpty ? user : nick,
    user,
    summary,
    time,
    amount: amt,
    points: pts,
    status: status,
  );
}

/// Map owner member row to [HostMember].
HostMember hostMemberFromMap(Map<String, dynamic> m) {
  final id = (m['accountId'] ?? m['id'] ?? '').toString();
  final nick = (m['nickname'] ?? m['displayName'] ?? '').toString();
  final user = (m['username'] ?? '').toString();
  final balance = m['balance'] ?? m['points'] ?? 0;
  final pts = balance is num ? balance.toInt() : int.tryParse('$balance') ?? 0;
  final status = (m['status'] ?? '').toString().toUpperCase();
  final role = (m['roleLabel'] ?? m['role'] ?? '普通用户').toString();
  final online = m['online'] == true || (m['presence']?.toString().toUpperCase() == 'IN');
  final isAgent = m['isAgent'] == true || role.contains('代理');
  final isMood = m['isMood'] == true || role.contains('气氛') || role.contains('机器');
  final isTrial = m['isTrial'] == true || role.contains('试玩');
  final disabled = status == 'FROZEN' ||
      status == 'BAN_ENTER' ||
      status == 'DISABLED' ||
      m['disabled'] == true;
  return HostMember(
    id,
    nick.isEmpty ? user : nick,
    user,
    id,
    role,
    pts,
    online: online,
    isMood: isMood,
    isTrial: isTrial,
    disabled: disabled,
    isAgent: isAgent,
    status: status.isEmpty ? 'NORMAL' : status,
  );
}

/// Normalize owner list payloads: rows / list / records / bare List.
List<Map<String, dynamic>> hostRowsOf(dynamic data) {
  if (data is List) {
    return data.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }
  if (data is Map) {
    final m = Map<String, dynamic>.from(data);
    for (final key in ['rows', 'list', 'records', 'items', 'games']) {
      final v = m[key];
      if (v is List) {
        return v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
      }
    }
  }
  return const [];
}

/// Format numeric API fields for host UI display.
String hostNumStr(dynamic value, {int fraction = 0}) {
  if (value == null) return '0';
  if (value is num) {
    if (fraction <= 0) {
      return value == value.roundToDouble() ? '${value.toInt()}' : value.toString();
    }
    return value.toStringAsFixed(fraction);
  }
  final parsed = num.tryParse('$value');
  if (parsed == null) return '$value';
  if (fraction <= 0) {
    return parsed == parsed.roundToDouble() ? '${parsed.toInt()}' : parsed.toString();
  }
  return parsed.toStringAsFixed(fraction);
}

