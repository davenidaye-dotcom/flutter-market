import '../../core/network/api_client.dart';

/// Owner portal APIs under `/owner/**`
class OwnerRepository {
  OwnerRepository({ApiClient? client}) : _client = client ?? ApiClient.instance;

  final ApiClient _client;

  // --- notices / games ---
  Future<List<Map<String, dynamic>>> getNotices() async {
    final data = await _client.get('/owner/notices');
    return _asMapList(data);
  }

  Future<List<Map<String, dynamic>>> getGames() async {
    final data = await _client.get('/owner/games');
    return _asMapList(data);
  }

  Future<Map<String, dynamic>> getGameHistory(
    String gameType, {
    String? date,
    int pageNum = 1,
    int pageSize = 20,
  }) async {
    final data = await _client.get('/owner/games/$gameType/history', query: {
      if (date != null) 'date': date,
      'pageNum': pageNum,
      'pageSize': pageSize,
    });
    return _asMap(data);
  }

  Future<List<Map<String, dynamic>>> getGameMessages(
    String gameType, {
    String? beforeId,
    int limit = 50,
  }) async {
    final data = await _client.get('/owner/games/$gameType/messages', query: {
      if (beforeId != null) 'beforeId': beforeId,
      'limit': limit,
    });
    return _asMapList(data);
  }

  // --- room ---
  Future<Map<String, dynamic>> getRoom() async {
    final data = await _client.get('/owner/room');
    return _asMap(data);
  }

  Future<void> updateRoomName(String roomName) async {
    await _client.put('/owner/room/name', data: {'roomName': roomName});
  }

  Future<Map<String, dynamic>> getAnnouncement() async {
    final data = await _client.get('/owner/room/announcement');
    return _asMap(data);
  }

  Future<void> updateAnnouncement(String content) async {
    await _client.put('/owner/room/announcement', data: {'content': content});
  }

  Future<void> updateRoomPassword(String? password) async {
    await _client.put('/owner/room/password', data: {
      'password': password ?? '',
    });
  }

  Future<Map<String, dynamic>> getMembers({
    String? keyword,
    String? status,
    int pageNum = 1,
    int pageSize = 20,
  }) async {
    final data = await _client.get('/owner/room/members', query: {
      if (keyword != null) 'keyword': keyword,
      if (status != null) 'status': status,
      'pageNum': pageNum,
      'pageSize': pageSize,
    });
    return _asMap(data);
  }

  Future<void> updateMemberStatus(String accountId, String status) async {
    await _client.put('/owner/room/members/$accountId/status', data: {
      'status': status,
    });
  }

  Future<void> updateMemberRebate(String accountId, num rebate) async {
    await _client.put('/owner/room/members/$accountId/rebate', data: {
      'rebate': rebate,
    });
  }

  Future<List<Map<String, dynamic>>> getAgents() async {
    final data = await _client.get('/owner/room/agents');
    return _asMapList(data);
  }

  Future<Map<String, dynamic>> getOdds({required String gameType}) async {
    final data = await _client.get('/owner/room/odds', query: {
      'gameType': gameType,
    });
    return _asMap(data);
  }

  Future<void> updateOdds(Map<String, dynamic> body) async {
    await _client.put('/owner/room/odds', data: body);
  }

  Future<Map<String, dynamic>> getRebate() async {
    final data = await _client.get('/owner/room/rebate');
    return _asMap(data);
  }

  Future<void> updateRebate(Map<String, dynamic> body) async {
    await _client.put('/owner/room/rebate', data: body);
  }

  Future<void> advanceRebate(Map<String, dynamic> body) async {
    await _client.post('/owner/room/rebate/advance', data: body);
  }

  Future<Map<String, dynamic>> getOpLogs({
    String? startDate,
    String? endDate,
    int pageNum = 1,
    int pageSize = 20,
  }) async {
    final data = await _client.get('/owner/room/op-logs', query: {
      if (startDate != null) 'startDate': startDate,
      if (endDate != null) 'endDate': endDate,
      'pageNum': pageNum,
      'pageSize': pageSize,
    });
    return _asMap(data);
  }

  Future<Map<String, dynamic>> getGamesSettings() async {
    final data = await _client.get('/owner/room/games/settings');
    return _asMap(data);
  }

  Future<void> updateGamesSettings(Map<String, dynamic> body) async {
    await _client.put('/owner/room/games/settings', data: body);
  }

