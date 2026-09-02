import 'app_role.dart';

class UserModel {
  const UserModel({
    required this.id,
    required this.username,
    required this.nickname,
    this.avatarUrl,
    this.role = AppRole.player,
    this.roomId,
  });

  final String id;
  final String username;
  final String nickname;
  final String? avatarUrl;
  final AppRole role;

  /// 房主/协管绑定的房间；玩家可为空（首页再选房）
  final String? roomId;

  bool get isHostSide => role.isHostSide;
  bool get isAgentSide => role.isAgentSide;
  bool get canPlaceBet => role.canPlaceBet;

  factory UserModel.fromJson(Map<String, dynamic> json) => UserModel(
        id: json['id']?.toString() ?? '',
        username: json['username'] as String? ?? '',
        nickname: json['nickname'] as String? ?? '',
        avatarUrl: json['avatarUrl'] as String?,
        role: AppRoleX.fromApi(json['role'] as String? ?? json['accountType'] as String?),
        roomId: json['roomId']?.toString() ?? json['roomCode']?.toString(),
      );

  /// Map login/register envelope `data` from member/portal auth.
  factory UserModel.fromLoginPayload(
    Map<String, dynamic> data, {
    required String fallbackUsername,
  }) {
    final profile = data['profile'] is Map
        ? Map<String, dynamic>.from(data['profile'] as Map)
        : <String, dynamic>{};
    final header = data['header'] is Map
        ? Map<String, dynamic>.from(data['header'] as Map)
        : <String, dynamic>{};
    final room = data['room'] is Map
        ? Map<String, dynamic>.from(data['room'] as Map)
        : null;

    return UserModel(
      id: header['displayId']?.toString() ??
          data['accountId']?.toString() ??
          '',
      username: profile['username']?.toString() ?? fallbackUsername,
      nickname: profile['displayName']?.toString() ??
          profile['nickname']?.toString() ??
          profile['username']?.toString() ??
          fallbackUsername,
      avatarUrl: profile['avatarUrl']?.toString() ?? header['avatarUrl']?.toString(),
      role: AppRoleX.fromApi(data['accountType']?.toString()),
      // Routes use roomCode; numeric roomId lives in SessionStore
      roomId: room?['roomCode']?.toString() ?? room?['roomId']?.toString(),
    );
  }

  UserModel copyWith({
    String? id,
    String? username,
    String? nickname,
    String? avatarUrl,
    AppRole? role,
    String? roomId,
  }) =>
      UserModel(
        id: id ?? this.id,
        username: username ?? this.username,
        nickname: nickname ?? this.nickname,
        avatarUrl: avatarUrl ?? this.avatarUrl,
        role: role ?? this.role,
        roomId: roomId ?? this.roomId,
      );

  static const mock = UserModel(
    id: '202565468',
    username: 'abc658',
    nickname: '小白爱你',
    role: AppRole.player,
  );

  static const mockHost = UserModel(
    id: 'host1001',
    username: 'host001',
    nickname: '房主一号',
    role: AppRole.host,
    roomId: '1001',
  );

  /// 写死代理演示账号 — 房主登录口输入 abcd658 进入代理壳
  static const mockAgent = UserModel(
    id: '202622963',
    username: 'abcd658',
    nickname: 'abcd658',
    role: AppRole.agent,
    roomId: '1001',
  );
}
