import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../config/theme/app_colors.dart';
import '../../../data/models/chat_message_model.dart';
import '../../../shared/widgets/user_avatar.dart';
import '../utils/draw_result_parse.dart';
import '../utils/pc28_format.dart';
import '../../../shared/format/game_series.dart';
import 'lottery_result_stage.dart';
import 'pc28_draw_formula.dart';

bool _isRobotName(String raw) {
  final s = raw.trim();
  return s.isEmpty || s == '机器人' || s == '管理员';
}

String _displaySender(String raw) {
  final s = raw.trim();
  if (s.isEmpty || s == '管理员') return '机器人';
  return s;
}

bool _isSealLineSystemContent(String content) {
  return content.contains('封盘线') || content.contains('停止战斗');
}

bool _isSealWarnSystemContent(String content) {
  if (_isSealLineSystemContent(content)) return false;
  return content.contains('距离封盘') || content.contains('不能再投注');
}

class ChatMessageItem extends StatelessWidget {
  const ChatMessageItem({
    super.key,
    required this.message,
    this.gameName,
    this.roomId,
    this.gameId,
  });

  final ChatMessageModel message;

  /// 开奖卡左下角游戏名；不传则显示「开奖结果」
  final String? gameName;

  /// 兼容旧调用，封盘文案已改回纯文字气泡，不再使用。
  final String? roomId;
  final String? gameId;

  bool get _isRobotSystemLayout =>
      message.type == ChatMessageType.system ||
      message.type == ChatMessageType.resultCard ||
      message.isAdmin;