  // --- manage ---
  Future<Map<String, dynamic>> getDashboard() async {
    final data = await _client.get('/owner/manage/dashboard');
    return _asMap(data);
  }

  Future<Map<String, dynamic>> getApplications(
    String kind, {
    String? day,
    String? startDate,
    String? endDate,
    String? status,
    int pageNum = 1,
    int pageSize = 20,
  }) async {
    final data = await _client.get(
      '/owner/manage/applications/$kind',
      query: {
        if (day != null) 'day': day,
        if (startDate != null) 'startDate': startDate,
        if (endDate != null) 'endDate': endDate,
        if (status != null) 'status': status,
        'pageNum': pageNum,
        'pageSize': pageSize,
      },
    );
    return _asMap(data);
  }

  Future<void> approveApplication(String applicationId, {String? remark}) async {
    await _client.post(
      '/owner/manage/applications/$applicationId/approve',
      data: {if (remark != null) 'remark': remark},
    );
  }

  Future<void> rejectApplication(String applicationId, {String? remark}) async {
    await _client.post(
      '/owner/manage/applications/$applicationId/reject',
      data: {if (remark != null) 'remark': remark},
    );
  }

  Future<Map<String, dynamic>> getBetReports({
    String? startDate,
    String? endDate,
    int pageNum = 1,
    int pageSize = 20,
  }) async {
    final data = await _client.get('/owner/manage/reports/bets', query: {
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
    final data = await _client.get('/owner/manage/welfare', query: {
      'type': type,
      if (startDate != null) 'startDate': startDate,
      if (endDate != null) 'endDate': endDate,
    });
    return _asMap(data);
  }

  Future<void> advanceWelfare(Map<String, dynamic> body) async {
    await _client.post('/owner/manage/welfare/advance', data: body);
  }

  Future<Map<String, dynamic>> getCreditRecords({
    String? startDate,
    String? endDate,
    int pageNum = 1,
    int pageSize = 20,
  }) async {
    final data = await _client.get('/owner/manage/credits/records', query: {
      if (startDate != null) 'startDate': startDate,
      if (endDate != null) 'endDate': endDate,
      'pageNum': pageNum,
      'pageSize': pageSize,
    });
    return _asMap(data);
  }

  Future<Map<String, dynamic>> getManageBets({
    String? startDate,
    String? endDate,
    int pageNum = 1,
    int pageSize = 20,
  }) async {
    final data = await _client.get('/owner/manage/bets', query: {
      if (startDate != null) 'startDate': startDate,
      if (endDate != null) 'endDate': endDate,
      'pageNum': pageNum,
      'pageSize': pageSize,
    });
    return _asMap(data);
  }

  Future<Map<String, dynamic>> createRedpack(Map<String, dynamic> body) async {
    final data = await _client.post('/owner/manage/redpacks', data: body);
    return _asMap(data);
  }

  Future<Map<String, dynamic>> listRedpacks({
    String? status,
    int pageNum = 1,
    int pageSize = 20,
  }) async {
    final data = await _client.get('/owner/manage/redpacks', query: {
      if (status != null) 'status': status,
      'pageNum': pageNum,
      'pageSize': pageSize,
    });
    return _asMap(data);
  }

  // --- feipan ---
  Future<Map<String, dynamic>> getFeipanStatus() async {
    final data = await _client.get('/owner/feipan/status');
    return _asMap(data);
  }

  Future<void> bindFeipan(Map<String, dynamic> body) async {
    await _client.post('/owner/feipan/bind', data: body);
  }

  Future<void> unbindFeipan() async {
    await _client.post('/owner/feipan/unbind');
  }

  Future<Map<String, dynamic>> getFeipanCredit({String? gameType}) async {
    final data = await _client.get('/owner/feipan/credit', query: {
      if (gameType != null) 'gameType': gameType,
    });
    return _asMap(data);
  }

  Future<Map<String, dynamic>> getFeipanReports({
    String? startDate,
    String? endDate,
    String category = 'ALL',
  }) async {
    final data = await _client.get('/owner/feipan/reports', query: {
      if (startDate != null) 'startDate': startDate,
      if (endDate != null) 'endDate': endDate,
      'category': category,
    });
    return _asMap(data);
  }

  Future<Map<String, dynamic>> getFeipanOdds({required String gameType}) async {
    final data = await _client.get('/owner/feipan/odds', query: {
      'gameType': gameType,
    });
    return _asMap(data);
  }

  Future<void> updateFeipanOdds(Map<String, dynamic> body) async {
    await _client.put('/owner/feipan/odds', data: body);
  }

  Future<Map<String, dynamic>> getFeipanPointsChanges({
    String changeType = 'ALL',
    int pageNum = 1,
    int pageSize = 20,
  }) async {
    final data = await _client.get('/owner/feipan/points/changes', query: {
      'changeType': changeType,
      'pageNum': pageNum,
      'pageSize': pageSize,
    });
    return _asMap(data);
  }

  Future<Map<String, dynamic>> getFeipanOpLogs({
    String? startDate,
    String? endDate,
  }) async {
    final data = await _client.get('/owner/feipan/op-logs', query: {
      if (startDate != null) 'startDate': startDate,
      if (endDate != null) 'endDate': endDate,
    });
    return _asMap(data);
  }

  // --- CS sessions ---
  Future<Map<String, dynamic>> getCsSessions({
    String? keyword,
    int pageNum = 1,
    int pageSize = 20,
  }) async {
    final data = await _client.get('/owner/cs/sessions', query: {
      if (keyword != null && keyword.isNotEmpty) 'keyword': keyword,
      'pageNum': pageNum,
      'pageSize': pageSize,
    });
    return _asMap(data);
  }

  Future<List<Map<String, dynamic>>> getCsMessages(
    String accountId, {
    String? beforeId,
    int limit = 20,
  }) async {
    final data = await _client.get(
      '/owner/cs/sessions/$accountId/messages',
      query: {
        if (beforeId != null) 'beforeId': beforeId,
        'limit': limit,
      },
    );
    return _asMapList(data);
  }

  Future<Map<String, dynamic>> sendCsReply(
    String accountId,
    String content,
  ) async {
    final data = await _client.post(
      '/owner/cs/sessions/$accountId/messages',
      data: {'content': content},
    );
    return _asMap(data);
  }

  // --- assistants ---
  Future<List<Map<String, dynamic>>> getAssistants() async {
    final data = await _client.get('/owner/room/assistants');
    return _asMapList(data);
  }

  Future<Map<String, dynamic>> createAssistant({
    required String username,
    required String password,
    String? displayName,
    List<String>? permissions,
  }) async {
    final data = await _client.post('/owner/room/assistants', data: {
      'username': username,
      'password': password,
      if (displayName != null && displayName.isNotEmpty) 'displayName': displayName,
      if (permissions != null) 'permissions': permissions,
    });
    return _asMap(data);
  }

  Future<void> updateAssistant(
    String delegationId, {
    String? displayName,
    String? password,
    String? status,
    List<String>? permissions,
  }) async {
    await _client.put('/owner/room/assistants/$delegationId', data: {
      if (displayName != null) 'displayName': displayName,
      if (password != null && password.isNotEmpty) 'password': password,
      if (status != null) 'status': status,
      if (permissions != null) 'permissions': permissions,
    });
  }

  Future<void> deleteAssistant(String delegationId) async {
    await _client.delete('/owner/room/assistants/$delegationId');
  }

  // --- batch rebate ---
  Future<Map<String, dynamic>> getRebateBatchPreview({
    String presence = 'ALL',
    String? keyword,
  }) async {
    final data = await _client.get('/owner/room/rebate/batch-preview', query: {
      'presence': presence,
      if (keyword != null && keyword.isNotEmpty) 'keyword': keyword,
    });
    return _asMap(data);
  }

  Future<Map<String, dynamic>> batchSetRebate(
    List<Map<String, dynamic>> items,
  ) async {
    final data = await _client.post('/owner/room/rebate/batch', data: {
      'items': items,
    });
    return _asMap(data);
  }

  Future<Map<String, dynamic>> batchAdvanceRebate({
    required List<int> accountIds,
    String? remark,
  }) async {
    final data = await _client.post('/owner/room/rebate/batch-advance', data: {
      'accountIds': accountIds,
      if (remark != null && remark.isNotEmpty) 'remark': remark,
    });
    return _asMap(data);
  }
}

Map<String, dynamic> _asMap(dynamic data) {
  if (data is Map<String, dynamic>) return data;
  if (data is Map) return Map<String, dynamic>.from(data);
  return {};
}

List<Map<String, dynamic>> _asMapList(dynamic data) {
  if (data is! List) return const [];
  return data
      .whereType<Map>()
      .map((e) => Map<String, dynamic>.from(e))
      .toList();
}
