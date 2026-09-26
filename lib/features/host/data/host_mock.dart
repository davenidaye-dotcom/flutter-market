// 房主端列表解析 helpers（页面统一用 API 数据，不再使用静态假列表）
import 'package:flutter/material.dart';
import '../../../shared/format/display_number.dart';

class _Member {
  const _Member(
    this.id,
    this.nickname,
    this.username,
    this.userId,
    this.roleLabel,
    this.points, {
    this.avatar,
    this.online = false,
    this.isMood = false,
    this.isTrial = false,
    this.disabled = false,
    this.isAgent = false,
    this.status = 'NORMAL',
    this.remark = '',
  });

  final String id;
  final String nickname;
  final String username;
  final String userId;
  final String roleLabel;
  final int points;
  /// 头像编码 avNN 或 URL
  final String? avatar;
  final bool online;
  final bool isMood;
  final bool isTrial;
  final bool disabled;
  final bool isAgent;
  /// NORMAL / FROZEN / BAN_ENTER / DISABLED
  final String status;
  /// 房间备注。列表有备注时优先显示备注。
  final String remark;

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
  final parsed = balance is num ? balance : num.tryParse('$balance');
  final pts = (parsed ?? 0).round();
  final status = (m['status'] ?? '').toString().toUpperCase();
  final role = (m['roleLabel'] ?? m['role'] ?? '普通用户').toString();
  final online = m['online'] == true || (m['presence']?.toString().toUpperCase() == 'IN');
  final isAgent = m['isAgent'] == true || role.contains('代理');
  // 以后端 playMode 为准：ATMOSPHERE=机器人/气氛号，TRIAL=试玩号
  final playMode = (m['playMode'] ?? '').toString().toUpperCase();
  final isMood = playMode == 'ATMOSPHERE' ||
      m['isRobot'] == true ||
      m['isMood'] == true ||
      role.contains('气氛') ||
      role.contains('机器');
  final isTrial = playMode == 'TRIAL' ||
      m['isFake'] == true ||
      m['isTrial'] == true ||
      role.contains('假人') ||
      role.contains('试玩');
  final disabled = status == 'FROZEN' ||
      status == 'BAN_ENTER' ||
      status == 'DISABLED' ||
      m['disabled'] == true;
  final avatar = (m['avatar'] ?? m['avatarUrl'] ?? '').toString().trim();
  return HostMember(
    id,
    nick.isEmpty ? user : nick,
    user,
    id,
    role,
    pts,
    avatar: avatar.isEmpty ? null : avatar,
    online: online,
    isMood: isMood,
    isTrial: isTrial,
    disabled: disabled,
    isAgent: isAgent,
    status: status.isEmpty ? 'NORMAL' : status,
    remark: (m['remark'] ?? '').toString().trim(),
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
/// 去掉小数尾零，不再按 fraction 补 0。fraction 仅保留给旧调用。
String hostNumStr(dynamic value, {int fraction = 0}) {
  if (fraction < 0) return displayNumber(value);
  return displayNumber(value);
}

/// 盈亏：盈利 `+` 绿色，亏损 `-` 红色，零为中性色无符号。
class HostSignedPnl {
  const HostSignedPnl({required this.text, required this.color});

  final String text;
  final Color color;

  static const green = Color(0xFF2E9E5B);
  static const red = Color(0xFFE53935);

  factory HostSignedPnl.of(
    dynamic value, {
    int fraction = 2,
    Color zeroColor = const Color(0xFF222222),
  }) {
    final raw = hostNumStr(value, fraction: fraction);
    final n = double.tryParse(raw.replaceAll(',', '')) ?? 0;
    if (n > 0) {
      final t = raw.startsWith('+') ? raw : '+$raw';
      return HostSignedPnl(text: t, color: green);
    }
    if (n < 0) {
      return HostSignedPnl(text: raw, color: red);
    }
    return HostSignedPnl(text: raw, color: zeroColor);
  }
}

/// 操作日志 action 码 → 中文（接口仍返回英文码，展示侧翻译）
String hostOpActionLabel(String? action) {
  final a = (action ?? '').trim().toUpperCase();
  if (a.isEmpty) return '-';
  if (a.startsWith('APPLICATION_')) return '审核';
  if (a.startsWith('ASSISTANT')) return '协管';
  return switch (a) {
    'MEMBER_CREDIT' => '上下分',
    'MEMBER_AGENT' || 'MEMBER_DOWNLINE' => '代理',
    'MEMBER_TRIAL' => '试玩号',
    'MEMBER_STATUS' || 'MEMBER_REBATE' || 'MEMBER_REMARK' || 'MEMBER_DELETE' ||
    'MEMBER_ROBOT' =>
      '用户管理',
    'FEIPAN_BIND' || 'FEIPAN_UNBIND' || 'FEIPAN_SWITCH' || 'FEIPAN_ODDS' => '飞单',
    'ODDS' => '赔率与限额',
    'REBATE' => '回水',
    'GAME_SETTINGS' => '彩种',
    'ANNOUNCEMENT' => '公告',
    'REDPACK' => '红包',
    'ROOM_NAME' || 'ENTER_PASSWORD' || 'ROOM_FLAGS' => '房间设置',
    _ => a,
  };
}

/// 操作日志 content 里残留英文片段（历史数据）→ 中文
String hostOpContentLabel(String? content) {
  var t = (content ?? '').trim();
  if (t.isEmpty) return t;
  t = t.replaceFirst(RegExp(r'^UP--', caseSensitive: false), '上分--');
  t = t.replaceFirst(RegExp(r'^DOWN--', caseSensitive: false), '下分--');
  t = t.replaceAllMapped(RegExp(r'申请(APPROVED|REJECTED|CANCELLED|PENDING)--', caseSensitive: false), (m) {
    final s = m.group(1)!.toUpperCase();
    final zh = switch (s) {
      'APPROVED' => '通过',
      'REJECTED' => '拒绝',
      'CANCELLED' => '取消',
      'PENDING' => '待审',
      _ => s,
    };
    return '申请$zh--';
  });
  t = t.replaceAllMapped(RegExp(r'--(ACTIVE|NORMAL|DISABLED|BAN|BANNED|BLOCK|REMOVED)$', caseSensitive: false), (m) {
    final s = m.group(1)!.toUpperCase();
    final zh = switch (s) {
      'ACTIVE' || 'NORMAL' => '正常',
      'DISABLED' || 'BAN' || 'BANNED' || 'BLOCK' => '封禁',
      'REMOVED' => '已删除',
      _ => s,
    };
    return '--$zh';
  });
  return t;
}

