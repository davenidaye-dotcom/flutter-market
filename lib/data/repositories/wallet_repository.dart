import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../models/wallet_model.dart';

class WalletRepository {
  WalletRepository({ApiClient? client}) : _client = client ?? ApiClient.instance;

  final ApiClient _client;

  Future<WalletSummaryModel> getSummary(String roomId) async {
    final _ = roomId;
    final data = await _client.get('/member/wallet');
    if (data is! Map) {
      throw const ApiException(message: '钱包数据异常');
    }
    final m = Map<String, dynamic>.from(data);
    double n(dynamic v) =>
        v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
    return WalletSummaryModel(
      availablePoints: n(m['totalAssets'] ?? m['available'] ?? m['availablePoints'] ?? m['balance']),
      todayTurnover: n(m['turnover'] ?? m['todayTurnover']),
      // rebate = 个人回水比例%；pendingRebate = 待领金额
      pendingRebate: n(m['pendingRebate']),
      todayWinLoss: n(m['profitLoss'] ?? m['todayWinLoss'] ?? m['winLoss']),
    );
  }

  Future<Map<String, dynamic>> getAdjustments({
    String? startDate,
    String? endDate,
    int pageNum = 1,
    int pageSize = 20,
  }) async {
    final data = await _client.get('/member/wallet/adjustments', query: {
      if (startDate != null) 'startDate': startDate,
      if (endDate != null) 'endDate': endDate,
      'pageNum': pageNum,
      'pageSize': pageSize,
    });
    return _asMap(data);
  }

  Future<Map<String, dynamic>> getWelfare({
    required String type,
    String? startDate,
    String? endDate,
  }) async {
    final data = await _client.get('/member/welfare', query: {
      'type': type,
      if (startDate != null) 'startDate': startDate,
      if (endDate != null) 'endDate': endDate,
    });
    return _asMap(data);
  }

  Future<Map<String, dynamic>> getBets({
    String? startDate,
    String? endDate,
    String? issueNo,
    String walletType = 'REAL',
    int pageNum = 1,
    int pageSize = 20,
  }) async {
    final data = await _client.get('/member/bets', query: {
      if (startDate != null) 'startDate': startDate,
      if (endDate != null) 'endDate': endDate,
      if (issueNo != null && issueNo.isNotEmpty) 'issueNo': issueNo,
      'walletType': walletType,
      'pageNum': pageNum,
      'pageSize': pageSize,
    });
    return _asMap(data);
  }

  Future<Map<String, dynamic>> getBetDetail(String orderId) async {
    final data = await _client.get('/member/bets/$orderId');
    return _asMap(data);
  }

  Future<Map<String, dynamic>> getPointsChanges({
    String? issueNo,
    int pageNum = 1,
    int pageSize = 20,
  }) async {
    final data = await _client.get('/member/points/changes', query: {
      if (issueNo != null && issueNo.isNotEmpty) 'issueNo': issueNo,
      'pageNum': pageNum,
      'pageSize': pageSize,
    });
    return _asMap(data);
  }

  Future<Map<String, dynamic>> submitApplication({
    required String applyType,
    required num amount,
    String? remark,
    String? requestId,
  }) async {
    final data = await _client.post(
      '/member/wallet/applications',
      data: {
        'applyType': applyType,
        'amount': amount,
        if (remark != null && remark.isNotEmpty) 'remark': remark,
        if (requestId != null && requestId.isNotEmpty) 'requestId': requestId,
        if (requestId != null && requestId.isNotEmpty) 'request_id': requestId,
      },
      headers: requestId == null || requestId.isEmpty
          ? null
          : {
              'Idempotency-Key': requestId,
              'X-Request-Id': requestId,
            },
    );
    return _asMap(data);
  }

  Future<Map<String, dynamic>?> getPendingApplication() async {
    final data = await _client.get('/member/wallet/applications/pending');
    if (data == null) return null;
    if (data is Map) return Map<String, dynamic>.from(data);
    return null;
  }

  Future<Map<String, dynamic>> getApplications({
    String applyType = 'ALL',
    String status = 'ALL',
    String? startDate,
    String? endDate,
    int pageNum = 1,
    int pageSize = 20,
  }) async {
    final data = await _client.get('/member/wallet/applications', query: {
      'applyType': applyType,
      'status': status,
      if (startDate != null) 'startDate': startDate,
      if (endDate != null) 'endDate': endDate,
      'pageNum': pageNum,
      'pageSize': pageSize,
    });
    return _asMap(data);
  }

  Future<Map<String, dynamic>> claimRebate() async {
    final data = await _client.post('/member/rebate/claim');
    return _asMap(data);
  }

  Future<Map<String, dynamic>> getRebatePending() async {
    final data = await _client.get('/member/rebate/pending');
    return _asMap(data);
  }

  Future<void> cancelApplication(String applicationId) async {
    await _client.post('/member/wallet/applications/$applicationId/cancel');
  }
}

Map<String, dynamic> _asMap(dynamic data) {
  if (data is Map<String, dynamic>) return data;
  if (data is Map) return Map<String, dynamic>.from(data);
  return {};
}
