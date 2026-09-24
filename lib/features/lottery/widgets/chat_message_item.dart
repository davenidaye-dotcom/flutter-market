import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../config/theme/app_colors.dart';
import '../../../data/models/chat_message_model.dart';
import '../../../shared/widgets/lottery_ball.dart';
import '../../../shared/widgets/user_avatar.dart';
import '../utils/draw_result_parse.dart';

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
  const ChatMessageItem({super.key, required this.message});

  final ChatMessageModel message;

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
        fontSize: 16.sp,
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
                    style: TextStyle(fontSize: 11.sp, color: AppColors.textSecondary),
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
    // 用户下注：左侧默认头像（自己和他人同一套，对齐竞品）
    return _UserBetBubble(message: message);
  }

  Widget _buildRobotSystemBody() {
    if (message.type == ChatMessageType.resultCard) {
      return _ResultCard(message: message);
    }
    if (message.type == ChatMessageType.system) {
      return _SystemNotice(content: message.content, issueNo: message.issueNo);
    }
    return Text(
      message.content,
      style: TextStyle(
        fontSize: 16.sp,
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
                  style: TextStyle(fontSize: 11.sp, color: AppColors.textSecondary),
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
    return Padding(
      padding: EdgeInsets.only(bottom: 12.h),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          UserAvatar(
            codeOrUrl: message.avatarUrl,
            radius: 18.r,
            backgroundColor: const Color(0xFFBDBDBD),
          ),
          SizedBox(width: 8.w),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  message.time.trim().isEmpty ? name : '$name  ${message.time}',
                  style: TextStyle(fontSize: 11.sp, color: AppColors.textSecondary),
                ),
                SizedBox(height: 4.h),
                Container(
                  constraints: BoxConstraints(maxWidth: 0.72.sw),
                  padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF2F2F2),
                    borderRadius: BorderRadius.circular(8.r),
                  ),
                  child: Text(
                    message.content,
                    style: TextStyle(
                      fontSize: 16.sp,
                      height: 1.35,
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
          fontSize: 16.sp,
          color: const Color(0xFFE65100),
          fontWeight: FontWeight.w600,
          height: 1.35,
        ),
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.message});

  final ChatMessageModel message;

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

    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 14.h),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1A1A2E), Color(0xFF16213E)],
        ),
        borderRadius: BorderRadius.circular(10.r),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '开奖结果',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 12.sp,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (issue != null && issue.isNotEmpty) ...[
            SizedBox(height: 8.h),
            Text(
              '第$issue期',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18.sp,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
          ],
          if (ranks.isNotEmpty) ...[
            SizedBox(height: 10.h),
            LayoutBuilder(
              builder: (context, constraints) {
                const count = 10;
                final gap = 2.w;
                final size = ((constraints.maxWidth - gap * (count - 1)) / count)
                    .clamp(14.0, 20.w);
                return LotteryBallRow(
                  numbers: ranks,
                  ballSize: size,
                  gap: gap,
                );
              },
            ),
          ] else if (message.content.isNotEmpty) ...[
            SizedBox(height: 8.h),
            Text(
              message.content,
              style: TextStyle(color: Colors.white, fontSize: 13.sp, height: 1.35),
            ),
          ],
        ],
      ),
    );
  }
}
