import '../../core/network/api_client.dart';
import '../../core/network/session_store.dart';
import '../../features/lottery/utils/bet_receipt_format.dart';
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
      final sealAtRaw = m['sealAtEpochMs'];
      final sealAtEpochMs = sealAtRaw is int
          ? sealAtRaw
          : int.tryParse('$sealAtRaw');
      final sealRaw = m['sealSeconds'];
      final sealSeconds = sealRaw is int
          ? sealRaw
          : int.tryParse('$sealRaw');
      final model = LotteryGameModel(
        id: m['gameType']?.toString() ?? '',
        name: m['gameName']?.toString() ?? m['gameType']?.toString() ?? '',
        currentIssue: m['latestIssueNo']?.toString() ?? '',
        previousIssue: m['lastIssueNo']?.toString(),
        countdownSeconds: seconds,
        previousResults: previousResults,
        isDrawing: enabled && seconds <= 0,
        openAtEpochMs: openAtEpochMs,
        sealAtEpochMs: sealAtEpochMs,
        sealSeconds: sealSeconds,
      );
      return model.copyWith(
        status: !enabled
            ? LotteryStatus.closed
            : LotteryPeriodHelper.statusFromCountdown(
                seconds,
                sealSeconds: LotteryPeriodRules.sealSecondsOf(model),
              ),
      );
    }).where((g) => g.id.isNotEmpty && g.status != LotteryStatus.closed).toList();
  }

  /// 与 plus-ui 同源：公开期数含 sealAt / sealSeconds（member games 可能缺）。
  Future<({int? openAt, int? sealAt, int? sealSeconds, int countdown})?>
      getPublicPeriod(String gameType) async {
    if (gameType.isEmpty) return null;
    try {
      final data = await _client.get(
        '/public/lottery/period',
        query: {'gameType': gameType},
      );
      if (data is! Map) return null;
      final m = Map<String, dynamic>.from(data);
      int? toInt(dynamic v) {
        if (v is int) return v;
        if (v is num) return v.toInt();
        return int.tryParse('$v');
      }

      return (
        openAt: toInt(m['openAtEpochMs']),
        sealAt: toInt(m['sealAtEpochMs']),
        sealSeconds: toInt(m['sealSeconds']),
        countdown: toInt(m['countdownSeconds']) ?? 0,
      );
    } catch (_) {
      return null;
    }
  }

  Future<List<ChatMessageModel>> getChatMessages({
    required String roomId,
    required String gameId,
    bool asOwner = false,
    int limit = 15,
  }) async {
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
        .where((e) => _visibleInRoom(e, roomId))
        .map((e) => _parseChatMessage(Map<String, dynamic>.from(e)))
        .toList();
    return messages;
  }

  /// 当前房间全部已启用彩种，各取最近 [limit] 期后按 gameType 分组。顺序与接口一致：旧 → 新。
  Future<Map<String, List<ChatMessageModel>>> getAllRoomDrawMessages({
    required String roomId,
    int limit = 15,
  }) async {
    final data = await _client.get(
      '/member/rooms/messages/all',
      query: {'limit': limit},
    );
    if (data is! List) return const {};
    final grouped = <String, List<ChatMessageModel>>{};
    for (final item in data.whereType<Map>()) {
      if (!_visibleInRoom(item, roomId)) continue;
      final m = Map<String, dynamic>.from(item);
      final gameType = m['gameType']?.toString() ?? '';
      if (gameType.isEmpty) continue;
      grouped.putIfAbsent(gameType, () => []).add(_parseChatMessage(m));
    }
    return grouped;
  }

  /// 封盘/开奖 roomId 为空，本房消息必须等于当前房。
  bool _visibleInRoom(Map raw, String roomId) {
    final id = raw['roomId']?.toString().trim() ?? '';
    if (id.isEmpty || id == 'null') return true;
    return roomId.isEmpty || id == roomId.trim();
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
    final isReceipt = msgType == 'BET_RECEIPT';
    final isUserChat = msgType == 'CHAT';
    final isBetRank = msgType == 'BET_RANK' ||
        msgType == 'BET_LIST_CHECK' ||
        msgType == 'GUESS_LIST_CHECK' ||
        msgType == 'SEAL_BET_LIST';
    final isWinList = msgType == 'WIN_LIST' ||
        msgType == 'WIN_CHECK' ||
        msgType == 'WIN_LIST_CHECK';
    final isDrawOrSeal = msgType == 'DRAW_RESULT' ||
        msgType == 'SEAL_WARN' ||
        msgType == 'SEALED' ||
        msgType == 'SYS';
    final orderId = m['orderId']?.toString() ?? '';
    final gameType = m['gameType']?.toString() ?? '';
    final rawId = m['id']?.toString() ?? '';
    final issueForId = (apiIssue ?? '').trim();
    final serverSender = (m['senderName'] ?? '').toString().trim();
    final id = rawId.isNotEmpty
        ? rawId
        : (isBetRank && gameType.isNotEmpty && issueForId.isNotEmpty
            ? 'bet-rank-$gameType-$issueForId'
            : (isWinList && gameType.isNotEmpty && issueForId.isNotEmpty
                ? 'win-list-$gameType-$issueForId'
                : (orderId.isNotEmpty && gameType.isNotEmpty
                    ? (isReceipt
                        ? 'bet-receipt-$gameType-$orderId'
                        : 'bet-chat-$gameType-$orderId')
                    : '')));
    final displayContent = isReceipt
        ? formatBetReceiptText(
            mention: (m['mentionName'] ?? '').toString(),
            issue: (m['issueNo'] ?? '').toString(),
            total: m['totalAmount'],
            items: m['items'] is List ? m['items'] as List : null,
            fallbackContent: content,
          )
        : (isBetRank
            ? formatBetRankText(
                issue: issueForId,
                content: content,
                rankings: m['rankings'] is List ? m['rankings'] as List : null,
              )
            : (isWinList
                ? formatWinCheckText(
                    issue: issueForId,
                    content: content,
                    winners: parseWinCheckWinners(
                      m['winners'] is List ? m['winners'] as List : null,
                    ),
                  )
                : content));
    return ChatMessageModel(
      id: id,
      sender: isUserChat
          ? (serverSender.isEmpty ? '会员' : serverSender)
          : (serverSender.isNotEmpty
              ? (serverSender == '管理员' ? '机器人' : serverSender)
              : '机器人'),
      content: displayContent,
      time: time,
      type: switch (msgType) {
        'DRAW_RESULT' => ChatMessageType.resultCard,
        'SEAL_WARN' || 'SEALED' || 'SYS' => ChatMessageType.system,
        'BET_RECEIPT' => ChatMessageType.betReceipt,
        'BET_RANK' ||
        'BET_LIST_CHECK' ||
        'GUESS_LIST_CHECK' ||
        'SEAL_BET_LIST' =>
          ChatMessageType.betListCheck,
        'WIN_LIST' || 'WIN_CHECK' || 'WIN_LIST_CHECK' => ChatMessageType.winCheck,
        _ => ChatMessageType.text,
      },
      isAdmin: isDrawOrSeal,
      issueNo: apiIssue?.isNotEmpty == true
          ? apiIssue
          : (parsed.issueNo ?? _issueFromMessageId(id.isNotEmpty ? id : m['id']?.toString())),
      drawRanks: parsed.ranks.isEmpty ? null : parsed.ranks,
      avatarUrl: (m['avatarUrl'] ?? m['avatar'])?.toString(),
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
    }
    // 有 items 也带 command，便于后端广播同房可见的下注文案
    if (command.trim().isNotEmpty) {
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
