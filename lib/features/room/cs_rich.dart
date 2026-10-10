import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:image_picker/image_picker.dart';

import '../../config/theme/app_colors.dart';
import '../../core/network/api_client.dart';
import '../../shared/format/display_number.dart';
import '../wallet/utils/draw_snapshot_utils.dart';

final Map<String, Uint8List> _csMediaBytesCache = {};

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

String csMediaPath({required bool owner, required String mediaId}) =>
    owner ? '/owner/cs/media/$mediaId/file' : '/member/cs/media/$mediaId/file';

Future<Uint8List> loadCsMediaBytes({
  required bool ownerSide,
  required String mediaId,
}) async {
  final key = '${ownerSide ? 'o' : 'm'}:$mediaId';
  final cached = _csMediaBytesCache[key];
  if (cached != null) return cached;
  final path = csMediaPath(owner: ownerSide, mediaId: mediaId);
  final bytes = await ApiClient.instance.getBytes(path);
  _csMediaBytesCache[key] = bytes;
  return bytes;
}

Future<bool> confirmCsSideDelete(BuildContext context) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('确定删除消息'),
      content: const Text('删除后将不可见'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('删除'),
        ),
      ],
    ),
  );
  return ok == true;
}

Future<bool> confirmCsClearHistory(BuildContext context, {String title = '确定删除消息'}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: const Text('删除后将不可见'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('删除'),
        ),
      ],
    ),
  );
  return ok == true;
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
    imageQuality: 70,
    maxWidth: 1280,
  );
}

/// 微信风底部宫格：仅相册。
class CsAttachPanel extends StatelessWidget {
  const CsAttachPanel({
    super.key,
    required this.onPickImage,
    this.enabled = true,
  });

  final VoidCallback onPickImage;
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
    this.onLongPress,
  });

  final Map<String, dynamic> message;
  final bool mine;
  final bool ownerSide;
  final VoidCallback? onOpenShare;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final type = (message['msgType'] ?? 'TEXT').toString().toUpperCase();
    final content = message['content']?.toString() ?? '';
    final mediaId = message['mediaId']?.toString() ?? '';
    final refType = message['refType']?.toString() ?? '';

    Widget child;
    if (type == 'IMAGE') {
      child = Container(
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
        ),
      );
    } else if (type == 'VIDEO') {
      child = Container(
        constraints: BoxConstraints(maxWidth: 0.72.sw),
        margin: EdgeInsets.only(bottom: 12.h),
        padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
        decoration: BoxDecoration(
          color: const Color(0xFFF0F0F0),
          borderRadius: BorderRadius.circular(10.r),
          border: Border.all(color: const Color(0xFFE0E0E0)),
        ),
        child: Text(
          '视频已停用',
          style: TextStyle(fontSize: 13.sp, color: AppColors.textSecondary),
        ),
      );
    } else if (type == 'SHARE') {
      child = Container(
        constraints: BoxConstraints(maxWidth: 0.84.sw),
        margin: EdgeInsets.only(bottom: 12.h),
        child: Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12.r),
          child: InkWell(
            onTap: onOpenShare,
            onLongPress: onLongPress,
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
      );
    } else {
      final radius = BorderRadius.only(
        topLeft: Radius.circular(14.r),
        topRight: Radius.circular(14.r),
        bottomLeft: Radius.circular(mine ? 14.r : 4.r),
        bottomRight: Radius.circular(mine ? 4.r : 14.r),
      );
      final bg = mine ? AppColors.navBlue : AppColors.sidebarInactive;
      final fg = mine ? Colors.white : AppColors.textPrimary;
      child = Container(
        constraints: BoxConstraints(maxWidth: 0.72.sw),
        margin: EdgeInsets.only(bottom: 12.h),
        padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
        decoration: BoxDecoration(color: bg, borderRadius: radius),
        child: Text(
          content,
          style: TextStyle(fontSize: 14.sp, height: 1.45, color: fg),
        ),
      );
    }

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: onLongPress,
        child: child,
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

class _ImageBody extends StatefulWidget {
  const _ImageBody({
    required this.mediaId,
    required this.ownerSide,
    required this.fallback,
  });

  final String mediaId;
  final bool ownerSide;
  final String fallback;

  @override
  State<_ImageBody> createState() => _ImageBodyState();
}

class _ImageBodyState extends State<_ImageBody> {
  Uint8List? _bytes;
  String? _err;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _ImageBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mediaId != widget.mediaId ||
        oldWidget.ownerSide != widget.ownerSide) {
      _load();
    }
  }

  Future<void> _load() async {
    if (widget.mediaId.isEmpty) {
      setState(() {
        _bytes = null;
        _err = widget.fallback.isEmpty ? '图片无效' : widget.fallback;
        _loading = false;
      });
      return;
    }
    setState(() {
      _loading = true;
      _err = null;
    });
    try {
      final bytes = await loadCsMediaBytes(
        ownerSide: widget.ownerSide,
        mediaId: widget.mediaId,
      );
      if (!mounted) return;
      setState(() {
        _bytes = bytes;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _err = e.toString();
        _loading = false;
      });
    }
  }

  void _openPreview() {
    final bytes = _bytes;
    if (bytes == null) {
      _load();
      return;
    }
    showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: EdgeInsets.all(12.w),
        child: InteractiveViewer(
          child: Image.memory(bytes, fit: BoxFit.contain),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _bytes == null) {
      return SizedBox(
        width: 120.w,
        height: 80.h,
        child: const Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    if (_bytes == null) {
      return GestureDetector(
        onTap: _load,
        child: SizedBox(
          width: 140.w,
          height: 90.h,
          child: Center(
            child: Text(
              _err == null || _err!.isEmpty ? '图片加载失败，点重试' : '图片加载失败，点重试',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.sp, color: AppColors.textSecondary),
            ),
          ),
        ),
      );
    }
    return GestureDetector(
      onTap: _openPreview,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8.r),
        child: Image.memory(
          _bytes!,
          width: 180.w,
          height: 140.h,
          fit: BoxFit.cover,
        ),
      ),
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
