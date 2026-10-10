import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../config/theme/app_colors.dart';
import '../../../data/models/chat_message_model.dart';
import '../../../shared/widgets/lottery_ball.dart';
import '../../../shared/widgets/user_avatar.dart';
import '../utils/draw_result_parse.dart';
import 'history_draw_panel.dart';

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
    final gy = ranks.length >= 2 ? ranks[0] + ranks[1] : null;
    final gyLabel = gy == null
        ? ''
        : '冠亚和 $gy ${gy >= 12 ? '大' : '小'} ${gy.isOdd ? '单' : '双'}';
    final dtLabel = _dragonTigerLine(ranks);

    return Container(
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10.r),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF1B2740), Color(0xFF0E1524)],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(10.w, 10.h, 10.w, 6.h),
            child: Row(
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13.sp,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(width: 8.w),
                if (ranks.isNotEmpty)
                  Expanded(
                    child: SizedBox(
                      height: 20.h,
                      child: LotteryBallRow(
                        numbers: ranks,
                        expandSlots: true,
                        gap: 2.w,
                        digitFontSize: 10.sp,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (podium.isNotEmpty)
            Padding(
              padding: EdgeInsets.fromLTRB(8.w, 4.h, 8.w, 8.h),
              child: _PodiumCars(numbers: podium),
            ),
          Container(
            color: Colors.black.withValues(alpha: 0.55),
            padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 7.h),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    issue != null && issue.isNotEmpty ? '期号 No.$issue' : title,
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 10.sp,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (gyLabel.isNotEmpty)
                  Text(
                    gyLabel,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 10.sp,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                if (dtLabel.isNotEmpty) ...[
                  SizedBox(width: 8.w),
                  Flexible(
                    child: Text(
                      dtLabel,
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 10.sp,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 1-5 名 vs 10-6 名龙虎串。
  static String _dragonTigerLine(List<int> ranks) {
    if (ranks.length < 10) return '';
    final buf = StringBuffer('1-5龙虎 ');
    for (var i = 0; i < 5; i++) {
      buf.write(ranks[i] > ranks[9 - i] ? '龙' : '虎');
    }
    return buf.toString();
  }
}

/// 前三名领奖台：银 / 金 / 铜，车身色跟号色走。
class _PodiumCars extends StatelessWidget {
  const _PodiumCars({required this.numbers});

  final List<int> numbers;

  @override
  Widget build(BuildContext context) {
    final first = numbers.isNotEmpty ? numbers[0] : 0;
    final second = numbers.length > 1 ? numbers[1] : 0;
    final third = numbers.length > 2 ? numbers[2] : 0;
    return SizedBox(
      height: 118.h,
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: CustomPaint(
              size: Size(double.infinity, 36.h),
              painter: _PodiumBasePainter(),
            ),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: _PodiumSlot(
                  place: 2,
                  number: second,
                  cupColor: const Color(0xFFC0C0C0),
                  height: 88.h,
                ),
              ),
              Expanded(
                child: _PodiumSlot(
                  place: 1,
                  number: first,
                  cupColor: const Color(0xFFFFC107),
                  height: 108.h,
                ),
              ),
              Expanded(
                child: _PodiumSlot(
                  place: 3,
                  number: third,
                  cupColor: const Color(0xFFCD7F32),
                  height: 78.h,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PodiumSlot extends StatelessWidget {
  const _PodiumSlot({
    required this.place,
    required this.number,
    required this.cupColor,
    required this.height,
  });

  final int place;
  final int number;
  final Color cupColor;
  final double height;

  @override
  Widget build(BuildContext context) {
    if (number <= 0) return SizedBox(height: height);
    final carColor = AppColors.ballColors[number] ?? AppColors.navBlue;
    return SizedBox(
      height: height,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Icon(Icons.emoji_events, color: cupColor, size: place == 1 ? 28.sp : 22.sp),
          Text(
            '$number',
            style: TextStyle(
              color: cupColor,
              fontSize: place == 1 ? 16.sp : 13.sp,
              fontWeight: FontWeight.w800,
            ),
          ),
          SizedBox(height: 2.h),
          _RaceCarChip(number: number, color: carColor, wide: place == 1),
          SizedBox(height: place == 1 ? 18.h : (place == 2 ? 12.h : 8.h)),
        ],
      ),
    );
  }
}

class _RaceCarChip extends StatelessWidget {
  const _RaceCarChip({
    required this.number,
    required this.color,
    this.wide = false,
  });

  final int number;
  final Color color;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final w = wide ? 56.w : 48.w;
    final h = wide ? 28.h : 24.h;
    return Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color.lerp(color, Colors.white, 0.22)!,
            color,
            Color.lerp(color, Colors.black, 0.18)!,
          ],
        ),
        borderRadius: BorderRadius.circular(6.r),
        border: Border.all(color: Colors.white24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Text(
        '$number',
        style: TextStyle(
          color: Colors.white,
          fontSize: wide ? 14.sp : 12.sp,
          fontWeight: FontWeight.w800,
          shadows: const [
            Shadow(color: Colors.black54, blurRadius: 2, offset: Offset(0, 1)),
          ],
        ),
      ),
    );
  }
}

class _PodiumBasePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0xFF2A3548);
    final path = Path()
      ..moveTo(0, size.height * 0.55)
      ..lineTo(size.width * 0.33, size.height * 0.35)
      ..lineTo(size.width * 0.5, size.height * 0.15)
      ..lineTo(size.width * 0.67, size.height * 0.4)
      ..lineTo(size.width, size.height * 0.55)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(path, paint);
    final edge = Paint()
      ..color = const Color(0xFF3D4A63)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawPath(path, edge);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