  bool get _isSealTextNotice =>
      message.type == ChatMessageType.system &&
      (_isSealWarnSystemContent(message.content) ||
          _isSealLineSystemContent(message.content));

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
                    style: TextStyle(
                      fontSize: 12.sp,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  SizedBox(height: 4.h),
                  // 封盘预警/封盘线：原版浅橙条（含第N期，无图片壳）
                  if (_isSealTextNotice)
                    _SystemNotice(
                      content: message.content,
                      issueNo: message.issueNo,
                    )
                  else if (message.type == ChatMessageType.resultCard &&
                      GameSeries.isPc28(gameId))
                    _buildRobotSystemBody()
                  else
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
      return _ResultCard(message: message, gameName: gameName, gameId: gameId);
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
                    return message.time.trim().isEmpty
                        ? name
                        : '$name  ${message.time}';
                  }(),
                  style: TextStyle(
                    fontSize: 12.sp,
                    color: AppColors.textSecondary,
                  ),
                ),
                SizedBox(height: 4.h),
                Container(
                  constraints: BoxConstraints(maxWidth: 0.78.sw),
                  padding: EdgeInsets.symmetric(
                    horizontal: 12.w,
                    vertical: 8.h,
                  ),
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
      crossAxisAlignment: mine
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
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
        mainAxisAlignment: mine
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        children: mine
            ? [Flexible(child: body), SizedBox(width: 8.w), avatar]
            : [avatar, SizedBox(width: 8.w), Flexible(child: body)],
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
  const _ResultCard({required this.message, this.gameName, this.gameId});

  final ChatMessageModel message;
  final String? gameName;
  final String? gameId;

  @override
  Widget build(BuildContext context) {
    final parsed = DrawResultParse.parse(message.content);
    final issueRaw = message.issueNo ?? parsed.issueNo;
    final issue = issueRaw != null && issueRaw.isNotEmpty
        ? issueRaw.trim()
        : null;
    final ranks = (message.drawRanks != null && message.drawRanks!.isNotEmpty)
        ? message.drawRanks!
        : parsed.ranks;
    if ((issue == null || issue.isEmpty) &&
        ranks.isEmpty &&
        message.content.trim().isEmpty) {
      return const SizedBox.shrink();
    }

    if (GameSeries.isPc28(gameId) && Pc28Format.valid(ranks)) {
      final title = (gameName != null && gameName!.trim().isNotEmpty)
          ? gameName!.trim()
          : '加拿大PC28';
      return _Pc28ResultCard(title: title, issue: issue, ranks: ranks);
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

class _Pc28ResultCard extends StatelessWidget {
  const _Pc28ResultCard({
    required this.title,
    required this.issue,
    required this.ranks,
  });

  final String title;
  final String? issue;
  final List<int> ranks;

  static const _blue = Color(0xFF1E88E5);
  static const _muted = Color(0xFF9E9E9E);

  @override
  Widget build(BuildContext context) {
    final sum = Pc28Format.sumOf(ranks);
    final combo = Pc28Format.combo(sum);
    final wave = Pc28Format.wave(sum);
    final extreme = Pc28Format.extreme(sum);
    final bao = Pc28Format.leopard(ranks);
    final dt = Pc28Format.dragonTiger(ranks);
    final shownIssue = issue?.trim() ?? '';
    return ClipRRect(
      borderRadius: BorderRadius.circular(8.r),
      child: ColoredBox(
        color: const Color(0xFF111111),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(height: 4, color: Pc28Format.colorOf(sum)),
            Padding(
              padding: EdgeInsets.fromLTRB(10.w, 10.h, 10.w, 10.h),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 14.sp,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                  if (shownIssue.isNotEmpty) ...[
                    SizedBox(height: 2.h),
                    Text(
                      '第$shownIssue期',
                      style: TextStyle(
                        fontSize: 12.sp,
                        color: const Color(0xFFB0B0B0),
                      ),
                    ),
                  ],
                  SizedBox(height: 8.h),
                  Pc28DrawFormula(numbers: ranks, ballSize: 22, gap: 4),
                  SizedBox(height: 8.h),
                  Row(
                    children: [
                      Expanded(child: _tag('大小', _comboText(combo))),
                      SizedBox(width: 4.w),
                      Expanded(
                        child: _tag(
                          '波',
                          _waveValue(wave, Pc28Format.colorOf(sum)),
                        ),
                      ),
                      SizedBox(width: 4.w),
                      Expanded(
                        child: _tag(
                          '龙虎',
                          Text(dt, style: _valueStyle(_dtColor(dt))),
                        ),
                      ),
                      SizedBox(width: 4.w),
                      Expanded(
                        child: _tag(
                          '极',
                          Text(
                            extreme.isEmpty ? '无' : extreme,
                            style: _valueStyle(
                              extreme.isEmpty ? _muted : AppColors.danger,
                            ),
                          ),
                          hot: extreme.isNotEmpty,
                        ),
                      ),
                      SizedBox(width: 4.w),
                      Expanded(
                        child: _tag(
                          '豹',
                          Text(
                            bao ? '豹子' : '无',
                            style: _valueStyle(bao ? Colors.white : _muted),
                          ),
                          solid: bao,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  TextStyle _valueStyle(Color color) => TextStyle(
    fontSize: 12.sp,
    height: 1.1,
    fontWeight: FontWeight.w600,
    color: color,
  );

  Widget _comboText(String combo) {
    return Text.rich(
      TextSpan(
        children: [
          for (final ch in combo.split(''))
            TextSpan(text: ch, style: _valueStyle(_comboColor(ch))),
        ],
      ),
      textAlign: TextAlign.center,
      maxLines: 1,
    );
  }

  Widget _waveValue(String wave, Color color) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 8.w,
          height: 8.w,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        SizedBox(width: 3.w),
        Text(wave, style: _valueStyle(color)),
      ],
    );
  }

  Color _comboColor(String ch) {
    if (ch == '大' || ch == '双') return AppColors.danger;
    if (ch == '小' || ch == '单') return _blue;
    return AppColors.textPrimary;
  }

  Color _dtColor(String dt) {
    return switch (dt) {
      '龙' => AppColors.danger,
      '虎' => _blue,
      _ => const Color(0xFF5A5A5A),
    };
  }

  Widget _tag(
    String name,
    Widget value, {
    bool hot = false,
    bool solid = false,
  }) {
    final nameColor = solid ? Colors.white : _muted;
    return Container(
      padding: EdgeInsets.symmetric(vertical: 4.h, horizontal: 2.w),
      decoration: BoxDecoration(
        color: solid
            ? AppColors.danger
            : hot
            ? const Color(0xFFFFE4E8)
            : const Color(0xFF2A2A2A),
        borderRadius: BorderRadius.circular(4.r),
      ),
      child: Column(
        children: [
          Text(
            name,
            maxLines: 1,
            style: TextStyle(fontSize: 10.sp, height: 1.1, color: nameColor),
          ),
          SizedBox(height: 2.h),
          value,
        ],
      ),
    );
  }
}
