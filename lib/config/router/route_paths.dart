/// 路由路径常量
abstract final class RoutePaths {
  static const login = '/login';
  static const register = '/register';
  static const captcha = '/captcha';
  static const home = '/home';
  static const personalSettings = '/personal-settings';
  static const changePassword = '/change-password';

  static String roomLottery(String roomId) => '/room/$roomId/lottery';
  static String roomService(String roomId) => '/room/$roomId/service';
  static String roomWallet(String roomId) => '/room/$roomId/wallet';
  static String roomIntro(String roomId) => '/room/$roomId/intro';
  static String roomProfile(String roomId) => '/room/$roomId/profile';
  static String chatBet(String roomId, String gameId) => '/room/$roomId/chat/$gameId';
  static String marketBet(String roomId, String gameId) => '/room/$roomId/chat/$gameId/market';

  /// 钱包子页（全屏，无底部 Tab）
  static String applyRecords(String roomId) => '/room/$roomId/records/apply';
  static String welfareReport(String roomId) => '/room/$roomId/records/welfare';
  static String betRecords(String roomId) => '/room/$roomId/records/bet';
  static String pointsChange(String roomId) => '/room/$roomId/records/points';
  static String agentInfo(String roomId) => '/room/$roomId/records/agent';

  /// 房主端壳
  static String hostLottery(String roomId) => '/host/$roomId/lottery';
  static String hostService(String roomId) => '/host/$roomId/service';
  static String hostManage(String roomId) => '/host/$roomId/manage';
  static String hostCenter(String roomId) => '/host/$roomId/center';
  static String hostAudit(String roomId) => '/host/$roomId/audit';

  /// 房主 — 房间管理子页
  static String hostBasicSettings(String roomId) => '/host/$roomId/basic-settings';
  static String hostMembers(String roomId) => '/host/$roomId/members';
  static String hostMemberDetail(String roomId, String memberId) =>
      '/host/$roomId/members/$memberId';
  static String hostAgents(String roomId) => '/host/$roomId/agents';
  static String hostOddsLimits(String roomId) => '/host/$roomId/odds-limits';
  static String hostDefaultRebate(String roomId) => '/host/$roomId/default-rebate';
  static String hostBatchRebate(String roomId) => '/host/$roomId/batch-rebate';
  static String hostGamesManage(String roomId) => '/host/$roomId/games';
  static String hostAnnouncements(String roomId) => '/host/$roomId/announcements';
  static String hostAtmosphere(String roomId) => '/host/$roomId/atmosphere';
  static String hostAssistants(String roomId) => '/host/$roomId/assistants';
  static String hostOpLogs(String roomId) => '/host/$roomId/op-logs';
  static String hostRoomSettings(String roomId) => '/host/$roomId/room-settings';
  static String hostAdvanceRebate(String roomId) => '/host/$roomId/advance-rebate';

  /// 房主 — 飞单
  static String hostFlyHub(String roomId) => '/host/$roomId/fly';
  static String hostFlyBind(String roomId) => '/host/$roomId/fly/bind';
  static String hostFlyOdds(String roomId) => '/host/$roomId/fly/odds';
  static String hostFlyReport(String roomId) => '/host/$roomId/fly/report';
  static String hostFlyBalance(String roomId) => '/host/$roomId/fly/balance';
  static String hostFlyLogs(String roomId) => '/host/$roomId/fly/logs';

  /// 房主 — 管理中心报表
  static String hostRoomReport(String roomId) => '/host/$roomId/reports/room';
  static String hostScoreFlow(String roomId) => '/host/$roomId/reports/score';
  static String hostRebateReport(String roomId) => '/host/$roomId/reports/rebate';

  /// 房主 — 客服会话
  static String hostCsChat(String roomId, String sessionId) =>
      '/host/$roomId/service/$sessionId';

  /// 代理端壳 — 竞品 D:\高铁\代理
  static String agentPersonalInfo(String roomId) => '/agent/$roomId/info';
  static String agentPayment(String roomId) => '/agent/$roomId/payment';
  static String agentAccounts(String roomId) => '/agent/$roomId/accounts';
  static String agentReports(String roomId) => '/agent/$roomId/reports';
  static String agentQuota(String roomId) => '/agent/$roomId/quota';
  static String agentPassword(String roomId) => '/agent/$roomId/password';
}
