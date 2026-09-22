import 'package:flutter_test/flutter_test.dart';
import 'package:letou_app/data/models/chat_message_model.dart';
import 'package:letou_app/features/lottery/utils/chat_timeline.dart';

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

  test('short and long issueNo treated as same period', () {
    final ordered = buildChatTimeline([
      _m(id: 'w', type: ChatMessageType.winCheck, content: '中奖', issueNo: '3647'),
      _m(id: 'd', type: ChatMessageType.resultCard, content: '第34163647期开奖', issueNo: '34163647'),
      _m(id: 'r', type: ChatMessageType.betListCheck, content: '竞猜', issueNo: '34163647'),
    ], gameId: 'JS_SC');
    expect(ordered.map((e) => e.id).toList(), ['r', 'd', 'w']);
  });
}
