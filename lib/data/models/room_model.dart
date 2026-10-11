class RoomModel {
  const RoomModel({
    required this.id,
    required this.name,
    this.ownerNickname,
    this.thumbnailUrl,
    this.numericId,
    this.enterMode,
    this.hasEnterPassword = false,
    this.enterApproved = false,
    this.status,
    this.betConfirm = false,
    this.playMode = 'REAL',
  });

  /// Room code used in routes (e.g. 679010)
  final String id;
  final String name;
  /// 房主昵称（大厅顶栏；缺省时可回退 [name]）
  final String? ownerNickname;
  final String? thumbnailUrl;

  /// Backend numeric roomId for X-Room-Id / query
  final String? numericId;

  /// DIRECT | AUDIT（校验接口返回时可用）
  final String? enterMode;

  final bool hasEnterPassword;

  /// 当前玩家已通过进房审核（或已是成员），可直接进
  final bool enterApproved;
  final String? status;

  /// 房主开启「下注确认」后，玩家下注前需二次确认
  final bool betConfirm;

  /// 当前账号在该房的玩法：REAL / TRIAL / ATMOSPHERE
  final String playMode;

  bool get isTrial => playMode.toUpperCase() == 'TRIAL';

  bool get requiresEnterAudit {
    final m = (enterMode ?? '').toUpperCase();
    return m == 'AUDIT' || m == 'APPLY' || m == 'NEED_AUDIT';
  }

  String get roomCode => id;

  factory RoomModel.fromJson(Map<String, dynamic> json) => RoomModel(
        id: json['roomCode']?.toString() ?? json['id']?.toString() ?? '',
        name: json['roomName'] as String? ?? json['name'] as String? ?? '',
        ownerNickname: json['ownerNickname']?.toString() ??
            json['owner_nickname']?.toString(),
        thumbnailUrl: json['coverUrl'] as String? ?? json['thumbnailUrl'] as String?,
        numericId: json['roomId']?.toString(),
        enterMode: json['enterMode']?.toString() ?? json['enter_mode']?.toString(),
        hasEnterPassword: json['hasEnterPassword'] == true ||
            json['needEnterPassword'] == true ||
            (json['enterPasswordHash'] != null &&
                '${json['enterPasswordHash']}'.isNotEmpty),
        enterApproved: json['enterApproved'] == true || json['enterApproved'] == 1,
        status: json['status']?.toString(),
        betConfirm: json['betConfirm'] == true || json['betConfirm'] == 1,
        playMode: json['playMode']?.toString() ?? 'REAL',
      );

  /// 大厅顶栏优先房主昵称，其次房间名。
  String get hallTitle {
    final nick = ownerNickname?.trim() ?? '';
    if (nick.isNotEmpty) return nick;
    final n = name.trim();
    return n;
  }
}

class RoomHistoryModel extends RoomModel {
  const RoomHistoryModel({
    required super.id,
    required super.name,
    super.thumbnailUrl,
  });
}

class AnnouncementModel {
  const AnnouncementModel({
    required this.id,
    required this.title,
    required this.content,
    required this.createdAt,
  });

  final String id;
  final String title;
  final String content;
  final DateTime createdAt;
}
