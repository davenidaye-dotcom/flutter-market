import 'package:letou_app/data/models/wallet_model.dart';
import 'package:letou_app/data/repositories/wallet_repository.dart';

class FakeWalletRepository extends WalletRepository {
  FakeWalletRepository({this.summary = WalletSummaryModel.mock}) : super(client: null);

  final WalletSummaryModel summary;

  @override
  Future<WalletSummaryModel> getSummary(String roomId) async => summary;
}
