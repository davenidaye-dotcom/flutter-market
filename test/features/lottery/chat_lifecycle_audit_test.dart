import 'package:flutter_test/flutter_test.dart';
import 'package:letou_app/data/models/chat_message_model.dart';
import 'package:letou_app/features/lottery/services/chat_push_cache.dart';
import 'package:letou_app/features/lottery/utils/chat_timeline.dart';
import 'package:letou_app/features/lottery/utils/draw_history_rows.dart';
import 'package:letou_app/features/lottery/widgets/history_draw_panel.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/chat_test_helpers.dart';

/// 场景审计：buffer 裁剪 / 去重 / HTTP 回补 / 多彩种隔离 / 漏期
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const roomId = 'audit-room';
  const gameA = 'AZXY10';
  const gameB = 'JS_SC';
  final cache = ChatPushCache.instance;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await cache.clearRoom(roomId);
  });

  tearDown(() async {
    await cache.clearRoom(roomId);
  });

  group('漏期 5280 场景', () {
    test('WS 有 5280 + API 只有 5279/5281 → 5280 不被 sync 删掉', () {
      for (final issue in ['5279', '5280']) {
        cache.pushOnce(
          roomId: roomId,
          dedupeKey: 'draw-$gameB-${issueCompareKey(issue)}',
          gameId: gameB,
          message: drawCard(gameB, issue, [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]),
        );
      }
      cache.syncDrawsFromApi(
        roomId: roomId,
        gameId: gameB,
        draws: [
          drawCard(gameB, '5279', [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]),
          drawCard(gameB, '5281', [2, 7, 4, 3, 10, 5, 9, 1, 8, 6]),
        ],
      );
      final timeline = cache.timelineForGame(
        roomId,
        gameB,
        syntheticSeals: true,
      );
      final drawIssues = timeline
          .where((m) => m.type == ChatMessageType.resultCard)
          .map(extractIssue)
          .whereType<String>()
          .map(issueCompareKey)
          .toList();
      expect(drawIssues, contains(5280));
      expect(drawIssues, contains(5281));
    });

    test('API 回补后 timeline 含 synthetic 封盘且按期排序', () {
      cache.syncDrawsFromApi(
        roomId: roomId,
        gameId: gameB,
        draws: drawRowsToResultMessages([
          HistoryDrawRow(
            issue: '5279',
            numbers: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10],
            summary: '3',
          ),
          HistoryDrawRow(
            issue: '5280',
            numbers: [2, 7, 4, 3, 10, 5, 9, 1, 8, 6],
            summary: '9',
          ),
          HistoryDrawRow(
            issue: '5281',
            numbers: [3, 1, 2, 4, 5, 6, 7, 8, 9, 10],
            summary: '4',
          ),
        ], gameId: gameB),
      );
      final timeline = cache.timelineForGame(
        roomId,
        gameB,
        syntheticSeals: true,
      );
      final draws = timeline
          .where((m) => m.type == ChatMessageType.resultCard)
          .map((m) => issueCompareKey(extractIssue(m) ?? ''))
          .toList();
      expect(draws, [5279, 5280, 5281]);
      expect(
        timeline.any((m) => m.content.contains('停止战斗')),
        isTrue,
      );
    });
  });

  group('多彩种隔离', () {
    test('AZXY10 与 JS_SC 开奖 buffer 互不影响', () {
      cache.pushOnce(
        roomId: roomId,
        dedupeKey: 'draw-$gameA-4453',
        gameId: gameA,
        message: drawCard(gameA, '4453', [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]),
      );
      cache.pushOnce(
        roomId: roomId,
        dedupeKey: 'draw-$gameB-5281',
        gameId: gameB,
        message: drawCard(gameB, '5281', [2, 7, 4, 3, 10, 5, 9, 1, 8, 6]),
      );
      expect(cache.hasDrawForIssue(roomId, gameA, '4453'), isTrue);
      expect(cache.hasDrawForIssue(roomId, gameA, '5281'), isFalse);
      expect(cache.hasDrawForIssue(roomId, gameB, '5281'), isTrue);
      expect(cache.hasDrawForIssue(roomId, gameB, '4453'), isFalse);
    });
  });

  group('buffer 裁剪', () {
    test('25 期开奖全部留在 buffer', () {
      for (var i = 5250; i <= 5274; i++) {
        cache.pushOnce(
          roomId: roomId,
          dedupeKey: 'draw-$gameB-$i',
          gameId: gameB,
          message: drawCard(gameB, '$i', [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]),
        );
      }
      final issues = cache
          .bufferedForGame(roomId, gameB)
          .where((m) => m.type == ChatMessageType.resultCard)
          .map(extractIssue)
          .whereType<String>()
          .toList();
      expect(issues.length, 25);
      expect(issues.first, '5250');
      expect(issues.last, '5274');
    });
  });

  group('时间线稳定性', () {
    String sig(List<ChatMessageModel> list) {
      return list
          .map((m) {
            final issue = extractIssue(m);
            return '${m.type.index}:${issueCompareKey(issue ?? '')}';
          })
          .join('|');
    }

    test('相同 buffer 重建 timeline 指纹不变', () {
      cache.syncDrawsFromApi(
        roomId: roomId,
        gameId: gameB,
        draws: [
          drawCard(gameB, '5280', [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]),
        ],
      );
      final a = cache.timelineForGame(roomId, gameB, syntheticSeals: true);
      final b = cache.timelineForGame(roomId, gameB, syntheticSeals: true);
      expect(sig(a), sig(b));
    });

    test('长号短号同一期 timeline 不重复开奖卡', () {
      cache.pushOnce(
        roomId: roomId,
        dedupeKey: 'draw-$gameB-5280',
        gameId: gameB,
        message: drawCard(gameB, '34135280', [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]),
      );
      cache.pushOnce(
        roomId: roomId,
        dedupeKey: 'draw-$gameB-5280-dup',
        gameId: gameB,
        message: drawCard(gameB, '5280', [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]),
      );
      final timeline = cache.timelineForGame(roomId, gameB, syntheticSeals: true);
      expect(
        timeline.where((m) => m.type == ChatMessageType.resultCard).length,
        1,
      );
    });

    test('长号 id 与短号 id 同逻辑期只保留一条且展示长号', () {
      cache.pushOnce(
        roomId: roomId,
        dedupeKey: 'draw-$gameB-34135299',
        gameId: gameB,
        message: drawCard(gameB, '34135299', [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]),
      );
      cache.pushOnce(
        roomId: roomId,
        dedupeKey: 'draw-$gameB-5299',
        gameId: gameB,
        message: drawCard(gameB, '5299', [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]),
      );
      final draws = cache
          .bufferedForGame(roomId, gameB)
          .where((m) => m.type == ChatMessageType.resultCard)
          .toList();
      expect(draws.length, 1);
      expect(draws.single.issueNo, '34135299');
      expect(draws.single.content, contains('第34135299期'));
      expect(draws.single.id, 'draw-$gameB-5299');
      expect(stableChatItemKey(draws.single), 'draw-5299');
    });
  });

  group('historyDrawRowsForGame', () {
    test('长号短号同一期只保留一条且排序正确', () {
      cache.pushOnce(
        roomId: roomId,
        dedupeKey: 'draw-$gameB-5279',
        gameId: gameB,
        message: drawCard(gameB, '34135279', [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]),
      );
      cache.pushOnce(
        roomId: roomId,
        dedupeKey: 'draw-$gameB-5281',
        gameId: gameB,
        message: drawCard(gameB, '5281', [2, 7, 4, 3, 10, 5, 9, 1, 8, 6]),
      );
      cache.pushOnce(
        roomId: roomId,
        dedupeKey: 'draw-$gameB-5280',
        gameId: gameB,
        message: drawCard(gameB, '34135280', [3, 1, 2, 4, 5, 6, 7, 8, 9, 10]),
      );

      final rows = cache.historyDrawRowsForGame(roomId, gameB);
      expect(rows.length, 3);
      expect(rows.map((r) => r.issue).toList(), ['5281', '34135280', '34135279']);
    });
  });
}
