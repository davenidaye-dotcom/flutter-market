class WalletSummaryModel {
  const WalletSummaryModel({
    required this.availablePoints,
    required this.todayTurnover,
    required this.pendingRebate,
    required this.paidRebate,
    required this.todayWinLoss,
    this.playMode = 'REAL',
  });

  final double availablePoints;
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
    todayTurnover: 0,
    pendingRebate: 0,
    paidRebate: 0,
    todayWinLoss: 0,
  );
}
