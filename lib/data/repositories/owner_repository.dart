import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';

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

  /// 房间运行时开关（Redis）；读在 GET /owner/room 的 betConfirm
  Future<void> updateRoomFlags({bool? betConfirm}) async {
    await _client.put('/owner/room/flags', data: {
      if (betConfirm != null) 'betConfirm': betConfirm,
    });
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
    /// ALL / ONLINE / ROBOT / FAKE / AGENT（后端补齐后生效）
    String? memberType,
    String? presence,
    int pageNum = 1,
    int pageSize = 20,
  }) async {
    final data = await _client.get('/owner/room/members', query: {
      if (keyword != null && keyword.isNotEmpty) 'keyword': keyword,
      if (status != null) 'status': status,
      if (memberType != null && memberType.isNotEmpty) 'memberType': memberType,
      if (presence != null) 'presence': presence,
      'pageNum': pageNum,
      'pageSize': pageSize,
    });
    return _asMap(data);
  }

  Future<Map<String, dynamic>> getMemberDetail(String accountId) async {
    final data = await _client.get('/owner/room/members/$accountId');
    return _asMap(data);
  }

  Future<void> updateMemberStatus(String accountId, String status) async {
    await _client.put('/owner/room/members/$accountId/status', data: {
      'status': status,
    });
  }

  Future<void> updateMemberRebate(String accountId, num rebate) async {
    final id = accountId.trim();
    if (id.isEmpty) {
      throw const ApiException(message: '会员账号无效');
    }
    // 固定用小数，避免 int/double 混用导致签名体与验签不一致
    final ratio = rebate.toDouble();
    await _client.put('/owner/room/members/$id/rebate', data: {
      'rebateRatio': ratio,
    });
  }

  Future<void> updateMemberRemark(String accountId, String remark) async {
    await _client.put('/owner/room/members/$accountId/remark', data: {
      'remark': remark,
    });
  }

  Future<void> memberCredit({
    required String accountId,
    required String direction,
    required num amount,
    String? remark,
  }) async {
    await _client.post('/owner/room/members/$accountId/credits', data: {
      'direction': direction,
      'amount': amount,
      if (remark != null && remark.isNotEmpty) 'remark': remark,
    });
  }

  Future<void> setMemberAgent({
    required String accountId,
    required num commissionRatio,
  }) async {
    await _client.post('/owner/room/members/$accountId/agent', data: {
      'commissionRatio': commissionRatio,
    });
  }

  Future<void> cancelMemberAgent(String accountId) async {
    await _client.delete('/owner/room/members/$accountId/agent');
  }

  Future<void> markMemberFake(String accountId, {bool fake = true}) async {
    await _client.put('/owner/room/members/$accountId/fake', data: {
      'fake': fake,
    });
  }

  Future<void> deleteMember(String accountId) async {
    await _client.delete('/owner/room/members/$accountId');
  }

  Future<void> createRobot(Map<String, dynamic> body) async {
    await _client.post('/owner/room/members/robots', data: body);
  }

  // --- 气氛号 / 机器人（playMode=ATMOSPHERE）---

  Future<Map<String, dynamic>> getAtmosphereList({
    String? keyword,
    int pageNum = 1,
    int pageSize = 20,
  }) async {
    final data = await _client.get('/owner/room/atmosphere', query: {
      if (keyword != null && keyword.isNotEmpty) 'keyword': keyword,
      'pageNum': pageNum,
      'pageSize': pageSize,
    });
    return _asMap(data);
  }

  Future<Map<String, dynamic>> getAtmosphere(String accountId) async {
    final data = await _client.get('/owner/room/atmosphere/$accountId');
    return _asMap(data);
  }

  Future<void> updateAtmosphere(
    String accountId,
    Map<String, dynamic> body,
  ) async {
    await _client.put('/owner/room/atmosphere/$accountId', data: body);
  }

  Future<Map<String, dynamic>> createAtmosphere(
    Map<String, dynamic> body,
  ) async {
    final data = await _client.post('/owner/room/atmosphere', data: body);
    if (data is Map) return Map<String, dynamic>.from(data);
    return {};
  }

  Future<List<Map<String, dynamic>>> getAgents({
    String? keyword,
    int pageNum = 1,
    int pageSize = 20,
  }) async {
    final data = await _client.get('/owner/room/agents', query: {
      if (keyword != null && keyword.isNotEmpty) 'keyword': keyword,
      'pageNum': pageNum,
      'pageSize': pageSize,
    });
    return _asMapList(data is Map ? (data['rows'] ?? data) : data);
  }

  Future<List<Map<String, dynamic>>> getAgentDownlines(
    String accountId, {
    String? keyword,
    int pageNum = 1,
    int pageSize = 20,
  }) async {
    final data = await _client.get(
      '/owner/room/agents/$accountId/downlines',
      query: {
        if (keyword != null && keyword.isNotEmpty) 'keyword': keyword,
        'pageNum': pageNum,
        'pageSize': pageSize,
      },
    );
    return _asMapList(data is Map ? (data['rows'] ?? data) : data);
  }

  Future<void> addAgentDownline({
    required String agentAccountId,
    required String memberAccountId,
  }) async {
    await _client.post('/owner/room/agents/$agentAccountId/downlines', data: {
      'memberAccountId': memberAccountId,
    });
  }

  Future<void> removeAgentDownline({
    required String agentAccountId,
    required String memberAccountId,
  }) async {
    await _client.delete(
      '/owner/room/agents/$agentAccountId/downlines/$memberAccountId',
    );
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
    String? keyword,
    String? action,
    int pageNum = 1,
    int pageSize = 20,
  }) async {
    final data = await _client.get('/owner/room/op-logs', query: {
      if (startDate != null) 'startDate': startDate,
      if (endDate != null) 'endDate': endDate,
      if (keyword != null && keyword.isNotEmpty) 'keyword': keyword,
      if (action != null && action.isNotEmpty) 'action': action,
      'pageNum': pageNum,
      'pageSize': pageSize,
    });
    return _asMap(data);
  }

  Future<List<Map<String, dynamic>>> getGamesSettings() async {
    final data = await _client.get('/owner/room/games/settings');
    if (data is List) return _asMapList(data);
    if (data is Map) {
      for (final key in ['rows', 'list', 'records', 'items', 'games']) {
        final v = data[key];
        if (v is List) return _asMapList(v);
      }
    }
    return const [];
  }

  Future<void> updateGamesSettings(Map<String, dynamic> body) async {
    // 后端主字段 items；同时带 games 兼容旧调用
    final games = body['items'] ?? body['games'];
    await _client.put('/owner/room/games/settings', data: {
      ...body,
      if (games != null) 'items': games,
      if (games != null) 'games': games,
    });
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

  /// 图1 玩家报表 — GET /owner/manage/reports/bets
  /// 「全部」不传 startDate/endDate。
  Future<Map<String, dynamic>> getRoomPlayerReport({
    String? startDate,
    String? endDate,
    String? category,
    int pageNum = 1,
    int pageSize = 20,
  }) async {
    final data = await _client.get('/owner/manage/reports/bets', query: {
      if (startDate != null && startDate.isNotEmpty) 'startDate': startDate,
      if (endDate != null && endDate.isNotEmpty) 'endDate': endDate,
      if (category != null && category.isNotEmpty && category != 'ALL')
        'category': category,
      'pageNum': pageNum,
      'pageSize': pageSize,
    });
    return _asMap(data);
  }

  /// 图2 期数报表 — GET /owner/manage/reports/bets/issues
  Future<Map<String, dynamic>> getPlayerPeriodReport({
    required String accountId,
    String? startDate,
    String? endDate,
    String? category,
    int pageNum = 1,
    int pageSize = 20,
  }) async {
    final data = await _client.get('/owner/manage/reports/bets/issues', query: {
      'accountId': accountId,
      if (startDate != null && startDate.isNotEmpty) 'startDate': startDate,
      if (endDate != null && endDate.isNotEmpty) 'endDate': endDate,
      if (category != null && category.isNotEmpty && category != 'ALL')
        'category': category,
      'pageNum': pageNum,
      'pageSize': pageSize,
    });
    return _asMap(data);
  }

  /// 图3 玩法明细 — GET /owner/manage/reports/bets/items
  Future<Map<String, dynamic>> getPlayerIssueBetDetail({
    required String accountId,
    required String issueNo,
    required String gameType,
    int pageNum = 1,
    int pageSize = 20,
  }) async {
    final data = await _client.get('/owner/manage/reports/bets/items', query: {
      'accountId': accountId,
      'gameType': gameType,
      'issueNo': issueNo,
      'pageNum': pageNum,
      'pageSize': pageSize,
    });
    final map = _asMap(data);
    // 头顶字段可能在 data 根上，统一塞进 summary 方便页面读
    final summary = <String, dynamic>{};
    final rawSummary = map['summary'];
    if (rawSummary is Map) summary.addAll(Map<String, dynamic>.from(rawSummary));
    for (final k in ['itemCount', 'betAmount', 'playerResult', 'nickname', 'accountId']) {
      if (map[k] != null) summary.putIfAbsent(k, () => map[k]);
    }
    return {
      ...map,
      'summary': summary,
      'total': map['total'] ?? summary['itemCount'],
      'rows': map['rows'] ?? const [],
    };
  }

  @Deprecated('Use getRoomPlayerReport')
  Future<Map<String, dynamic>> getRoomReport({
    required String startDate,
    required String endDate,
    String? category,
  }) async {
    return getRoomPlayerReport(
      startDate: startDate,
      endDate: endDate,
      category: category,
    );
  }

  Future<Map<String, dynamic>> getWelfare({
    required String type,
    String? startDate,
    String? endDate,
    String? accountId,
  }) async {
    final data = await _client.get('/owner/manage/welfare', query: {
      'type': type,
      if (startDate != null) 'startDate': startDate,
      if (endDate != null) 'endDate': endDate,
      if (accountId != null && accountId.isNotEmpty) 'accountId': accountId,
    });
    return _asMap(data);
  }

  Future<void> advanceWelfare(Map<String, dynamic> body) async {
    await _client.post('/owner/manage/welfare/advance', data: body);
  }

  Future<Map<String, dynamic>> getCreditRecords({
    String? startDate,
    String? endDate,
    String? accountId,
    String? direction,
    int pageNum = 1,
    int pageSize = 20,
  }) async {
    final data = await _client.get('/owner/manage/credits/records', query: {
      if (startDate != null) 'startDate': startDate,
      if (endDate != null) 'endDate': endDate,
      if (accountId != null && accountId.isNotEmpty) 'accountId': accountId,
      if (direction != null && direction.isNotEmpty) 'direction': direction,
      'pageNum': pageNum,
      'pageSize': pageSize,
    });
    return _asMap(data);
  }

  Future<Map<String, dynamic>> getManageBets({
    String? startDate,
    String? endDate,
    String? accountId,
    int pageNum = 1,
    int pageSize = 20,
  }) async {
    final data = await _client.get('/owner/manage/bets', query: {
      if (startDate != null) 'startDate': startDate,
      if (endDate != null) 'endDate': endDate,
      if (accountId != null && accountId.isNotEmpty) 'accountId': accountId,
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
    String? accountId,
    int pageNum = 1,
    int pageSize = 20,
  }) async {
    final data = await _client.get('/owner/manage/redpacks', query: {
      if (status != null) 'status': status,
      if (accountId != null && accountId.isNotEmpty) 'accountId': accountId,
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

  /// 飞单总开关 / 彩种开关 / 飞单比例 / 起飞金额。
  Future<void> updateFeipanFlightSwitch({
    bool? flightEnabled,
    String? gameType,
    bool? gameEnabled,
    num? flightRatio,
    num? minAmount,
  }) async {
    await _client.put('/owner/feipan/flight-switch', data: {
      if (flightEnabled != null) 'flightEnabled': flightEnabled,
      if (gameType != null && gameType.isNotEmpty) 'gameType': gameType,
      if (gameEnabled != null) 'gameEnabled': gameEnabled,
      if (flightRatio != null) 'flightRatio': flightRatio,
      if (minAmount != null) 'minAmount': minAmount,
    });
  }

  /// 所绑代理会员额度账户（totalCredit / occupied / available）
  Future<Map<String, dynamic>> getFeipanCredit() async {
    final data = await _client.get('/owner/feipan/credit');
    return _asMap(data);
  }

  Future<Map<String, dynamic>> getFeipanReports({
    String? startDate,
    String? endDate,
    String category = 'ALL',
    int? bindingId,
  }) async {
    final data = await _client.get('/owner/feipan/reports', query: {
      if (startDate != null) 'startDate': startDate,
      if (endDate != null) 'endDate': endDate,
      'category': category,
      if (bindingId != null) 'bindingId': bindingId,
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

  /// 没有会话就建空会话。玩家信息「发起私聊」先调这个。
  Future<Map<String, dynamic>> ensureCsSession(String accountId) async {
    final data = await _client.get('/owner/cs/sessions/$accountId');
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

  /// 未回水按单明细 — GET /owner/room/rebate/lines
  Future<Map<String, dynamic>> getRebateLines({
    String? accountId,
    String? startDate,
    String? endDate,
    bool unpaidOnly = true,
  }) async {
    final data = await _client.get('/owner/room/rebate/lines', query: {
      if (accountId != null && accountId.isNotEmpty) 'accountId': accountId,
      if (startDate != null) 'startDate': startDate,
      if (endDate != null) 'endDate': endDate,
      'unpaidOnly': unpaidOnly,
    });
    return _asMap(data);
  }

  /// 彩票回水记录 — GET /owner/room/rebate/records（kind=REBATE）
  Future<Map<String, dynamic>> getRebateRecords({
    String? startDate,
    String? endDate,
    String? accountId,
    int pageNum = 1,
    int pageSize = 50,
  }) async {
    final data = await _client.get('/owner/room/rebate/records', query: {
      if (startDate != null) 'startDate': startDate,
      if (endDate != null) 'endDate': endDate,
      if (accountId != null && accountId.isNotEmpty) 'accountId': accountId,
      'pageNum': pageNum,
      'pageSize': pageSize,
    });
    return _asMap(data);
  }

  /// 彩票回水报表 — GET /owner/room/rebate/report
  Future<Map<String, dynamic>> getRebateReport({
    String? startDate,
    String? endDate,
  }) async {
    final data = await _client.get('/owner/room/rebate/report', query: {
      if (startDate != null) 'startDate': startDate,
      if (endDate != null) 'endDate': endDate,
    });
    return _asMap(data);
  }

  /// 代理未返佣查询 — GET /owner/room/commission/batch-preview
  Future<Map<String, dynamic>> getCommissionBatchPreview({
    String presence = 'ALL',
    String? keyword,
  }) async {
    final data = await _client.get('/owner/room/commission/batch-preview', query: {
      'presence': presence,
      if (keyword != null && keyword.isNotEmpty) 'keyword': keyword,
    });
    return _asMap(data);
  }

  /// 单笔返佣 / 一键返佣 — POST /owner/room/commission/batch-advance
  /// 传 1 个 accountId 即单笔返佣，传当前列表全部 id 即一键返佣。
  Future<Map<String, dynamic>> batchAdvanceCommission({
    required List<int> accountIds,
    String? remark,
  }) async {
    final data = await _client.post('/owner/room/commission/batch-advance', data: {
      'accountIds': accountIds,
      if (remark != null && remark.isNotEmpty) 'remark': remark,
    });
    return _asMap(data);
  }

  /// 代理未返佣按单明细 — GET /owner/room/commission/lines
  Future<Map<String, dynamic>> getCommissionLines({
    String? accountId,
    String? startDate,
    String? endDate,
    bool unpaidOnly = true,
  }) async {
    final data = await _client.get('/owner/room/commission/lines', query: {
      if (accountId != null && accountId.isNotEmpty) 'accountId': accountId,
      if (startDate != null) 'startDate': startDate,
      if (endDate != null) 'endDate': endDate,
      'unpaidOnly': unpaidOnly,
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
