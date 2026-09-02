enum ChatMessageType { text, system, betReceipt, resultCard, image }

class ChatMessageModel {
  const ChatMessageModel({
    required this.id,
    required this.sender,
    required this.content,
    required this.time,
    this.type = ChatMessageType.text,
    this.isAdmin = false,
    this.issueNo,
    this.drawRanks,
  });

  final String id;
  final String sender;
  final String content;
  final String time;
  final ChatMessageType type;
  final bool isAdmin;
  final String? issueNo;
  final List<int>? drawRanks;

  static const mockList = [
    ChatMessageModel(
      id: '1',
      sender: '管理员',
      content: '34089571期已开奖 中奖名单如下:\n=======================',
      time: '13:43',
      isAdmin: true,
    ),
    ChatMessageModel(
      id: '2',
      sender: '管理员',
      content: '[开奖结果卡片]',
      time: '13:43',
      type: ChatMessageType.resultCard,
      isAdmin: true,
    ),
  ];
}
