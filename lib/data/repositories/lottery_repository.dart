import '../../core/network/api_client.dart';
import '../../core/network/session_store.dart';
import '../../features/lottery/utils/draw_result_parse.dart';
import '../../features/lottery/utils/lottery_period_ui.dart';
import '../models/chat_message_model.dart';
import '../models/lottery_game_model.dart';

class LotteryRepository {
  LotteryRepository({ApiClient? client}) : _client = client ?? ApiClient.instance;

  final ApiClient _client;

  Future<List<LotteryGameModel>> getGames(
    String roomId, {
    bool asOwner = false,
  }) async {
    final dynamic data;
    if (asOwner) {
      data = await _client.get('/owner/games');
    } else {
      final numeric = SessionStore.instance.roomId ??
          (int.tryParse(roomId) != null ? roomId : null);
      data = await _client.get(
        '/member/rooms/games',
        query: {
          if (numeric != null && numeric.isNotEmpty) 'roomId': numeric,
        },
      );
    }
    if (data is! List) return const [];
    return data.whereType<Map>().map((e) {
      final m = Map<String, dynamic>.from(e);
      final ranks = m['lastRanks'];
      final List<int> previousResults = ranks is List
          ? ranks.map((x) => int.tryParse('$x') ?? 0).where((x) => x > 0).toList()
          : const <int>[];
      final countdown = m['countdownSeconds'];
      final seconds = countdown is int ? countdown : int.tryParse('$countdown') ?? 0;
      final enabled = m['enabled'] != false;
      final openAtRaw = m['openAtEpochMs'];
      final openAtEpochMs = openAtRaw is int
          ? openAtRaw
          : int.tryParse('$openAtRaw');
      return LotteryGameModel(
        id: m['gameType']?.toString() ?? '',
        name: m['gameName']?.toString() ?? m['gameType']?.toString() ?? '',
        currentIssue: m['latestIssueNo']?.toString() ?? '',
        previousIssue: m['lastIssueNo']?.toString(),
        countdownSeconds: seconds,
        status: !enabled
            ? LotteryStatus.closed
            : LotteryPeriodHelper.statusFromCountdown(seconds),
        previousResults: previousResults,
        isDrawing: enabled && seconds <= 0,
        openAtEpochMs: openAtEpochMs,
      );
    }).where((g) => g.id.isNotEmpty && g.status != LotteryStatus.closed).toList();
  }

  Future<List<ChatMessageModel>> getChatMessages({
    required String roomId,
    required String gameId,
    bool asOwner = false,
    int limit = 20,
  }) async {
    final _ = roomId;
    final dynamic data;
    if (asOwner) {
      data = await _client.get(
        '/owner/games/$gameId/messages',
        query: {'limit': limit},
      );
    } else {
      data = await _client.get(
        '/member/rooms/messages',
        query: {
          'gameType': gameId,
          'limit': limit,
        },
      );
    }
    if (data is! List) return const [];
    final messages = data
        .whereType<Map>()
        .map((e) => _parseChatMessage(Map<String, dynamic>.from(e)))
        .toList();
    return messages.reversed.toList();
  }

  /// 当前房间全部彩种各取最新 [limit] 条开奖（一次 HTTP）。
  Future<Map<String, List<ChatMessageModel>>> getAllRoomDrawMessages({
    required String roomId,
    int limit = 20,
  }) async {
    final _ = roomId;
    final data = await _client.get(
      '/member/rooms/messages/all',
      query: {'limit': limit},
    );
    if (data is! List) return const {};
    final grouped = <String, List<ChatMessageModel>>{};
    for (final item in data.whereType<Map>()) {
      final m = Map<String, dynamic>.from(item);
      final gameType = m['gameType']?.toString() ?? '';
      if (gameType.isEmpty) continue;
      grouped.putIfAbsent(gameType, () => []).add(_parseChatMessage(m));
    }
    for (final key in grouped.keys.toList()) {
      grouped[key] = grouped[key]!.reversed.toList();
    }
    return grouped;
  }

