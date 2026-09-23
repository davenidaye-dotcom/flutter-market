enum ChatMessageType {
  text,
  system,
  betReceipt,
  resultCard,
  /// 封盘后「竞猜列表核对」
  betListCheck,
  /// 开奖后「中奖列表核对」
  winCheck,
  image,
}

class ChatMessageModel {
  const ChatMessageModel({
    required this.id,
    required this.sender,
    required this.content,
    required this.time,
    this.type = ChatMessageType.text,
    this.isAdmin = false,
    this.isSelf = false,
    this.issueNo,
    this.drawRanks,
    this.avatarUrl,
    this.seq = 0,
    this.pair = 0,
  });

  final String id;
  final String sender;
  final String content;
  final String time;
  final ChatMessageType type;
  final bool isAdmin;
  /// 自己的下注/发言：右对齐；他人：左对齐带头像（竞品布局）
  final bool isSelf;
  final String? issueNo;
  final List<int>? drawRanks;
  /// 头像编码（av01）或历史 URL
  final String? avatarUrl;
  /// 房间流序号。0 表示旧数据，仍按期号阶段排。
  final int seq;
  /// 同一序号里的行号。0 下注文字，1 回执。
  final int pair;

  ChatMessageModel copyWith({
    String? id,
    String? sender,
    String? content,
    String? time,
    ChatMessageType? type,
    bool? isAdmin,
    bool? isSelf,
    String? issueNo,
    List<int>? drawRanks,
    String? avatarUrl,
    int? seq,
    int? pair,
  }) {
    return ChatMessageModel(
      id: id ?? this.id,
      sender: sender ?? this.sender,
      content: content ?? this.content,
      time: time ?? this.time,
      type: type ?? this.type,
      isAdmin: isAdmin ?? this.isAdmin,
      isSelf: isSelf ?? this.isSelf,
      issueNo: issueNo ?? this.issueNo,
      drawRanks: drawRanks ?? this.drawRanks,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      seq: seq ?? this.seq,
      pair: pair ?? this.pair,
    );
  }

  static const mockList = [
    ChatMessageModel(
      id: '1',
      sender: '机器人',
      content: '34089571期已开奖 中奖名单如下:\n=======================',
      time: '13:43',
      isAdmin: true,
    ),
    ChatMessageModel(
      id: '2',
      sender: '机器人',
      content: '[开奖结果卡片]',
      time: '13:43',
      type: ChatMessageType.resultCard,
      isAdmin: true,
    ),
  ];
}
