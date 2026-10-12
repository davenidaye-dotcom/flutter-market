class WalletSummaryModel {
  const WalletSummaryModel({
    required this.availablePoints,
    required this.totalAssets,
    required this.todayTurnover,
    required this.pendingRebate,
    required this.paidRebate,
    required this.todayWinLoss,
    this.playMode = 'REAL',
  });

  /// 可下注 / 房间顶栏积分（balance − hold − frozen）
  final double availablePoints;

  /// 钱包「总资产」（账面 balance，含下分冻结）
  final double totalAssets;

  final double todayTurnover;
  final double pendingRebate;

  /// 当前业务日已领取回水
  final double paidRebate;
  final double todayWinLoss;

  /// REAL / TRIAL / ATMOSPHERE（与后端 MemberWalletVo.playMode 一致）
  final String playMode;

  bool get isTrial => playMode.toUpperCase() == 'TRIAL';

  static const mock = WalletSummaryModel(
    availablePoints: 10658,
    totalAssets: 10658,
    todayTurnover: 0,
    pendingRebate: 0,
    paidRebate: 0,
    todayWinLoss: 0,
  );
}
