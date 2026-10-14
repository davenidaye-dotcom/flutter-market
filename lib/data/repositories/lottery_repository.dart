import '../../core/network/api_client.dart';
import '../../shared/format/display_number.dart';
import '../../shared/format/game_series.dart';
import '../../core/network/session_store.dart';
import '../../core/time/server_clock.dart';
import '../../features/lottery/utils/bet_receipt_format.dart';
import '../../features/lottery/utils/check_card_format.dart';
import '../../features/lottery/utils/draw_result_parse.dart';
import '../../features/lottery/utils/lottery_period_ui.dart';
import '../models/chat_message_model.dart';
import '../models/lottery_game_model.dart';

class BetSubmitResult {
  const BetSubmitResult({
    required this.orderIds,
    this.content = '',
    this.receipt = '',
    this.issueNo = '',
    this.mentionName = '',
    this.gameType = '',
    this.totalAmount,
    this.available,
    this.items,
  });

  final List<String> orderIds;
  final String content;
  final String receipt;
  final String issueNo;
  final String mentionName;
  final String gameType;
  final Object? totalAmount;
  final Object? available;
  final List<dynamic>? items;

  /// HTTP 下注响应 / WS BET_ACK / 按 reqId 查询结果共用：orderIds 或单个 orderId。
  factory BetSubmitResult.fromMap(Map<dynamic, dynamic> resp) {
    final ids = resp['orderIds'];
    final single = '${resp['orderId'] ?? ''}'.trim();
    final items = resp['items'];
    return BetSubmitResult(
      orderIds: ids is List
          ? ids.map((e) => '$e').where((e) => e.isNotEmpty).toList()
          : (single.isNotEmpty ? [single] : const <String>[]),
      content: '${resp['content'] ?? ''}'.trim(),
      receipt: '${resp['receipt'] ?? resp['text'] ?? ''}'.trim(),
      issueNo: '${resp['issueNo'] ?? ''}'.trim(),
      mentionName: '${resp['mentionName'] ?? ''}'.trim(),
      gameType: '${resp['gameType'] ?? ''}'.trim(),
      totalAmount: resp['totalAmount'],
      available: resp['available'],
      items: items is List ? items : null,
    );
  }
}

/// 聊天历史一页（旧→新）。[nextBeforeSeq] 取自响应头 X-Chat-Next-Before-Seq，0 表示没有更多。
class ChatPage {
  const ChatPage({
    required this.messages,
    this.nextBeforeSeq,
    this.hasMore,
  });

  final List<ChatMessageModel> messages;

  /// null = 响应没带头（旧服务端 / 房主接口）
  final int? nextBeforeSeq;
  final bool? hasMore;
}

class LotteryRepository {
  LotteryRepository({ApiClient? client}) : _client = client ?? ApiClient.instance;

  final ApiClient _client;

  /// 房主在倍率页保存的房间赔率。playCode → 展示用数字。
  Future<Map<String, String>> getRoomOdds(String gameType) async {
    final data = await _client.get('/member/rooms/odds', query: {
      'gameType': gameType,
    });
    if (data is! List) return const {};
    final out = <String, String>{};
    for (final raw in data.whereType<Map>()) {
      final code = '${raw['playCode'] ?? ''}'.trim();
      if (code.isEmpty) continue;
      out[code] = displayNumber(raw['odds'], maxDecimals: 4);
    }
    return out;
  }

