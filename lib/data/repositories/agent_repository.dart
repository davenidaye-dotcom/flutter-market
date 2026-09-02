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
      if (keyword != null) 'keyword': keyword,
      'pageNum': pageNum,
      'pageSize': pageSize,
    });
    return _asMap(data);
  }

  Future<Map<String, dynamic>> createAccount({
    required String username,
    required String password,
    required String accountType,
    String? displayName,
    num? shareRatio,
  }) async {
    final data = await _client.post('/agent/accounts', data: {
      'username': username,
      'password': password,
      'accountType': accountType,
      if (displayName != null) 'displayName': displayName,
      if (shareRatio != null) 'shareRatio': shareRatio,
    });
    return _asMap(data);
  }

  Future<Map<String, dynamic>> getReports({
    String? startDate,
    String? endDate,
    String? type,
    int pageNum = 1,
    int pageSize = 20,
  }) async {
    final data = await _client.get('/agent/reports', query: {
      if (startDate != null) 'startDate': startDate,
      if (endDate != null) 'endDate': endDate,
      if (type != null) 'type': type,
      'pageNum': pageNum,
      'pageSize': pageSize,
    });
    return _asMap(data);
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
}

Map<String, dynamic> _asMap(dynamic data) {
  if (data is Map<String, dynamic>) return data;
  if (data is Map) return Map<String, dynamic>.from(data);
  return {};
}
