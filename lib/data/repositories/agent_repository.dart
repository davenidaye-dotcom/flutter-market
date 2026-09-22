import '../../core/network/api_client.dart';

/// Agent portal APIs under `/agent/**`
class AgentRepository {
  AgentRepository({ApiClient? client}) : _client = client ?? ApiClient.instance;

  final ApiClient _client;

  Future<Map<String, dynamic>> getLotteryInfo({
    required String scene,
    String? type,
  }) async {
    final data = await _client.get('/agent/lottery/info', query: {
      'scene': scene,
      if (type != null && type.isNotEmpty) 'type': type,
    });
    return _asMap(data);
  }

  Future<Map<String, dynamic>> getAccounts({
    String? keyword,
    int pageNum = 1,
    int pageSize = 20,
  }) async {
    final data = await _client.get('/agent/accounts', query: {
      if (keyword != null && keyword.isNotEmpty) 'keyword': keyword,
      'pageNum': pageNum,
      'pageSize': pageSize,
    });
    return _asMap(data);
  }

  Future<Map<String, dynamic>> createAccount({
    required String username,
    required String password,
    required String confirmPassword,
    required String type,
    String? displayName,
    int? parentAgentId,
  }) async {
    final data = await _client.post('/agent/accounts', data: {
      'type': type,
      'username': username,
      'password': password,
      'confirmPassword': confirmPassword,
      if (displayName != null && displayName.isNotEmpty) 'displayName': displayName,
      if (parentAgentId != null) 'parentAgentId': parentAgentId,
    });
    return _asMap(data);
  }

  Future<Map<String, dynamic>> getReports({
    String? startDate,
    String? endDate,
    String? type,
    String? source,
    int? parentAccountId,
    String status = 'SETTLED',
    String? username,
    String? issueNo,
    int pageNum = 1,
    int pageSize = 20,
  }) async {
    final data = await _client.get('/agent/reports', query: {
      if (startDate != null) 'startDate': startDate,
      if (endDate != null) 'endDate': endDate,
      if (type != null && type.isNotEmpty) 'type': type,
      if (source != null && source.isNotEmpty) 'source': source,
      if (parentAccountId != null) 'parentAccountId': parentAccountId,
      'status': status,
      if (username != null && username.isNotEmpty) 'username': username,
      if (issueNo != null && issueNo.isNotEmpty) 'issueNo': issueNo,
      'pageNum': pageNum,
      'pageSize': pageSize,
    });
    return _asMap(data);
  }

  /// 会员注单明细（玩法行）。点进会员后调这个，不要继续 reports 下钻。
  Future<Map<String, dynamic>> getReportTickets({
    required String startDate,
    required String endDate,
    int? memberAccountId,
    String? type,
    String status = 'SETTLED',
    String? source,
    int? bindingId,
    int pageNum = 1,
    int pageSize = 50,
  }) async {
    final data = await _client.get('/agent/reports/tickets', query: {
      'startDate': startDate,
      'endDate': endDate,
      if (memberAccountId != null) 'memberAccountId': memberAccountId,
      if (type != null && type.isNotEmpty) 'type': type,
      'status': status,
      if (source != null && source.isNotEmpty) 'source': source,
      if (bindingId != null) 'bindingId': bindingId,
      'pageNum': pageNum,
      'pageSize': pageSize,
    });
    return _asMap(data);
  }

  /// 飞单按房主汇总（仅 AGENT_MEMBER）
  Future<Map<String, dynamic>> getFlightOwners({
    required String startDate,
    required String endDate,
  }) async {
    final data = await _client.get('/agent/reports/flight-owners', query: {
      'startDate': startDate,
      'endDate': endDate,
    });
    return _asMap(data);
  }

  Future<Map<String, dynamic>> getShareDetail(int orderId) async {
    final data = await _client.get('/agent/bets/$orderId/share-detail');
    return _asMap(data);
  }

  Future<Map<String, dynamic>> getCreditAccount() async {
    final data = await _client.get('/agent/credits/account');
    return _asMap(data);
  }

  Future<void> transferCredit({
    required int targetAccountId,
    required String direction,
    required num amount,
    String? remark,
  }) async {
    await _client.post('/agent/credits/transfer', data: {
      'targetAccountId': targetAccountId,
      'direction': direction,
      'amount': amount,
      if (remark != null && remark.isNotEmpty) 'remark': remark,
    });
  }

  Future<Map<String, dynamic>> getCreditChanges({
    String? startDate,
    String? endDate,
    String? changeType,
    int pageNum = 1,
    int pageSize = 20,
  }) async {
    final data = await _client.get('/agent/credits/changes', query: {
      if (startDate != null) 'startDate': startDate,
      if (endDate != null) 'endDate': endDate,
      if (changeType != null) 'changeType': changeType,
      'pageNum': pageNum,
      'pageSize': pageSize,
    });
    return _asMap(data);
  }

  /// Web 直属下注（仅 AGENT_MEMBER）；成功返回 agentBusinessId 列表
  Future<List<dynamic>> placeBets({
    required String gameType,
    String? issueNo,
    required List<Map<String, dynamic>> items,
  }) async {
    final data = await _client.post('/agent/bets', data: {
      'gameType': gameType,
      if (issueNo != null && issueNo.isNotEmpty) 'issueNo': issueNo,
      'items': items,
    });
    if (data is List) return List<dynamic>.from(data);
    return const [];
  }

  /// 代理业务注单列表（可按 source）
  Future<Map<String, dynamic>> getBets({
    String? startDate,
    String? endDate,
    String? type,
    String? source,
    String status = 'ALL',
    String? issueNo,
    int pageNum = 1,
    int pageSize = 20,
  }) async {
    final data = await _client.get('/agent/bets', query: {
      if (startDate != null) 'startDate': startDate,
      if (endDate != null) 'endDate': endDate,
      if (type != null && type.isNotEmpty) 'type': type,
      if (source != null && source.isNotEmpty) 'source': source,
      'status': status,
      if (issueNo != null && issueNo.isNotEmpty) 'issueNo': issueNo,
      'pageNum': pageNum,
      'pageSize': pageSize,
    });
    return _asMap(data);
  }
}

Map<String, dynamic> _asMap(dynamic data) {
  if (data is Map<String, dynamic>) return data;
  if (data is Map) return Map<String, dynamic>.from(data);
  return {};
}
