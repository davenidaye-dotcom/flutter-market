import 'package:flutter_test/flutter_test.dart';
import 'package:letou_app/data/models/chat_message_model.dart';
import 'package:letou_app/features/lottery/utils/chat_timeline.dart';
import 'package:letou_app/features/lottery/utils/draw_history_rows.dart';
import 'package:letou_app/features/lottery/services/chat_push_cache.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/chat_test_helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const roomId = 'room-regression';
  const gameId = 'JS_SC';
  final cache = ChatPushCache.instance;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await cache.clearRoom(roomId);
  });

  tearDown(() async {
    await cache.clearRoom(roomId);
  });

  group('ChatPushCache 回归', () {
    test('pushOnce 同 dedupeKey 不重复写入', () {
      final msg = sealWarn(gameId, '4731');
      expect(
        cache.pushOnce(
          roomId: roomId,
          dedupeKey: msg.id,
          gameId: gameId,
          message: msg,
        ),
        isTrue,
      );
      expect(
        cache.pushOnce(
          roomId: roomId,
          dedupeKey: msg.id,
          gameId: gameId,
          message: msg,
        ),
        isFalse,
      );
      expect(cache.bufferedForGame(roomId, gameId).length, 1);
    });

    test('trim 优先保留开奖卡片，封盘可被裁掉', () {
      for (var i = 4700; i < 4720; i++) {
        cache.pushOnce(
          roomId: roomId,
          dedupeKey: 'seal-warn-$gameId-$i',
          gameId: gameId,
          message: sealWarn(gameId, '$i'),
        );
        cache.pushOnce(
          roomId: roomId,
          dedupeKey: 'sealed-$gameId-$i',
          gameId: gameId,
          message: sealedLine(gameId, '$i'),
        );
      }
      for (var i = 4710; i < 4730; i++) {
        cache.pushOnce(
          roomId: roomId,
          dedupeKey: 'draw-$gameId-$i',
          gameId: gameId,
          message: drawCard(gameId, '$i', [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]),
        );
      }

      final buffered = cache.bufferedForGame(roomId, gameId);
      final draws = buffered.where((m) => m.type == ChatMessageType.resultCard);

      expect(draws.length, greaterThan(0));
      expect(draws.length, lessThanOrEqualTo(ChatPushCache.maxDrawsPerGame));
      expect(
        buffered.length,
        lessThanOrEqualTo(ChatPushCache.maxPerGame),
      );
    });

    test('trim 保留用户下注指令（不被封盘挤掉）', () {
      for (var i = 0; i < 15; i++) {
        cache.pushOnce(
          roomId: roomId,
          dedupeKey: 'bet-chat-$gameId-$i',
          gameId: gameId,
          message: userBet(gameId, '$i', '大${100 + i}'),
        );
      }
      for (var i = 4700; i < 4725; i++) {
        cache.pushOnce(
          roomId: roomId,
          dedupeKey: 'sealed-$gameId-$i',
          gameId: gameId,
          message: sealedLine(gameId, '$i'),
        );
      }

      final bets = cache
          .bufferedForGame(roomId, gameId)
          .where((m) => m.id.startsWith('bet-chat-'));

      expect(bets.length, greaterThan(0));
      expect(bets.length, lessThanOrEqualTo(ChatPushCache.maxUserBetsPerGame));
    });

    test('syncDrawsFromApi 写入开奖并可在时间线展示', () {
      final draws = [
        drawCard(gameId, '4730', [8, 10, 6, 7, 3, 1, 4, 5, 2, 9]),
        drawCard(gameId, '4729', [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]),
      ];

      cache.syncDrawsFromApi(roomId: roomId, gameId: gameId, draws: draws);

      final timeline = cache.timelineForGame(roomId, gameId);
      expect(
        timeline.where((m) => m.type == ChatMessageType.resultCard).length,
        2,
      );
    });

    test('syncDrawsFromApi 丢弃开奖窗口之前的本地历史下注', () {
      cache.pushOnce(
        roomId: roomId,
        dedupeKey: 'bet-chat-$gameId-old',
        gameId: gameId,
        message: ChatMessageModel(
          id: 'bet-chat-$gameId-old',
          sender: '我',
          content: '大/10',
          time: '19:00',
          issueNo: '34143975',
        ),
      );
      cache.pushOnce(
        roomId: roomId,
        dedupeKey: 'bet-chat-$gameId-keep',
        gameId: gameId,
        message: ChatMessageModel(
          id: 'bet-chat-$gameId-keep',
          sender: '我',
          content: '小/20',
          time: '20:00',
          issueNo: '34145492',
        ),
      );

      cache.syncDrawsFromApi(
        roomId: roomId,
        gameId: gameId,
        draws: [
          drawCard(gameId, '34145491', [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]),
          drawCard(gameId, '34145492', [9, 10, 5, 6, 3, 8, 4, 7, 1, 2]),
        ],
      );

      final bets = cache
          .bufferedForGame(roomId, gameId)
          .where((m) => m.id.startsWith('bet-chat-'))
          .toList();
      expect(bets.any((m) => m.content == '大/10'), isFalse);
      expect(bets.any((m) => m.content == '小/20'), isTrue);
    });

    test('emitLive 不写 buffer，但时间线能展示实时封盘', () {
      final msg = sealWarn(gameId, '4731');
      expect(
        cache.emitLive(
          roomId: roomId,
          dedupeKey: msg.id,
          gameId: gameId,
          message: msg,
        ),
        isTrue,
      );

      expect(cache.bufferedForGame(roomId, gameId), isEmpty);
      expect(cache.liveForGame(roomId, gameId), isNotEmpty);
      final timeline = cache.timelineForGame(roomId, gameId);
      expect(
        timeline.any((m) => m.content.contains('封盘')),
        isTrue,
        reason: '实时封盘必须进 timeline，否则 sync/进页会丢、只能等开奖 synthetic',
      );
      // 二次 emit 被去重
      expect(
        cache.emitLive(
          roomId: roomId,
          dedupeKey: msg.id,
          gameId: gameId,
          message: msg,
        ),
        isFalse,
      );
    });

    test('trim 裁掉过量封盘后仍保留 seal dedupe key，不会被 PERIOD_TICK 重推', () {
      for (var i = 0; i < 60; i++) {
        cache.pushOnce(
          roomId: roomId,
          dedupeKey: 'sealed-$gameId-$i',
          gameId: gameId,
          message: sealedLine(gameId, '$i'),
        );
      }
      const sealKey = 'sealed-$gameId-0';
      // others 上限 40：最旧封盘会出 buffer，但 dedupe key 必须留下
      expect(
        cache
            .bufferedForGame(roomId, gameId)
            .where((m) => m.id == sealKey),
        isEmpty,
      );
      expect(cache.hasDedupeKey(roomId, sealKey), isTrue);
      expect(
        cache.emitLive(
          roomId: roomId,
          dedupeKey: sealKey,
          gameId: gameId,
          message: sealedLine(gameId, '0'),
        ),
        isFalse,
        reason: 'key 必须留下，否则每秒重推导致聊天闪屏',
      );
    });

    test('historyDrawRowsForGame 从 buffer 开奖卡片生成顶栏历史', () {
      cache.syncDrawsFromApi(
        roomId: roomId,
        gameId: gameId,
        draws: [
          drawCard(gameId, '4730', [8, 10, 6, 7, 3, 1, 4, 5, 2, 9]),
          drawCard(gameId, '4729', [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]),
        ],
      );

      final rows = cache.historyDrawRowsForGame(roomId, gameId);
      expect(rows.length, 2);
      expect(rows.first.issue, '4730');
      expect(rows.first.numbers, [8, 10, 6, 7, 3, 1, 4, 5, 2, 9]);
    });

    test('syncDrawsFromApi API 缺中间一期时不删 WS 已缓存的该期', () {
      for (final issue in ['5279', '5280']) {
        final key = 'draw-$gameId-${issueCompareKey(issue)}';
        cache.pushOnce(
          roomId: roomId,
          dedupeKey: key,
          gameId: gameId,
          message: drawCard(gameId, issue, [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]),
        );
      }
      expect(cache.hasDrawForIssue(roomId, gameId, '5280'), isTrue,
          reason: 'pushOnce 后应有 5280');

      cache.syncDrawsFromApi(
        roomId: roomId,
        gameId: gameId,
        draws: [
          drawCard(gameId, '5279', [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]),
          drawCard(gameId, '5281', [2, 7, 4, 3, 10, 5, 9, 1, 8, 6]),
        ],
      );

      final issues = cache
          .bufferedForGame(roomId, gameId)
          .where((m) => m.type == ChatMessageType.resultCard)
          .map(extractIssue)
          .whereType<String>()
          .toList();
      expect(issues, contains('5280'), reason: 'sync 后 issues=$issues');
      expect(issues, contains('5281'));
      expect(issues, contains('5279'));
      expect(cache.hasDrawGap(roomId, gameId), isFalse);
    });

    test('syncDrawsFromApi API 缺中间一期且 WS 无该期时仍检测到 gap', () {
      cache.pushOnce(
        roomId: roomId,
        dedupeKey: 'draw-$gameId-5279',
        gameId: gameId,
        message: drawCard(gameId, '5279', [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]),
      );
      cache.syncDrawsFromApi(
        roomId: roomId,
        gameId: gameId,
        draws: [
          drawCard(gameId, '5279', [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]),
          drawCard(gameId, '5281', [2, 7, 4, 3, 10, 5, 9, 1, 8, 6]),
        ],
      );
      expect(cache.hasDrawForIssue(roomId, gameId, '5280'), isFalse);
      expect(cache.hasDrawGap(roomId, gameId), isTrue);
    });

    test('连续开 25 期后 buffer 保留最新 15 期开奖且时间线可展示', () {
      for (var issue = 5250; issue <= 5274; issue++) {
        cache.pushOnce(
          roomId: roomId,
          dedupeKey: 'draw-$gameId-$issue',
          gameId: gameId,
          message: drawCard(gameId, '$issue', [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]),
        );
      }

      final buffered = cache.bufferedForGame(roomId, gameId);
      final drawIssues = buffered
          .where((m) => m.type == ChatMessageType.resultCard)
          .map(extractIssue)
          .whereType<String>()
          .toList();

      expect(drawIssues.length, ChatPushCache.maxDrawsPerGame);
      expect(drawIssues.first, '5260');
      expect(drawIssues.last, '5274');

      final timeline = cache.timelineForGame(
        roomId,
        gameId,
        syntheticSeals: true,
      );
      final timelineDraws = timeline
          .where((m) => m.type == ChatMessageType.resultCard)
          .map(extractIssue)
          .whereType<String>()
          .toList();

      expect(timelineDraws.length, ChatPushCache.maxDrawsPerGame);
      expect(timelineDraws.last, '5274');
      expect(
        timeline.length,
        lessThanOrEqualTo(ChatPushCache.maxVisibleChatMessages),
      );
    });

    test('15 期开奖 + 核对不会因 trim 丢光 BET_RANK/WIN_LIST', () {
      for (var issue = 5260; issue <= 5274; issue++) {
        cache.pushOnce(
          roomId: roomId,
          dedupeKey: 'draw-$gameId-$issue',
          gameId: gameId,
          message: drawCard(gameId, '$issue', [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]),
        );
        cache.pushOnce(
          roomId: roomId,
          dedupeKey: 'bet-rank-$gameId-$issue',
          gameId: gameId,
          message: ChatMessageModel(
            id: 'bet-rank-$gameId-$issue',
            sender: '机器人',
            content: '$issue期已封盘\n竞猜列表核对',
            time: '12:00',
            type: ChatMessageType.betListCheck,
            issueNo: '$issue',
          ),
        );
        cache.pushOnce(
          roomId: roomId,
          dedupeKey: 'win-list-$gameId-$issue',
          gameId: gameId,
          message: ChatMessageModel(
            id: 'win-list-$gameId-$issue',
            sender: '机器人',
            content: '$issue期已开奖\n中奖列表核对',
            time: '12:01',
            type: ChatMessageType.winCheck,
            issueNo: '$issue',
          ),
        );
      }
      final buf = cache.bufferedForGame(roomId, gameId);
      expect(
        buf.where((m) => m.type == ChatMessageType.betListCheck).length,
        15,
      );
      expect(
        buf.where((m) => m.type == ChatMessageType.winCheck).length,
        15,
      );
      expect(
        buf.where((m) => m.type == ChatMessageType.resultCard).length,
        15,
      );
    });

    test('大量投注成功不会裁掉竞猜核对和中奖列表', () {
      for (var i = 0; i < 200; i++) {
        cache.pushOnce(
          roomId: roomId,
          dedupeKey: 'receipt-$i',
          gameId: gameId,
          message: ChatMessageModel(
            id: 'receipt-$i',
            sender: '机器人',
            content: '3416442${i % 10}期投注成功!',
            time: '12:00',
            type: ChatMessageType.betReceipt,
            issueNo: '34164430',
          ),
        );
      }
      for (var issue = 5260; issue <= 5274; issue++) {
        cache.pushOnce(
          roomId: roomId,
          dedupeKey: 'draw-$gameId-$issue',
          gameId: gameId,
          message: drawCard(gameId, '$issue', [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]),
        );
        cache.pushOnce(
          roomId: roomId,
          dedupeKey: 'bet-rank-$gameId-$issue',
          gameId: gameId,
          message: ChatMessageModel(
            id: 'bet-rank-$gameId-$issue',
            sender: '机器人',
            content: '$issue期已封盘\n竞猜列表核对',
            time: '12:00',
            type: ChatMessageType.betListCheck,
            issueNo: '$issue',
          ),
        );
        cache.pushOnce(
          roomId: roomId,
          dedupeKey: 'win-list-$gameId-$issue',
          gameId: gameId,
          message: ChatMessageModel(
            id: 'win-list-$gameId-$issue',
            sender: '机器人',
            content: '$issue期已开奖\n中奖列表核对',
            time: '12:01',
            type: ChatMessageType.winCheck,
            issueNo: '$issue',
          ),
        );
      }
      final buf = cache.bufferedForGame(roomId, gameId);
      expect(
        buf.where((m) => m.type == ChatMessageType.betListCheck).length,
        15,
      );
      expect(
        buf.where((m) => m.type == ChatMessageType.winCheck).length,
        15,
      );
      final timeline = buildChatTimeline(buf, gameId: gameId);
      final visible = ChatPushCache.capVisibleTimeline(timeline);
      expect(
        visible.where((m) => m.content.contains('竞猜列表核对')).length,
        15,
      );
      expect(
        visible.where((m) => m.content.contains('中奖列表核对')).length,
        15,
      );
    });

    test('进房窗口丢掉更早的注单，留下窗口内的开奖', () {
      const ranks = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];
      cache.pushOnce(
        roomId: roomId,
        dedupeKey: 'bet-old',
        gameId: gameId,
        message: ChatMessageModel(
          id: 'bet-old',
          sender: '机器人',
          content: '34164045期投注成功!',
          time: '05:14',
          type: ChatMessageType.betReceipt,
          issueNo: '34164045',
        ),
      );
      cache.pushOnce(
        roomId: roomId,
        dedupeKey: 'draw-old',
        gameId: gameId,
        message: drawCard(gameId, '34164420', ranks),
      );
      cache.pushOnce(
        roomId: roomId,
        dedupeKey: 'draw-new',
        gameId: gameId,
        message: drawCard(gameId, '34164434', ranks),
      );
      cache.pushOnce(
        roomId: roomId,
        dedupeKey: 'draw-empty',
        gameId: gameId,
        message: const ChatMessageModel(
          id: 'draw-empty',
          sender: '机器人',
          content: '',
          time: '',
          type: ChatMessageType.resultCard,
        ),
      );

      cache.dropOlderThanIssue(
        roomId: roomId,
        gameId: gameId,
        oldestIssue: '34164421',
      );

      final left = cache.bufferedForGame(roomId, gameId);
      final issues = left.map((m) => m.issueNo).toList();
      expect(issues, isNot(contains('34164045')));
      expect(issues, isNot(contains('34164420')));
      expect(issues, contains('34164434'));
      expect(
        left.where((m) => m.type == ChatMessageType.resultCard && (m.issueNo ?? '').isEmpty),
        isEmpty,
      );
    });

    test('同一条下注后来补上头像编码', () {
      const id = 'bet-chat-JS_SC-9001';
      final first = ChatMessageModel(
        id: id,
        sender: '气氛号',
        content: '大/10',
        time: '12:00',
        issueNo: '34164435',
      );
      expect(
        cache.pushOnce(
          roomId: roomId,
          dedupeKey: id,
          gameId: gameId,
          message: first,
        ),
        isTrue,
      );
      expect(
        cache.pushOnce(
          roomId: roomId,
          dedupeKey: id,
          gameId: gameId,
          message: first.copyWith(avatarUrl: 'av07'),
        ),
        isTrue,
      );
      expect(
        cache.pushOnce(
          roomId: roomId,
          dedupeKey: id,
          gameId: gameId,
          message: first.copyWith(avatarUrl: 'av08'),
        ),
        isFalse,
      );
      final stored = cache.bufferedForGame(roomId, gameId);
      expect(stored, hasLength(1));
      expect(stored.single.avatarUrl, 'av07');
    });
  });
}
