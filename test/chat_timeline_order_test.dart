import 'package:flutter_test/flutter_test.dart';
import 'package:letou_app/data/models/chat_message_model.dart';
import 'package:letou_app/features/lottery/utils/chat_timeline.dart';
import 'package:letou_app/features/lottery/utils/draw_history_rows.dart';
import 'package:letou_app/features/lottery/widgets/history_draw_panel.dart';

ChatMessageModel _m({
  required String id,
  required ChatMessageType type,
  required String content,
  String? issueNo,
  String time = '20:57',
}) {
  return ChatMessageModel(
    id: id,
    sender: '机器人',
    content: content,
    time: time,
    type: type,
    issueNo: issueNo,
  );
}

void main() {
  test('same issue phase order: bet → receipt → seal → rank → draw → win', () {
    const issue = '34163647';
    final shuffled = [
      _m(id: 'w', type: ChatMessageType.winCheck, content: '$issue期已开奖\n中奖列表核对', issueNo: issue, time: '20:58'),
      _m(id: 'd', type: ChatMessageType.resultCard, content: '第$issue期开奖', issueNo: issue, time: '20:58'),
      _m(id: 'r', type: ChatMessageType.betListCheck, content: '$issue期已封盘\n竞猜列表核对', issueNo: issue, time: '20:57'),
      _m(id: 's2', type: ChatMessageType.system, content: '======停止战斗====== =======封盘线=======', issueNo: issue),
      _m(id: 's1', type: ChatMessageType.system, content: '注意：距离封盘时间还有10秒，封盘之后将不能再投注！', issueNo: issue),
      _m(id: 'rc', type: ChatMessageType.betReceipt, content: '$issue期投注成功!', issueNo: issue, time: '20:56'),
      _m(id: 'b', type: ChatMessageType.text, content: '1/100', issueNo: issue, time: '20:56'),
    ];
    final ordered = buildChatTimeline(shuffled, gameId: 'JS_SC');
    expect(ordered.map((e) => e.id).toList(), ['b', 'rc', 's1', 's2', 'r', 'd', 'w']);
  });

  test('bet pairs interleaved: each CHAT followed by its RECEIPT', () {
    const issue = '34163650';
    // 故意打乱：B 的确认卡先于 A 的下注文案
    final shuffled = [
      _m(id: 'bet-receipt-JS_SC-2', type: ChatMessageType.betReceipt,
          content: '@botB\n$issue期投注成功!', issueNo: issue, time: '21:01'),
      _m(id: 'bet-chat-JS_SC-1', type: ChatMessageType.text,
          content: '3/50', issueNo: issue, time: '21:01'),
      _m(id: 'bet-receipt-JS_SC-1', type: ChatMessageType.betReceipt,
          content: '@botA\n$issue期投注成功!', issueNo: issue, time: '21:01'),
      _m(id: 'bet-chat-JS_SC-2', type: ChatMessageType.text,
          content: '5/80', issueNo: issue, time: '21:01'),
    ];
    final ordered = buildChatTimeline(shuffled, gameId: 'JS_SC');
    expect(ordered.map((e) => e.id).toList(), [
      'bet-chat-JS_SC-1',
      'bet-receipt-JS_SC-1',
      'bet-chat-JS_SC-2',
      'bet-receipt-JS_SC-2',
    ]);
  });

  test('short and long issueNo treated as same period', () {
    final ordered = buildChatTimeline([
      _m(id: 'w', type: ChatMessageType.winCheck, content: '中奖', issueNo: '3647'),
      _m(id: 'd', type: ChatMessageType.resultCard, content: '第34163647期开奖', issueNo: '34163647'),
      _m(id: 'r', type: ChatMessageType.betListCheck, content: '竞猜', issueNo: '34163647'),
    ], gameId: 'JS_SC');
    expect(ordered.map((e) => e.id).toList(), ['r', 'd', 'w']);
  });

  test('orphan winCheck without draw is dropped from timeline', () {
    final ordered = buildChatTimeline([
      _m(id: 'w', type: ChatMessageType.winCheck, content: '中奖', issueNo: '34163699'),
      _m(id: 'r', type: ChatMessageType.betListCheck, content: '竞猜', issueNo: '34163698'),
    ], gameId: 'JS_SC');
    expect(ordered.map((e) => e.id).toList(), ['r']);
  });

  test('history merge stops at gap so live head does not sit on stale orphans', () {
    final merged = mergeDrawHistoryRows(
      base: [
        HistoryDrawRow(issue: '34163844', numbers: const [1, 2], summary: '3'),
        HistoryDrawRow(issue: '34163843', numbers: const [3, 4], summary: '7'),
      ],
      liveHead: HistoryDrawRow(
        issue: '34163952',
        numbers: const [5, 6],
        summary: '11',
      ),
      maxRows: 15,
    );
    expect(merged.map((e) => e.issue).toList(), ['34163952']);
  });
}
