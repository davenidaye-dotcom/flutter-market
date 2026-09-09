/// 登录/会话角色（以后端返回为准，前端不猜测）
enum AppRole {
  /// 普通玩家（用户端壳）
  player,

  /// 房间代理（代理管理后台壳，竞品 D:\高铁\代理）
  agent,

  /// 房主
  host,

  /// 房主协管（与房主同壳，菜单按权限裁剪）
  hostAssistant,
}

extension AppRoleX on AppRole {
  bool get isHostSide => this == AppRole.host || this == AppRole.hostAssistant;

  bool get isAgentSide => this == AppRole.agent;

  /// 房主登录入口：房主 / 协管 / 代理
  bool get isManagementLoginSide => isHostSide || isAgentSide;

  bool get canPlaceBet => this == AppRole.player;

  String get label => switch (this) {
        AppRole.player => '玩家',
        AppRole.agent => '代理',
        AppRole.host => '房主',
        AppRole.hostAssistant => '协管',
      };

  static AppRole fromApi(String? raw) {
    switch (raw?.toUpperCase()) {
      case 'AGENT':
      case 'ROOM_AGENT':
        return AppRole.agent;
      case 'OWNER':
      case 'HOST':
      case 'ROOM_OWNER':
        return AppRole.host;
      case 'OWNER_DELEGATE':
      case 'HOST_ASSISTANT':
      case 'ASSISTANT':
      case 'CO_HOST':
        return AppRole.hostAssistant;
      case 'PLAYER':
        return AppRole.player;
      case 'AGENT_MEMBER':
      case 'AGENT_DELEGATE':
      case 'EXPERIENCE':
        // App 不允许；勿映射成 player 以免误进玩家壳
        throw FormatException('APP_ROLE_DENIED:$raw');
      default:
        return AppRole.player;
    }
  }

  /// 与后端 APP_LOGIN_TYPES 一致
  static bool isAppLoginAllowedType(String? accountType) {
    final t = accountType?.toUpperCase();
    return t == 'PLAYER' || t == 'OWNER' || t == 'AGENT';
  }
}
