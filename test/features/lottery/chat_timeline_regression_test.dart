import 'package:flutter_test/flutter_test.dart';
import 'package:letou_app/data/models/chat_message_model.dart';
import 'package:letou_app/features/lottery/utils/chat_timeline.dart';

import '../../helpers/chat_test_helpers.dart';

void main() {
  group('buildChatTimeline 回归', () {
    test('同一期封盘预警+封盘线只保留一条（去重）', () {
      const gameId = 'JS_SC';
      const issue = '4731';
      final messages = [
        sealWarn(gameId, issue),
        sealedLine(gameId, issue),
        // 模拟 WS + PERIOD_TICK + 合成 重复写入
        sealWarn(gameId, issue, remain: 9),
        sealedLine(gameId, issue),
      ];

      final timeline = buildChatTimeline(messages, gameId: gameId);

      expect(
        timeline.where((m) => m.type == ChatMessageType.system).length,
        2,
        reason: '每期应只有 1 预警 + 1 封盘线',
      );
    });

    test('syntheticSeals=false 不为历史开奖补封盘文案', () {
      const gameId = 'JS_SC';
      final messages = [
        drawCard(gameId, '4729', [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]),
      ];

      final timeline = buildChatTimeline(
        messages,
        gameId: gameId,
        syntheticSeals: false,
      );

      expect(timeline.length, 1);
      expect(timeline.single.type, ChatMessageType.resultCard);
    });

    test('syntheticSeals=true 为缺封盘的开奖补全封盘', () {
      const gameId = 'JS_SC';
      final messages = [
        drawCard(gameId, '4729', [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]),
      ];

      final timeline = buildChatTimeline(
        messages,
        gameId: gameId,
        syntheticSeals: true,
      );

      expect(timeline.any((m) => m.content.contains('封盘')), isTrue);
      expect(timeline.any((m) => m.content.contains('停止战斗')), isTrue);
      expect(timeline.any((m) => m.type == ChatMessageType.resultCard), isTrue);
    });

    test('已有服务端封盘时 syntheticSeals 不再重复补', () {
      const gameId = 'JS_SC';
      const issue = '4730';
      final messages = [
        sealWarn(gameId, issue),
        sealedLine(gameId, issue),
        drawCard(gameId, issue, [8, 10, 6, 7, 3, 1, 4, 5, 2, 9]),
      ];

      final timeline = buildChatTimeline(
        messages,
        gameId: gameId,
        syntheticSeals: true,
      );

      expect(
        timeline.where((m) => m.type == ChatMessageType.system).length,
        2,
      );
    });

    test('时间线按期号排序：封盘在前、开奖在后', () {
      const gameId = 'JS_SC';
      final messages = [
        drawCard(gameId, '4730', [8, 10, 6, 7, 3, 1, 4, 5, 2, 9]),
        sealWarn(gameId, '4730'),
        sealedLine(gameId, '4730'),
        userBet(gameId, '1', '大100'),
      ];

      final timeline = buildChatTimeline(messages, gameId: gameId);

      final issue4730 = timeline
          .where((m) => extractIssue(m) == '4730')
          .toList(growable: false);
      final warnIdx = issue4730.indexWhere((m) => m.content.contains('封盘时间'));
      final sealIdx =
          issue4730.indexWhere((m) => m.content.contains('停止战斗'));
      final drawIdx =
          issue4730.indexWhere((m) => m.type == ChatMessageType.resultCard);

      expect(warnIdx, lessThan(sealIdx));
      expect(sealIdx, lessThan(drawIdx));
    });

    test('长号与短号同一期只保留一条开奖', () {
      const gameId = 'JS_SC';
      final messages = [
        drawCard(gameId, '34135272', [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]),
        drawCard(gameId, '5272', [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]),
      ];

      final timeline = buildChatTimeline(messages, gameId: gameId);

      expect(
        timeline.where((m) => m.type == ChatMessageType.resultCard).length,
        1,
        reason: '34135272 与 5272 应视为同一期',
      );
    });

    test('真实封盘消息优先于 synthetic（保留时间）', () {
      const gameId = 'JS_SC';
      final draw = drawCard(gameId, '5280', [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]);
      final sealed = sealedLine(gameId, '5280');
      final withTime = ChatMessageModel(
        id: sealed.id,
        sender: sealed.sender,
        content: sealed.content,
        time: '21:05',
        type: sealed.type,
        isAdmin: sealed.isAdmin,
        issueNo: sealed.issueNo,
      );

      final timeline = buildChatTimeline(
        [withTime, draw],
        gameId: gameId,
        syntheticSeals: true,
      );

      final sealedMsg = timeline.firstWhere(
        (m) => m.content.contains('停止战斗'),
      );
      expect(sealedMsg.time, '21:05');
    });
  });
}