  ChatMessageModel _parseChatMessage(Map<String, dynamic> m) {
    final msgType = m['msgType']?.toString().toUpperCase() ?? 'CHAT';
    final createdAt = m['createdAt']?.toString() ?? '';
    final time = createdAt.length >= 16 ? createdAt.substring(11, 16) : createdAt;
    final content = m['content']?.toString() ?? '';
    final parsed = msgType == 'DRAW_RESULT'
        ? DrawResultParse.parse(content)
        : (issueNo: null, ranks: const <int>[]);
    final apiIssue = m['issueNo']?.toString();
    final isUserChat = msgType == 'CHAT';
    return ChatMessageModel(
      id: m['id']?.toString() ?? '',
      sender: m['senderName']?.toString() ?? (isUserChat ? '会员' : '管理员'),
      content: content,
      time: time,
      type: switch (msgType) {
        'DRAW_RESULT' => ChatMessageType.resultCard,
        'SEAL_WARN' || 'SEALED' || 'SYS' => ChatMessageType.system,
        _ => ChatMessageType.text,
      },
      isAdmin: !isUserChat,
      issueNo: apiIssue?.isNotEmpty == true
          ? apiIssue
          : (parsed.issueNo ?? _issueFromMessageId(m['id']?.toString())),
      drawRanks: parsed.ranks.isEmpty ? null : parsed.ranks,
    );
  }

  String? _issueFromMessageId(String? id) {
    if (id == null || id.isEmpty) return null;
    final parts = id.split('-');
    if (parts.length < 3) return null;
    return parts.last;
  }

  Future<List<String>> submitBet({
    required String roomId,
    required String gameId,
    required String command,
    String? issueNo,
    List<Map<String, dynamic>>? items,
    String? requestId,
  }) async {
    final _ = roomId;
    final body = <String, dynamic>{
      'gameType': gameId,
      if (issueNo != null && issueNo.isNotEmpty) 'issueNo': issueNo,
      if (requestId != null && requestId.isNotEmpty) 'requestId': requestId,
      if (requestId != null && requestId.isNotEmpty) 'request_id': requestId,
    };
    if (items != null && items.isNotEmpty) {
      body['items'] = items;
    } else if (command.trim().isNotEmpty) {
      body['command'] = command.trim();
    }
    final resp = await _client.post(
      '/member/bets',
      data: body,
      headers: requestId == null || requestId.isEmpty
          ? null
          : {
              'Idempotency-Key': requestId,
              'X-Request-Id': requestId,
            },
    );
    if (resp is Map) {
      final ids = resp['orderIds'];
      if (ids is List) {
        return ids.map((e) => '$e').where((e) => e.isNotEmpty).toList();
      }
    }
    return const [];
  }

  Future<int> cancelIssueBets({
    required String gameId,
    required String issueNo,
    String? requestId,
  }) async {
    final data = await _client.post(
      '/member/bets/cancel',
      data: {
        'gameType': gameId,
        'issueNo': issueNo,
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
    if (data is Map) {
      final n = data['cancelled'];
      if (n is int) return n;
      return int.tryParse('$n') ?? 0;
    }
    return 0;
  }

  Future<void> cancelBetOrder({
    required String orderId,
    String? requestId,
  }) async {
    await _client.post(
      '/member/bets/$orderId/cancel',
      data: const {},
      headers: requestId == null || requestId.isEmpty
          ? null
          : {
              'Idempotency-Key': requestId,
              'X-Request-Id': requestId,
            },
    );
  }

  Future<List<Map<String, dynamic>>> getDrawHistory({
    required String gameId,
    bool asOwner = false,
    String? date,
    int pageSize = 50,
  }) async {
    final path = asOwner
        ? '/owner/games/$gameId/history'
        : '/member/games/$gameId/history';
    final data = await _client.get(
      path,
      query: {
        if (date != null) 'date': date,
        'pageNum': 1,
        'pageSize': pageSize,
      },
    );
    if (data is Map && data['rows'] is List) {
      return (data['rows'] as List)
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    if (data is List) {
      return data
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    return const [];
  }

  Future<List<Map<String, dynamic>>> getLongDragon({
    required String gameId,
    int limit = 100,
  }) async {
    final data = await _client.get(
      '/member/games/$gameId/trends/long-dragon',
      query: {'limit': limit},
    );
    if (data is Map && data['items'] is List) {
      return (data['items'] as List)
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    if (data is List) {
      return data
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    return const [];
  }
}
