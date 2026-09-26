class RoomModel {
  const RoomModel({
    required this.id,
    required this.name,
    this.thumbnailUrl,
    this.numericId,
    this.enterMode,
    this.hasEnterPassword = false,
    this.status,
    this.betConfirm = false,
    this.playMode = 'REAL',
  });

  /// Room code used in routes (e.g. 679010)
  final String id;
  final String name;
  final String? thumbnailUrl;

  /// Backend numeric roomId for X-Room-Id / query
  final String? numericId;

  /// DIRECT | AUDIT（校验接口返回时可用）
  final String? enterMode;

  final bool hasEnterPassword;
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
        thumbnailUrl: json['coverUrl'] as String? ?? json['thumbnailUrl'] as String?,
        numericId: json['roomId']?.toString(),
        enterMode: json['enterMode']?.toString() ?? json['enter_mode']?.toString(),
        hasEnterPassword: json['hasEnterPassword'] == true ||
            json['needEnterPassword'] == true ||
            (json['enterPasswordHash'] != null &&
                '${json['enterPasswordHash']}'.isNotEmpty),
        status: json['status']?.toString(),
        betConfirm: json['betConfirm'] == true || json['betConfirm'] == 1,
        playMode: json['playMode']?.toString() ?? 'REAL',
      );
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