  Future<List<LotteryGameModel>> getGames(
    String roomId, {
    bool asOwner = false,
  }) async {
    final dynamic data;
    final sentAt = DateTime.now().millisecondsSinceEpoch;
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
    // 往返一半近似单程延迟；服务器时间戳是写响应前取的，偏差一般在百毫秒内
    final rttHalf = (DateTime.now().millisecondsSinceEpoch - sentAt) ~/ 2;
    for (final e in data) {
      if (e is Map) {
        final sn = e['serverNowMs'];
        ServerClock.observe(
          sn is num ? sn.toInt() : int.tryParse('$sn'),
          latencyMs: rttHalf,
        );
        break;
      }
    }
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
      int? epochOf(dynamic v) {
        if (v is num) return v.toInt();
        return int.tryParse('$v');
      }

      final gameType = m['gameType']?.toString() ?? '';
      final model = LotteryGameModel(
        id: gameType,
        name: GameSeries.displayName(
          gameType,
          m['gameName']?.toString() ?? gameType,
        ),
        currentIssue: m['latestIssueNo']?.toString() ?? '',
        previousIssue: m['lastIssueNo']?.toString(),
        countdownSeconds: seconds,
        previousResults: previousResults,
        isDrawing: enabled && seconds <= 0,
        openAtEpochMs: openAtEpochMs,
        sealAtEpochMs: sealAtEpochMs,
        sealSeconds: sealSeconds,
        closeStartEpochMs: epochOf(m['closeStartEpochMs']),
        closeEndEpochMs: epochOf(m['closeEndEpochMs']),
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
      final sentAt = DateTime.now().millisecondsSinceEpoch;
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

      ServerClock.observe(
        toInt(m['serverNowMs']),
        latencyMs: (DateTime.now().millisecondsSinceEpoch - sentAt) ~/ 2,
      );

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

  static const chatPageSize = 50;

  /// 兼容旧调用：只要消息列表。会员接口 [limit] 已被服务端忽略，翻页用 [beforeSeq] / [size]。
  Future<List<ChatMessageModel>> getChatMessages({
    required String roomId,
    required String gameId,
    bool asOwner = false,
    int limit = 15,
    int? beforeSeq,
    int size = chatPageSize,
  }) async {
    final page = await getChatPage(
      roomId: roomId,
      gameId: gameId,
      asOwner: asOwner,
      limit: limit,
      beforeSeq: beforeSeq,
      size: size,
    );
    return page.messages;
  }

  /// 会员：`GET /member/rooms/messages?gameType&size&beforeSeq`（beforeSeq 省略 = 最新一页）。
  Future<ChatPage> getChatPage({
    required String roomId,
    required String gameId,
    bool asOwner = false,
    int limit = 15,
    int? beforeSeq,
    int size = chatPageSize,
  }) async {
    final dynamic data;
    int? nextBeforeSeq;
    bool? hasMore;
    if (asOwner) {
      data = await _client.get(
        '/owner/games/$gameId/messages',
        query: {'limit': limit},
      );
    } else {
      final res = await _client.getWithHeaders(
        '/member/rooms/messages',
        query: {
          'gameType': gameId,
          'size': size,
          if (beforeSeq != null && beforeSeq > 0) 'beforeSeq': beforeSeq,
        },
      );
      data = res.data;
      nextBeforeSeq = int.tryParse(res.headers['x-chat-next-before-seq'] ?? '');
      final flag = res.headers['x-chat-has-more']?.toLowerCase();
      if (flag == 'true' || flag == 'false') hasMore = flag == 'true';
    }
    if (data is! List) return const ChatPage(messages: []);
    final messages = data
        .whereType<Map>()
        .where((e) => _visibleInRoom(e, roomId))
        .map((e) => _parseChatMessage(Map<String, dynamic>.from(e)))
        .toList();
    return ChatPage(
      messages: messages,
      nextBeforeSeq: nextBeforeSeq,
      hasMore: hasMore,
    );
  }

  /// 当前房间全部已启用彩种，各取最新一页（≤50 条 + 开奖卡）后按 gameType 分组。顺序：旧 → 新。
  Future<Map<String, List<ChatMessageModel>>> getAllRoomDrawMessages({
    required String roomId,
    int limit = 15,
  }) async {
    final _ = limit; // 服务端已忽略
    final data = await _client.get('/member/rooms/messages/all');
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

  /// 会员/房主消息接口已按登录房间过滤。路由 roomId 是房间号，
  /// 消息 roomId 是数字主键，不再按字符串相等丢掉下注和核对卡。
  bool _visibleInRoom(Map raw, String roomId) => true;

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
    final hasCheckRows = (isBetRank && m['rankings'] is List) ||
        (isWinList && m['winners'] is List);
    final checkCard =
        hasCheckRows ? parseCheckCard(m, isWin: isWinList) : null;
    final displayContent = checkCard != null
        ? composeCheckCardText(data: checkCard, issue: issueForId)
        : (isReceipt
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
                    : content)));
    final accountIdRaw = '${m['accountId'] ?? ''}'.trim();
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
        'BET_RECEIPT' || 'BET_FAIL' => ChatMessageType.betReceipt,
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
      accountId: accountIdRaw.isEmpty ? null : accountIdRaw,
      seq: int.tryParse('${m['seq']}') ?? 0,
      pair: int.tryParse('${m['pair']}') ?? 0,
      checkCard: checkCard,
    );
  }

  String? _issueFromMessageId(String? id) {
    if (id == null || id.isEmpty) return null;
    final parts = id.split('-');
    if (parts.length < 3) return null;
    return parts.last;
  }

  /// 下注确认预览：解析指令/items，带回赔率与展示名，不落库。
  Future<List<Map<String, dynamic>>> previewBet({
    required String gameId,
    String? command,
    String? issueNo,
    List<Map<String, dynamic>>? items,
  }) async {
    final body = <String, dynamic>{
      'gameType': gameId,
      if (issueNo != null && issueNo.isNotEmpty) 'issueNo': issueNo,
      if (command != null && command.trim().isNotEmpty) 'command': command.trim(),
      if (items != null && items.isNotEmpty) 'items': items,
    };
    final data = await _client.post('/member/bets/preview', data: body);
    if (data is! Map) return const [];
    final lines = data['lines'];
    if (lines is! List) return const [];
    return lines
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList(growable: false);
  }

  /// HTTP `POST /member/bets` 与 WS `BET` 共用的请求体（WS 再包一层 `{action, data}`）。
  static Map<String, dynamic> buildBetBody({
    required String gameId,
    required String command,
    String? issueNo,
    List<Map<String, dynamic>>? items,
    String? requestId,
  }) {
    final body = <String, dynamic>{
      'gameType': gameId,
      if (issueNo != null && issueNo.isNotEmpty) 'issueNo': issueNo,
      if (requestId != null && requestId.isNotEmpty) 'reqId': requestId,
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
    return body;
  }

  Future<BetSubmitResult> submitBet({
    required String roomId,
    required String gameId,
    required String command,
    String? issueNo,
    List<Map<String, dynamic>>? items,
    String? requestId,
  }) async {
    final _ = roomId;
    final body = buildBetBody(
      gameId: gameId,
      command: command,
      issueNo: issueNo,
      items: items,
      requestId: requestId,
    );
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
    if (resp is Map) return BetSubmitResult.fromMap(resp);
    return const BetSubmitResult(orderIds: []);
  }

  /// `GET /member/bets/req/{reqId}`：DONE 返回回执；PENDING 返回 null；
  /// BET_REQ_NOT_FOUND / 404 抛出对应异常（服务端从未收到）。
  Future<BetSubmitResult?> pollBetByReqId(String reqId) async {
    final resp = await _client.get('/member/bets/req/$reqId');
    if (resp is! Map) return null;
    final status = '${resp['status'] ?? ''}'.toUpperCase();
    if (status == 'PENDING') return null;
    final result = BetSubmitResult.fromMap(resp);
    if (status == 'DONE' || result.orderIds.isNotEmpty) return result;
    return null;
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

  Future<({List<Map<String, dynamic>> rows, int total})> getDrawHistory({
    required String gameId,
    bool asOwner = false,
    String? date,
    int pageNum = 1,
    int pageSize = 50,
  }) async {
    final path = asOwner
        ? '/owner/games/$gameId/history'
        : '/member/games/$gameId/history';
    final data = await _client.get(
      path,
      query: {
        if (date != null) 'date': date,
        'pageNum': pageNum < 1 ? 1 : pageNum,
        'pageSize': pageSize,
      },
    );
    if (data is Map) {
      final rows = data['rows'] is List
          ? (data['rows'] as List)
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList()
          : const <Map<String, dynamic>>[];
      final total = int.tryParse('${data['total'] ?? ''}') ?? rows.length;
      return (rows: rows, total: total);
    }
    if (data is List) {
      final rows = data
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      return (rows: rows, total: rows.length);
    }
    return (rows: const <Map<String, dynamic>>[], total: 0);
  }

  Future<List<Map<String, dynamic>>> getLongDragon({
    required String gameId,
    int limit = 50,
    bool asOwner = false,
  }) async {
    final path = asOwner
        ? '/owner/games/$gameId/trends/long-dragon'
        : '/member/games/$gameId/trends/long-dragon';
    final data = await _client.get(
      path,
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
