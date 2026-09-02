import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../config/theme/app_colors.dart';
import '../../../data/models/chat_message_model.dart';
import '../../../shared/widgets/lottery_ball.dart';
import '../utils/draw_result_parse.dart';

class ChatMessageItem extends StatelessWidget {
  const ChatMessageItem({super.key, required this.message});

  final ChatMessageModel message;

  bool get _isAdminLayout =>
      message.isAdmin ||
      message.type == ChatMessageType.system ||
      message.type == ChatMessageType.resultCard;

  @override
  Widget build(BuildContext context) {
    if (!_isAdminLayout) {
      return _UserMessage(message: message);
    }
    return Padding(
      padding: EdgeInsets.only(bottom: 12.h),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 18.r,
            backgroundColor: AppColors.textPrimary,
            child: Icon(Icons.person, color: Colors.white, size: 18.sp),
          ),
          SizedBox(width: 8.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  message.time.trim().isEmpty
                      ? message.sender
                      : '${message.sender}  ${message.time}',
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
                  child: _buildAdminBody(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAdminBody() {
    if (message.type == ChatMessageType.resultCard) {
      return _ResultCard(message: message);
    }
    if (message.type == ChatMessageType.system) {
      return _SystemNotice(content: message.content);
    }
    return Text(message.content, style: TextStyle(fontSize: 13.sp));
  }
}

class _UserMessage extends StatelessWidget {
  const _UserMessage({required this.message});

  final ChatMessageModel message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: 12.h),
      child: Align(
        alignment: Alignment.centerRight,
        child: Container(
          constraints: BoxConstraints(maxWidth: 0.72.sw),
          padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
          decoration: BoxDecoration(
            color: const Color(0xFF95EC69),
            borderRadius: BorderRadius.circular(8.r),
          ),
          child: Text(message.content, style: TextStyle(fontSize: 13.sp)),
        ),
      ),
    );
  }
}

class _SystemNotice extends StatelessWidget {
  const _SystemNotice({required this.content});

  final String content;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF3E0),
        borderRadius: BorderRadius.circular(8.r),
        border: Border.all(color: const Color(0xFFFFCC80)),
      ),
      child: Text(
        content,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 13.sp,
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
