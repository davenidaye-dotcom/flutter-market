import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';

import '../../config/env/env_config.dart';
import '../../config/theme/app_colors.dart';
import '../../core/network/session_store.dart';
import '../../shared/format/display_number.dart';
import '../wallet/utils/draw_snapshot_utils.dart';

Map<String, dynamic> csMessageRow(Map<String, dynamic> raw) {
  return {
    'id': '${raw['id'] ?? ''}',
    'direction': (raw['direction'] ?? '').toString().toUpperCase(),
    'content': raw['content']?.toString() ?? '',
    'msgType': (raw['msgType'] ?? 'TEXT').toString().toUpperCase(),
    'mediaId': '${raw['mediaId'] ?? ''}',
    'refType': '${raw['refType'] ?? ''}',
    'refId': '${raw['refId'] ?? ''}',
    'createdAt': raw['createdAt']?.toString() ?? '',
  };
}

Map<String, dynamic> csPushRow(dynamic push) {
  return {
    'id': push.messageId,
    'direction': push.direction,
    'content': push.content,
    'msgType': push.msgType,
    'mediaId': push.mediaId,
    'refType': push.refType,
    'refId': push.refId,
    'createdAt': push.createdAt,
  };
}

String csMediaFileUrl({required bool owner, required String mediaId}) {
  final base = EnvConfig.apiBaseUrl.replaceAll(RegExp(r'/+$'), '');
  final path = owner
      ? '/owner/cs/media/$mediaId/file'
      : '/member/cs/media/$mediaId/file';
  return '$base$path';
}

Map<String, String> csAuthHeaders() {
  final token = SessionStore.instance.accessToken;
  final headers = <String, String>{
    'clientid': EnvConfig.clientId,
  };
  if (token != null && token.isNotEmpty) {
    headers['Authorization'] = 'Bearer $token';
  }
  final roomId = SessionStore.instance.roomId;
  if (roomId != null && roomId.isNotEmpty) {
    headers['X-Room-Id'] = roomId;
  }
  return headers;
}

String csAgentSummaryRefId(String startDate, String endDate) =>
    '${startDate.trim()}_${endDate.trim()}';

String csAgentDownlineRefId(
  String accountId,
  String startDate,
  String endDate,
) =>
    '${accountId.trim()}_${startDate.trim()}_${endDate.trim()}';

String csShareChipLabel(String refType, {String? applyType}) {
  switch (refType.trim().toUpperCase()) {
    case 'BET_ORDER':
      return '注单';
    case 'SCORE_APP':
      final t = (applyType ?? '').toUpperCase();
      if (t == 'UP') return '上分';
      if (t == 'DOWN') return '下分';
      return '上下分';
    case 'WELFARE_LEDGER':
      return '福利';
    case 'POINT_LEDGER':
      return '积分';
    case 'REBATE_PAYOUT':
      return '回水';
    case 'AGENT_SUMMARY':
      return '代理汇总';
    case 'AGENT_DOWNLINE':
      return '下级玩家';
    default:
      return '分享';
  }
}

Future<XFile?> pickCsGalleryImage() async {
  final picker = ImagePicker();
  return picker.pickImage(
    source: ImageSource.gallery,
    imageQuality: 85,
    maxWidth: 1920,
  );
}

Future<XFile?> pickCsGalleryVideo() async {
  final picker = ImagePicker();
  return picker.pickVideo(
    source: ImageSource.gallery,
    maxDuration: const Duration(seconds: 60),
  );
}

/// 微信风底部宫格：相册 / 视频。逻辑仍走 image_picker。
class CsAttachPanel extends StatelessWidget {
  const CsAttachPanel({
    super.key,
    required this.onPickImage,
    required this.onPickVideo,
    this.enabled = true,
  });

