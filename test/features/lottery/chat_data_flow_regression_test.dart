import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:letou_app/data/models/chat_message_model.dart';
import 'package:letou_app/features/lottery/services/chat_push_cache.dart';
import 'package:letou_app/features/lottery/utils/draw_history_rows.dart';
import 'package:letou_app/features/lottery/utils/draw_result_parse.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/chat_test_helpers.dart';

/// 模拟进聊天页的完整数据链路：
/// HTTP messages → pushOnce → syncDrawsFromApi → timelineForGame
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const roomId = 'room-flow';
  const gameId = 'JS_SC';
  final cache = ChatPushCache.instance;

  late String messagesFixture;
  late String historyFixture;

  setUpAll(() {
    messagesFixture =
        File('test/fixtures/member_room_messages.json').readAsStringSync();
    historyFixture =
        File('test/fixtures/member_draw_history.json').readAsStringSync();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await cache.clearRoom(roomId);
  });

  tearDown(() async {
    await cache.clearRoom(roomId);
  });

  group('API 解析回归', () {
    test('member/rooms/messages 响应解析出封盘/开奖/下注', () {
      final raw = loadJsonList(messagesFixture);
      final messages = parseApiChatMessages(raw);

      expect(messages.any((m) => m.type == ChatMessageType.system), isTrue);
      expect(messages.any((m) => m.type == ChatMessageType.resultCard), isTrue);
      expect(messages.any((m) => m.type == ChatMessageType.text), isTrue);

      final draw = messages.firstWhere(
        (m) => m.type == ChatMessageType.resultCard,
      );
      expect(draw.issueNo, '4729');
      expect(draw.drawRanks, [8, 10, 6, 7, 3, 1, 4, 5, 2, 9]);
    });

    test('DRAW_RESULT 文案解析与后端 toChatMessageVo 一致', () {
      const content = '第4730期开奖: 8,10,6,7,3,1,4,5,2,9';
      final parsed = DrawResultParse.parse(content);
      expect(parsed.issueNo, '4730');
      expect(parsed.ranks, [8, 10, 6, 7, 3, 1, 4, 5, 2, 9]);
    });

    test('draw history API 转为 resultCard', () {
      final draws = drawsFromHistoryJson(historyFixture, gameId);
      expect(draws.length, 3);
      expect(draws.first.issueNo, '4730');
      expect(draws.first.drawRanks, isNotEmpty);
    });
  });

  group('进聊天页数据流回归', () {
    test('HTTP 消息 + 开奖历史 → 时间线含开奖卡片', () {
      // 1) 模拟 loadChatMessagesFromServer
      final apiMessages = parseApiChatMessages(loadJsonList(messagesFixture));
      for (final m in apiMessages) {
        final issue = m.issueNo ?? '';
        final key = m.id.isNotEmpty
            ? m.id
            : 'api-${m.type.name}-$issue-${m.content.hashCode}';
        cache.pushOnce(
          roomId: roomId,
          dedupeKey: key,
          gameId: gameId,
          message: m,
        );
      }

      // 2) 模拟 refreshDrawHistoryRows → syncDrawsFromApi
      cache.syncDrawsFromApi(
        roomId: roomId,
        gameId: gameId,
        draws: drawsFromHistoryJson(historyFixture, gameId),
      );

      // 3) 模拟 _syncMessagesFromCache（syntheticSeals=false，后台权威）
      final timeline = cache.freshTimelineForGame(
        roomId,
        gameId,
        syntheticSeals: false,
      );

      expect(
        timeline.any((m) => m.type == ChatMessageType.resultCard),
        isTrue,
        reason: '聊天区必须能看到开奖卡片，不能只有封盘',
      );
      expect(
        timeline.any((m) => m.id.startsWith('bet-chat-')),
        isTrue,
        reason: '用户下注指令应保留',
      );
    });

    test('仅封盘无开奖时 isDrawTimelineFresh 为 false，应触发 HTTP 回补', () {
      cache.pushOnce(
        roomId: roomId,
        dedupeKey: 'sealed-$gameId-4731',
        gameId: gameId,
        message: sealedLine(gameId, '4731'),
      );
      cache.pushOnce(
        roomId: roomId,
        dedupeKey: 'seal-warn-$gameId-4731',
        gameId: gameId,
        message: sealWarn(gameId, '4731'),
      );

      final timeline = cache.timelineForGame(roomId, gameId);
      expect(
        isDrawTimelineFresh(timeline, '4731', previousIssue: '4730'),
        isFalse,
      );
    });

    test('时间线 syntheticSeals 为缺封盘的历史开奖补全', () {
      cache.syncDrawsFromApi(
        roomId: roomId,
        gameId: gameId,
        draws: [
          drawCard(gameId, '4730', [8, 10, 6, 7, 3, 1, 4, 5, 2, 9]),
        ],
      );

      final timeline = cache.freshTimelineForGame(
        roomId,
        gameId,
        syntheticSeals: true,
      );

      expect(timeline.any((m) => m.content.contains('停止战斗')), isTrue);
      expect(timeline.any((m) => m.type == ChatMessageType.resultCard), isTrue);
    });
  });
}
