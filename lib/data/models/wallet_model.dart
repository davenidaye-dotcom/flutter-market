class WalletSummaryModel {
  const WalletSummaryModel({
    required this.availablePoints,
    required this.todayTurnover,
    required this.pendingRebate,
    required this.todayWinLoss,
  });

  final double availablePoints;
  final double todayTurnover;
  final double pendingRebate;
  final double todayWinLoss;

  static const mock = WalletSummaryModel(
    availablePoints: 10658,
    todayTurnover: 0,
    pendingRebate: 0,
    todayWinLoss: 0,
  );
}
