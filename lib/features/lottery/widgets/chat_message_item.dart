import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../config/theme/app_colors.dart';
import '../../../data/models/chat_message_model.dart';
import '../../../shared/widgets/user_avatar.dart';
import '../utils/draw_result_parse.dart';
import 'lottery_result_stage.dart';

bool _isRobotName(String raw) {
  final s = raw.trim();
  return s.isEmpty || s == '机器人' || s == '管理员';
}

String _displaySender(String raw) {
  final s = raw.trim();
  if (s.isEmpty || s == '管理员') return '机器人';
  return s;
}

class ChatMessageItem extends StatelessWidget {
  const ChatMessageItem({
    super.key,
    required this.message,
    this.gameName,
  });

  final ChatMessageModel message;
  /// 开奖卡左下角游戏名；不传则显示「开奖结果」
  final String? gameName;

  bool get _isRobotSystemLayout =>
      message.type == ChatMessageType.system ||
      message.type == ChatMessageType.resultCard ||
      message.isAdmin;

  @override
  Widget build(BuildContext context) {
    if (message.type == ChatMessageType.betReceipt ||
        message.type == ChatMessageType.winCheck ||
        message.type == ChatMessageType.betListCheck) {
      return _RobotBubble(
        message: message,
        // 投注成功 / 竞猜核对 / 中奖核对 正文统一字号
        fontSize: 14.sp,
      );
    }
    if (_isRobotSystemLayout) {
      return Padding(
        padding: EdgeInsets.only(bottom: 12.h),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
          CircleAvatar(
              radius: 18.r,
              backgroundColor: _isRobotName(message.sender)
                  ? const Color(0xFF7E57C2)
                  : AppColors.textPrimary,
              child: Icon(
                _isRobotName(message.sender) ? Icons.smart_toy : Icons.person,
                color: Colors.white,
                size: 18.sp,
              ),
            ),
            SizedBox(width: 8.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    message.time.trim().isEmpty
                        ? _displaySender(message.sender)
                        : '${_displaySender(message.sender)}  ${message.time}',
                    style: TextStyle(fontSize: 12.sp, color: AppColors.textSecondary),
                  ),
                  SizedBox(height: 4.h),
                  Container(
                    width: double.infinity,
                    padding: EdgeInsets.all(10.w),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8.r),
                    ),
                    child: _buildRobotSystemBody(),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }
    // 用户下注：自己右对齐，他人左对齐
    return _UserBetBubble(message: message);
  }

  Widget _buildRobotSystemBody() {
    if (message.type == ChatMessageType.resultCard) {
      return _ResultCard(message: message, gameName: gameName);
    }
    if (message.type == ChatMessageType.system) {
      return _SystemNotice(content: message.content, issueNo: message.issueNo);
    }
    return Text(
      message.content,
      style: TextStyle(
        fontSize: 14.sp,
        color: Colors.black,
        fontWeight: FontWeight.bold,
      ),
    );
  }
}

class _RobotBubble extends StatelessWidget {
  const _RobotBubble({required this.message, required this.fontSize});

