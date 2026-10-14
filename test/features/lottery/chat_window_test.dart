import 'package:flutter_test/flutter_test.dart';
import 'package:letou_app/data/models/chat_message_model.dart';
import 'package:letou_app/data/models/check_card_model.dart';
import 'package:letou_app/features/lottery/services/chat_push_cache.dart';
import 'package:letou_app/features/lottery/utils/draw_history_rows.dart';
import 'package:shared_preferences/shared_preferences.dart';

ChatMessageModel _bet(String gameId, int i, {String issue = '34163650'}) {
  return ChatMessageModel(
    id: 'bet-chat-$gameId-$i',
    sender: 'u$i',
    content: '1/大/10',
    time: '10:00',
    issueNo: issue,
    seq: i,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const roomId = 'room-window';
  const gameId = 'JS_SC';
  final cache = ChatPushCache.instance;

  void pushBet(int i, {String issue = '34163650'}) {
    final m = _bet(gameId, i, issue: issue);
    cache.pushOnce(roomId: roomId, dedupeKey: m.id, gameId: gameId, message: m);
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await cache.clearRoom(roomId);
  });
  tearDown(() async => cache.clearRoom(roomId));

  test('非卡片消息只留最新 500 条，淘汰的 dedupe key 同时移除', () {
    for (var i = 1; i <= 620; i++) {
      pushBet(i);
    }
    final texts = cache
        .bufferedForGame(roomId, gameId)
        .where((m) => m.type == ChatMessageType.text)
        .toList();
    expect(texts.length, ChatPushCache.chatWindowSize);
    expect(texts.first.id, 'bet-chat-$gameId-121');
    expect(cache.hasDedupeKey(roomId, 'bet-chat-$gameId-1'), isFalse);
    expect(cache.hasDedupeKey(roomId, 'bet-chat-$gameId-620'), isTrue);
    expect(cache.windowedCount(roomId, gameId), 500);
  });

  test('开奖卡不占 500 窗口，也不会被投注淘汰', () {
    for (var i = 0; i < 15; i++) {
      final issue = '${34163600 + i}';
      final draw = ChatMessageModel(
        id: drawChatMessageId(gameId, issue),
        sender: '机器人',
        content: '第$issue期开奖',
        time: '10:00',
        type: ChatMessageType.resultCard,
        isAdmin: true,
        issueNo: issue,
        drawRanks: const [1, 2, 3, 4, 5, 6, 7, 8, 9, 10],
      );
      cache.pushOnce(roomId: roomId, dedupeKey: draw.id, gameId: gameId, message: draw);
    }
    for (var i = 1; i <= 700; i++) {
      pushBet(i, issue: '34163615');
    }
    final all = cache.bufferedForGame(roomId, gameId);
    expect(all.where((m) => m.type == ChatMessageType.resultCard).length, 15);
    expect(all.where((m) => m.type == ChatMessageType.text).length, 500);
  });

  test('时间线读取时是精确的 500 条，尾部追加不复制也不丢序', () {
    for (var i = 1; i <= 10; i++) {
      pushBet(i);
    }
    final first = cache.timelineForGame(roomId, gameId);
    expect(first.length, 10);
    final v0 = cache.timelineVersion(roomId, gameId);
    for (var i = 11; i <= 600; i++) {
      pushBet(i);
    }
    final timeline = cache.timelineForGame(roomId, gameId);
    expect(timeline.where((m) => m.type == ChatMessageType.text).length, 500);
    expect(timeline.last.id, 'bet-chat-$gameId-600');
    expect(cache.timelineVersion(roomId, gameId), greaterThan(v0));
    // 外部持有的旧快照不会被缓存原地修改
    expect(first.length, 10);
  });

  test('同 id 重复（房间频道 + 用户频道）只留一条', () {
    pushBet(1);
    pushBet(1);
    expect(cache.bufferedForGame(roomId, gameId).length, 1);
  });

  test('历史翻页只收窗口剩余容量，不挤掉已有新消息', () {
    for (var i = 301; i <= 600; i++) {
      pushBet(i);
    }
    final older = [for (var i = 101; i <= 300; i++) _bet(gameId, i)];
    expect(cache.prependHistory(roomId: roomId, gameId: gameId, older: older), 200);
    expect(cache.windowedCount(roomId, gameId), 500);
    // 再来一页已满：不再收
    final older2 = [for (var i = 1; i <= 100; i++) _bet(gameId, i)];
    expect(cache.prependHistory(roomId: roomId, gameId: gameId, older: older2), 0);
    final texts = cache.bufferedForGame(roomId, gameId);
    expect(texts.length, 500);
    expect(texts.first.id, 'bet-chat-$gameId-101');
    // 新消息继续来时，淘汰的是最旧的历史页而不是新消息
    pushBet(601);
    expect(cache.hasDedupeKey(roomId, 'bet-chat-$gameId-101'), isFalse);
    expect(cache.hasDedupeKey(roomId, 'bet-chat-$gameId-601'), isTrue);
  });

  test('CHECK_SELF：并进已有核对卡，内容重拼', () {
    const issue = '34163650';
    final card = ChatMessageModel(
      id: betRankChatMessageId(gameId, issue),
      sender: '机器人',
      content: 'x',
      time: '10:00',
      type: ChatMessageType.betListCheck,
      issueNo: issue,
      checkCard: const CheckCardData(
        isWin: false,
        rows: [
          CheckRow({'rank': 1, 'nickname': 'a', 'amount': 10}),
          CheckRow({'rank': 2, 'nickname': 'b', 'amount': 5}),
        ],
        total: 2,
      ),
    );
    cache.pushOnce(roomId: roomId, dedupeKey: card.id, gameId: gameId, message: card);
    final updated = cache.applyCheckSelf(
      roomId: roomId,
      gameId: gameId,
      cardIds: [card.id],
      rank: 2,
      row: const {'rank': 2, 'nickname': 'b', 'amount': 5},
    );
    expect(updated, isNotNull);
    expect(updated!.content, contains('[b]下注总金额'));
    expect(
      cache.bufferedForGame(roomId, gameId).single.content,
      contains('[b]下注总金额'),
    );
    expect(
      cache.applyCheckSelf(
        roomId: roomId,
        gameId: gameId,
        cardIds: const ['nope'],
        rank: 1,
      ),
      isNull,
    );
  });
}
