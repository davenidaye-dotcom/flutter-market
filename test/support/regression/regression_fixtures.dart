import 'package:letou_app/data/models/chat_message_model.dart';
import 'package:letou_app/data/models/lottery_game_model.dart';
import 'package:letou_app/data/repositories/lottery_repository.dart';
import 'package:letou_app/features/lottery/utils/lottery_period_ui.dart';

/// 固定样本：与 test/fixtures 及后端 Redis 消息格式对齐。
class RegressionFixtures {
  RegressionFixtures._();

  static const roomId = '900010001';
  static const gameId = 'JS_SC';
  static const currentIssue = '4731';
  static const previousIssue = '4730';

  static List<LotteryGameModel> games() => [
        LotteryGameModel(
          id: gameId,
          name: '极速赛车',
          currentIssue: currentIssue,
          previousIssue: previousIssue,
          countdownSeconds: 162,
          status: LotteryPeriodHelper.statusFromCountdown(162),
          previousResults: const [8, 10, 6, 7, 3, 1, 4, 5, 2, 9],
          openAtEpochMs: DateTime.now()
              .add(const Duration(seconds: 162))
              .millisecondsSinceEpoch,
        ),
      ];

  static List<Map<String, dynamic>> rawChatMessages() => [
        {
          'id': 'sealed-$gameId-$previousIssue',
          'msgType': 'SEALED',
          'issueNo': previousIssue,
          'content': '======封盘线======\n======停止战斗======',
          'senderName': '管理员',
          'createdAt': '2026-08-29T21:05:00',
        },
        {
          'id': 'seal-warn-$gameId-$previousIssue',
          'msgType': 'SEAL_WARN',
          'issueNo': previousIssue,
          'content': '注意：距离封盘时间还有9秒，封盘之后将不能再投注！',
          'senderName': '管理员',
          'createdAt': '2026-08-29T21:04:51',
        },
        {
          'id': 'draw-$gameId-$previousIssue',
          'msgType': 'DRAW_RESULT',
          'issueNo': previousIssue,
          'content': '第$previousIssue期开奖: 8,10,6,7,3,1,4,5,2,9',
          'senderName': '管理员',
          'createdAt': '2026-08-29T21:06:00',
        },
        {
          'id': 'bet-chat-$gameId-900001',
          'msgType': 'CHAT',
          'issueNo': currentIssue,
          'content': '大100',
          'senderName': 'player01',
          'createdAt': '2026-08-29T21:04:30',
        },
      ];

  static List<Map<String, dynamic>> rawDrawHistory() => [
        {
          'issueNo': previousIssue,
          'ranks': [8, 10, 6, 7, 3, 1, 4, 5, 2, 9],
        },
        {
          'issueNo': '4729',
          'ranks': [1, 2, 3, 4, 5, 6, 7, 8, 9, 10],
        },
      ];

  static Map<String, dynamic> wsPeriodTick({
    String? issue,
    int countdownSeconds = 162,
  }) =>
      {
        'event': 'PERIOD_TICK',
        'gameType': gameId,
        'data': {
          'issueNo': issue ?? currentIssue,
          'lastIssueNo': previousIssue,
          'lastRanks': [8, 10, 6, 7, 3, 1, 4, 5, 2, 9],
          'countdownSeconds': countdownSeconds,
          'status': 'BETTING',
          'openAtEpochMs': DateTime.now()
              .add(Duration(seconds: countdownSeconds))
              .millisecondsSinceEpoch,
        },
      };

  static Map<String, dynamic> wsSealWarn({String? issue, int remain = 9}) => {
        'event': 'SEAL_WARN',
        'gameType': gameId,
        'data': {
          'issueNo': issue ?? currentIssue,
          'remainSeconds': remain,
          'text': '注意：距离封盘时间还有${remain}秒，封盘之后将不能再投注！',
        },
      };

  static Map<String, dynamic> wsSealed({String? issue}) => {
        'event': 'SEALED',
        'gameType': gameId,
        'data': {
          'issueNo': issue ?? currentIssue,
          'text': '======封盘线======\n======停止战斗======',
        },
      };

  static Map<String, dynamic> wsDrawResult({String? issue}) => {
        'event': 'DRAW_RESULT',
        'gameType': gameId,
        'data': {
          'issueNo': issue ?? previousIssue,
          'ranks': [8, 10, 6, 7, 3, 1, 4, 5, 2, 9],
        },
      };

  static Map<String, dynamic> wsUserBet({
    String orderId = '900002',
    String command = '小50',
  }) =>
      {
        'event': 'CHAT',
        'gameType': gameId,
        'data': {
          'issueNo': currentIssue,
          'orderId': orderId,
          'content': command,
          'senderName': 'player01',
        },
      };
}

class FakeLotteryRepository extends LotteryRepository {
  FakeLotteryRepository({
    this.games = const [],
    this.chatMessages = const [],
    this.drawHistory = const [],
    this.betOrderIds = const ['mock-order-1'],
  }) : super(client: null);

  final List<LotteryGameModel> games;
  final List<ChatMessageModel> chatMessages;
  final List<Map<String, dynamic>> drawHistory;
  final List<String> betOrderIds;

  @override
  Future<List<LotteryGameModel>> getGames(
    String roomId, {
    bool asOwner = false,
  }) async =>
      games;

  @override
  Future<List<ChatMessageModel>> getChatMessages({
    required String roomId,
    required String gameId,
    bool asOwner = false,
    int limit = 20,
  }) async =>
      chatMessages;

  @override
  Future<({List<Map<String, dynamic>> rows, int total})> getDrawHistory({
    required String gameId,
    bool asOwner = false,
    String? date,
    int pageNum = 1,
    int pageSize = 50,
  }) async =>
      (rows: drawHistory, total: drawHistory.length);

  @override
  Future<BetSubmitResult> submitBet({
    required String roomId,
    required String gameId,
    required String command,
    String? issueNo,
    List<Map<String, dynamic>>? items,
    String? requestId,
  }) async =>
      BetSubmitResult(orderIds: betOrderIds);

  @override
  Future<List<Map<String, dynamic>>> getLongDragon({
    required String gameId,
    int limit = 100,
  }) async =>
      const [];
}