  final VoidCallback onPickImage;
  final VoidCallback onPickVideo;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: const Color(0xFFF5F5F5),
      padding: EdgeInsets.fromLTRB(20.w, 16.h, 20.w, 20.h),
      child: Row(
        children: [
          _AttachTile(
            icon: Icons.photo_outlined,
            label: '相册',
            enabled: enabled,
            onTap: onPickImage,
          ),
          SizedBox(width: 28.w),
          _AttachTile(
            icon: Icons.videocam_outlined,
            label: '视频',
            enabled: enabled,
            onTap: onPickVideo,
          ),
        ],
      ),
    );
  }
}

class _AttachTile extends StatelessWidget {
  const _AttachTile({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.enabled,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(12.r),
      child: SizedBox(
        width: 64.w,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 52.w,
              height: 52.w,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12.r),
                border: Border.all(color: const Color(0xFFE0E0E0)),
              ),
              child: Icon(
                icon,
                size: 26.sp,
                color: enabled ? AppColors.textPrimary : AppColors.textHint,
              ),
            ),
            SizedBox(height: 6.h),
            Text(
              label,
              style: TextStyle(
                fontSize: 12.sp,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class CsMessageBubble extends StatelessWidget {
  const CsMessageBubble({
    super.key,
    required this.message,
    required this.mine,
    required this.ownerSide,
    this.onOpenShare,
  });

  final Map<String, dynamic> message;
  final bool mine;
  final bool ownerSide;
  final VoidCallback? onOpenShare;

  @override
  Widget build(BuildContext context) {
    final type = (message['msgType'] ?? 'TEXT').toString().toUpperCase();
    final content = message['content']?.toString() ?? '';
    final mediaId = message['mediaId']?.toString() ?? '';
    final refType = message['refType']?.toString() ?? '';

    if (type == 'IMAGE') {
      return Align(
        alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          constraints: BoxConstraints(maxWidth: 0.78.sw),
          margin: EdgeInsets.only(bottom: 12.h),
          padding: EdgeInsets.all(3.w),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10.r),
            border: Border.all(color: const Color(0xFFE0E0E0)),
          ),
          child: _ImageBody(
            mediaId: mediaId,
            ownerSide: ownerSide,
            fallback: content,
            fg: AppColors.textPrimary,
          ),
        ),
      );
    }

    if (type == 'VIDEO') {
      return Align(
        alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          constraints: BoxConstraints(maxWidth: 0.72.sw),
          margin: EdgeInsets.only(bottom: 12.h),
          child: _VideoBody(
            mediaId: mediaId,
            ownerSide: ownerSide,
            fallback: content,
          ),
        ),
      );
    }

    if (type == 'SHARE') {
      return Align(
        alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          constraints: BoxConstraints(maxWidth: 0.84.sw),
          margin: EdgeInsets.only(bottom: 12.h),
          child: Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12.r),
            child: InkWell(
              onTap: onOpenShare,
              borderRadius: BorderRadius.circular(12.r),
              child: Container(
                padding: EdgeInsets.fromLTRB(12.w, 12.h, 12.w, 10.h),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12.r),
                  border: Border.all(color: const Color(0xFFE0E0E0)),
                ),
                child: _ShareCardBody(
                  refType: refType,
                  content: content,
                ),
              ),
            ),
          ),
        ),
      );
    }

    final radius = BorderRadius.only(
      topLeft: Radius.circular(14.r),
      topRight: Radius.circular(14.r),
      bottomLeft: Radius.circular(mine ? 14.r : 4.r),
      bottomRight: Radius.circular(mine ? 4.r : 14.r),
    );
    final bg = mine ? AppColors.navBlue : AppColors.sidebarInactive;
    final fg = mine ? Colors.white : AppColors.textPrimary;

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: 0.72.sw),
        margin: EdgeInsets.only(bottom: 12.h),
        padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
        decoration: BoxDecoration(color: bg, borderRadius: radius),
        child: Text(
          content,
          style: TextStyle(fontSize: 14.sp, height: 1.45, color: fg),
        ),
      ),
    );
  }
}

class _ShareCardBody extends StatelessWidget {
  const _ShareCardBody({
    required this.refType,
    required this.content,
  });

  final String refType;
  final String content;