  final ChatMessageModel message;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: 12.h),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 18.r,
            backgroundColor: const Color(0xFF7E57C2),
            child: Icon(Icons.smart_toy, color: Colors.white, size: 18.sp),
          ),
          SizedBox(width: 8.w),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  () {
                    final name = _displaySender(message.sender);
                    return message.time.trim().isEmpty ? name : '$name  ${message.time}';
                  }(),
                  style: TextStyle(fontSize: 12.sp, color: AppColors.textSecondary),
                ),
                SizedBox(height: 4.h),
                Container(
                  constraints: BoxConstraints(maxWidth: 0.78.sw),
                  padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF2F2F2),
                    borderRadius: BorderRadius.circular(8.r),
                  ),
                  child: Text(
                    message.content,
                    style: TextStyle(
                      fontSize: fontSize,
                      height: 1.45,
                      color: Colors.black,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _UserBetBubble extends StatelessWidget {
  const _UserBetBubble({required this.message});

  final ChatMessageModel message;

  @override
  Widget build(BuildContext context) {
    final name = message.sender.trim().isEmpty ? '会员' : message.sender.trim();
    final mine = message.isSelf;
    final meta = message.time.trim().isEmpty
        ? name
        : (mine ? '${message.time}  $name' : '$name  ${message.time}');
    final avatar = UserAvatar(
      codeOrUrl: message.avatarUrl,
      radius: 18.r,
      backgroundColor: mine ? AppColors.navBlue : const Color(0xFFBDBDBD),
    );
    final bubble = Container(
      constraints: BoxConstraints(maxWidth: 0.72.sw),
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
      decoration: BoxDecoration(
        color: mine ? AppColors.navBlue : const Color(0xFFF2F2F2),
        borderRadius: BorderRadius.circular(8.r),
      ),
      child: Text(
        message.content,
        style: TextStyle(
          fontSize: 14.sp,
          height: 1.35,
          color: mine ? Colors.white : Colors.black,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
    final body = Column(
      crossAxisAlignment:
          mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Text(
          meta,
          style: TextStyle(fontSize: 12.sp, color: AppColors.textSecondary),
        ),
        SizedBox(height: 4.h),
        bubble,
      ],
    );
    // 自己：贴内容区右缘（与开奖结果卡右缘对齐），去掉 Spacer 避免短气泡漂中间。
    return Padding(
      padding: EdgeInsets.only(bottom: 12.h),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment:
            mine ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: mine
            ? [
                Flexible(child: body),
                SizedBox(width: 8.w),
                avatar,
              ]
            : [
                avatar,
                SizedBox(width: 8.w),
                Flexible(child: body),
              ],
      ),
    );
  }
}

class _SystemNotice extends StatelessWidget {
  const _SystemNotice({required this.content, this.issueNo});

  final String content;
  final String? issueNo;

  @override
  Widget build(BuildContext context) {
    final issue = (issueNo ?? '').trim();
    final text = issue.isEmpty ? content : '第$issue期\n$content';
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF3E0),
        borderRadius: BorderRadius.circular(8.r),
        border: Border.all(color: const Color(0xFFFFCC80)),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 14.sp,
          color: const Color(0xFFE65100),
          fontWeight: FontWeight.w600,
          height: 1.35,
        ),
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.message, this.gameName});

  final ChatMessageModel message;
  final String? gameName;

  @override
  Widget build(BuildContext context) {
    final parsed = DrawResultParse.parse(message.content);
    final issueRaw = message.issueNo ?? parsed.issueNo;
    final issue =
        issueRaw != null && issueRaw.isNotEmpty ? issueRaw.trim() : null;
    final ranks = (message.drawRanks != null && message.drawRanks!.isNotEmpty)
        ? message.drawRanks!
        : parsed.ranks;
    if ((issue == null || issue.isEmpty) &&
        ranks.isEmpty &&
        message.content.trim().isEmpty) {
      return const SizedBox.shrink();
    }

    final title = (gameName != null && gameName!.trim().isNotEmpty)
        ? gameName!.trim()
        : '开奖结果';
    final podium = ranks.length >= 3
        ? <int>[ranks[0], ranks[1], ranks[2]]
        : ranks;

    final issueNo = issue != null && issue.isNotEmpty ? 'No.$issue' : title;
    return LotteryResultShell(
      borderRadius: BorderRadius.circular(10.r),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LotteryResultBallsHeader(title: title, numbers: ranks),
          if (podium.isNotEmpty) LotteryDrawPodiumScene(numbers: podium),
          LotteryResultFooterColumns(
            issueText: issueNo,
            gyBody: lotteryGyBody(ranks),
            dtBody: lotteryDragonTigerBody(ranks),
          ),
        ],
      ),
    );
  }
}