  @override
  Widget build(BuildContext context) {
    final chip = csShareChipLabel(refType);
    final tone = _chipTone(refType);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 2.h),
              decoration: BoxDecoration(
                color: tone.$1,
                borderRadius: BorderRadius.circular(4.r),
              ),
              child: Text(
                chip,
                style: TextStyle(
                  fontSize: 11.sp,
                  color: tone.$2,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            SizedBox(width: 6.w),
            Text(
              '业务分享',
              style: TextStyle(
                fontSize: 11.sp,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
        SizedBox(height: 8.h),
        Text(
          content.isEmpty ? '[分享]' : content,
          style: TextStyle(
            fontSize: 14.sp,
            height: 1.35,
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        SizedBox(height: 6.h),
        Text(
          '查看详情',
          style: TextStyle(fontSize: 11.sp, color: AppColors.navBlue),
        ),
      ],
    );
  }

  (Color, Color) _chipTone(String refType) {
    switch (refType.trim().toUpperCase()) {
      case 'SCORE_APP':
        return (const Color(0xFFE8F5E9), const Color(0xFF2E7D32));
      case 'BET_ORDER':
        return (const Color(0xFFE3F2FD), const Color(0xFF1565C0));
      case 'WELFARE_LEDGER':
      case 'REBATE_PAYOUT':
        return (const Color(0xFFFFF3E0), const Color(0xFFEF6C00));
      case 'POINT_LEDGER':
        return (const Color(0xFFF3E5F5), const Color(0xFF7B1FA2));
      case 'AGENT_SUMMARY':
      case 'AGENT_DOWNLINE':
        return (const Color(0xFFE0F2F1), const Color(0xFF00695C));
      default:
        return (const Color(0xFFF5F5F5), const Color(0xFF616161));
    }
  }
}

class _ImageBody extends StatelessWidget {
  const _ImageBody({
    required this.mediaId,
    required this.ownerSide,
    required this.fallback,
    required this.fg,
  });

  final String mediaId;
  final bool ownerSide;
  final String fallback;
  final Color fg;

  @override
  Widget build(BuildContext context) {
    if (mediaId.isEmpty) {
      return Padding(
        padding: EdgeInsets.all(10.w),
        child: Text(
          fallback.isEmpty ? '[图片]' : fallback,
          style: TextStyle(fontSize: 14.sp, color: fg),
        ),
      );
    }
    final url = csMediaFileUrl(owner: ownerSide, mediaId: mediaId);
    return GestureDetector(
      onTap: () {
        showDialog<void>(
          context: context,
          builder: (_) => Dialog(
            backgroundColor: Colors.black,
            insetPadding: EdgeInsets.all(12.w),
            child: InteractiveViewer(
              child: Image.network(
                url,
                headers: csAuthHeaders(),
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => Center(
                  child: Text(
                    '图片加载失败',
                    style: TextStyle(color: Colors.white, fontSize: 14.sp),
                  ),
                ),
              ),
            ),
          ),
        );
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8.r),
        child: Image.network(
          url,
          headers: csAuthHeaders(),
          width: 180.w,
          height: 140.h,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => SizedBox(
            width: 120.w,
            height: 80.h,
            child: Center(
              child: Text('[图片]', style: TextStyle(color: fg, fontSize: 13.sp)),
            ),
          ),
        ),
      ),
    );
  }
}

class _VideoBody extends StatelessWidget {
  const _VideoBody({
    required this.mediaId,
    required this.ownerSide,
    required this.fallback,
  });

  final String mediaId;
  final bool ownerSide;
  final String fallback;

  @override
  Widget build(BuildContext context) {
    if (mediaId.isEmpty) {
      return Container(
        padding: EdgeInsets.all(12.w),
        decoration: BoxDecoration(
          color: const Color(0xFFF0F0F0),
          borderRadius: BorderRadius.circular(10.r),
          border: Border.all(color: const Color(0xFFE0E0E0)),
        ),
        child: Text(
          fallback.isEmpty ? '[视频]' : fallback,
          style: TextStyle(fontSize: 14.sp, color: AppColors.textPrimary),
        ),
      );
    }
    return InkWell(
      onTap: () {
        final url = csMediaFileUrl(owner: ownerSide, mediaId: mediaId);
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => _CsVideoPage(url: url),
          ),
        );
      },
      borderRadius: BorderRadius.circular(10.r),
      child: Container(
        width: 180.w,
        height: 110.h,
        decoration: BoxDecoration(
          color: const Color(0xFFF0F0F0),
          borderRadius: BorderRadius.circular(10.r),
          border: Border.all(color: const Color(0xFFE0E0E0)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.play_circle_filled,
              size: 42.sp,
              color: AppColors.textSecondary,
            ),
            SizedBox(height: 4.h),
            Text(
              '视频',
              style: TextStyle(
                fontSize: 12.sp,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CsVideoPage extends StatefulWidget {
  const _CsVideoPage({required this.url});
  final String url;

  @override
  State<_CsVideoPage> createState() => _CsVideoPageState();
}

class _CsVideoPageState extends State<_CsVideoPage> {
  late final VideoPlayerController _ctrl;
  bool _ready = false;
  String? _err;

  @override
  void initState() {
    super.initState();
    _ctrl = VideoPlayerController.networkUrl(
      Uri.parse(widget.url),
      httpHeaders: csAuthHeaders(),
    );
    _ctrl.initialize().then((_) {
      if (!mounted) return;
      setState(() => _ready = true);
      _ctrl.play();
    }).catchError((e) {
      if (!mounted) return;
      setState(() => _err = e.toString());
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('视频'),
      ),
      body: Center(
        child: _err != null
            ? Text(_err!, style: const TextStyle(color: Colors.white))
            : !_ready
                ? const CircularProgressIndicator(color: Colors.white)
                : AspectRatio(
                    aspectRatio: _ctrl.value.aspectRatio == 0
                        ? 16 / 9
                        : _ctrl.value.aspectRatio,
                    child: VideoPlayer(_ctrl),
                  ),
      ),
      floatingActionButton: _ready
          ? FloatingActionButton(
              onPressed: () {
                setState(() {
                  _ctrl.value.isPlaying ? _ctrl.pause() : _ctrl.play();
                });
              },
              child: Icon(
                _ctrl.value.isPlaying ? Icons.pause : Icons.play_arrow,
              ),
            )
          : null,
    );
  }
}

String _csStatusLabel(String refType, dynamic raw) {
  final s = '${raw ?? ''}'.trim();
  if (s.isEmpty) return '';
  final type = refType.toUpperCase();
  if (type == 'BET_ORDER') return betStatusLabel(s);
  if (type == 'SCORE_APP') return applyStatusLabel(s);
  return s;
}

String _csTypeLabel(String refType, dynamic raw) {
  final s = '${raw ?? ''}'.trim();
  if (s.isEmpty) return '';
  final type = refType.toUpperCase();
  if (type == 'SCORE_APP') {
    return switch (s.toUpperCase()) {
      'UP' => '上分',
      'DOWN' => '下分',
      _ => s,
    };
  }
  if (type == 'WELFARE_LEDGER' ||
      type == 'POINT_LEDGER' ||
      type == 'REBATE_PAYOUT') {
    return ledgerChangeLabel(s);
  }
  return s;
}

Future<void> showCsRefSheet(
  BuildContext context,
  Map<String, dynamic> ref,
) async {
  final type = (ref['refType'] ?? '').toString().toUpperCase();
  final title = ref['title']?.toString() ?? '详情';
  final statusRaw = ref['status'];
  final statusText = _csStatusLabel(type, statusRaw);
  dynamic heroAmount = ref['amount'] ?? ref['totalAmount'] ?? ref['paidCommission'];

  final entries = <(String, String)>[];
  void add(String k, dynamic v, {bool money = false, bool asStatus = false, bool asType = false}) {
    if (v == null) return;
    String s;
    if (asStatus) {
      s = _csStatusLabel(type, v);
    } else if (asType) {
      s = _csTypeLabel(type, v);
    } else if (money || v is num) {
      s = displayNumber(v);
    } else {
      s = '$v'.trim();
    }
    if (s.isEmpty) return;
    entries.add((k, s));
  }

  switch (type) {
    case 'BET_ORDER':
      add('单号', ref['orderId']);
      add('彩种', ref['gameType']);
      add('期号', ref['issueNo']);
      add('金额', ref['totalAmount'], money: true);
      add('状态', ref['status'], asStatus: true);
      add('内容', ref['content']);
    case 'SCORE_APP':
      add('申请号', ref['applicationId']);
      add('类型', ref['applyType'], asType: true);
      add('金额', ref['amount'], money: true);
      add('状态', ref['status'], asStatus: true);
      add('备注', ref['remark']);
    case 'WELFARE_LEDGER':
    case 'POINT_LEDGER':
      add('账变号', ref['ledgerId']);
      add('类型', ref['changeType'], asType: true);
      add('金额', ref['amount'], money: true);
      add('余额', ref['balanceAfter'], money: true);
      add('期号', ref['issueNo']);
      add('备注', ref['remark']);
    case 'REBATE_PAYOUT':
      add('发放号', ref['payoutId']);
      add('金额', ref['amount'], money: true);
      add('类型', ref['kind'], asType: true);
      add('来源', ref['source']);
      add('备注', ref['remark']);
    case 'AGENT_SUMMARY':
      heroAmount = ref['paidCommission'];
      add('已返佣金', ref['paidCommission'], money: true);
      add('待领佣金', ref['unpaidCommission'], money: true);
      add('旗下流水', ref['subordinateTurnover'], money: true);
      add('下级人数', ref['subordinateCount']);
      add('区间', ref['dateRange']);
    case 'AGENT_DOWNLINE':
      heroAmount = ref['subordinateTurnover'];
      add('昵称', ref['nickname'] ?? ref['label']);
      add('玩家ID', ref['accountId']);
      add('流水', ref['subordinateTurnover'], money: true);
      add('抽佣比例', ref['commissionRatio'] == null
          ? null
          : '${displayNumber(ref['commissionRatio'])}%');
      add('已返佣', ref['paidCommission'], money: true);
      add('未返佣', ref['unpaidCommission'], money: true);
      add('区间', ref['dateRange']);
    default:
      final summary = ref['summary']?.toString() ?? '';
      if (summary.isNotEmpty) add('摘要', summary);
  }

  final amountText = heroAmount == null ? '' : displayNumber(heroAmount);
  final chip = csShareChipLabel(
    type,
    applyType: ref['applyType']?.toString(),
  );

  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.white,
    isScrollControlled: true,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(14.r)),
    ),
    builder: (ctx) {
      return Padding(
        padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 28.h),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 16.sp,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (statusText.isNotEmpty)
                  Container(
                    padding:
                        EdgeInsets.symmetric(horizontal: 8.w, vertical: 3.h),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8F5E9),
                      borderRadius: BorderRadius.circular(4.r),
                    ),
                    child: Text(
                      statusText,
                      style: TextStyle(
                        fontSize: 11.sp,
                        color: const Color(0xFF2E7D32),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  )
                else
                  Container(
                    padding:
                        EdgeInsets.symmetric(horizontal: 8.w, vertical: 3.h),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE3F2FD),
                      borderRadius: BorderRadius.circular(4.r),
                    ),
                    child: Text(
                      chip,
                      style: TextStyle(
                        fontSize: 11.sp,
                        color: const Color(0xFF1565C0),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
            if (amountText.isNotEmpty) ...[
              SizedBox(height: 10.h),
              Text(
                amountText,
                style: TextStyle(
                  fontSize: 28.sp,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
            SizedBox(height: 12.h),
            const Divider(height: 1),
            SizedBox(height: 12.h),
            for (final e in entries) ...[
              Padding(
                padding: EdgeInsets.only(bottom: 10.h),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 76.w,
                      child: Text(
                        e.$1,
                        style: TextStyle(
                          fontSize: 12.sp,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        e.$2,
                        style: TextStyle(fontSize: 13.sp),
                        textAlign: TextAlign.right,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      );
    },
  );
}
