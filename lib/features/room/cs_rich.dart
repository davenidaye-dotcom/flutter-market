import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';

import '../../config/env/env_config.dart';
import '../../config/theme/app_colors.dart';
import '../../core/network/session_store.dart';
import '../../shared/format/display_number.dart';

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

Future<void> showCsAttachSheet({
  required BuildContext context,
  required Future<void> Function(XFile file, String msgType) onPicked,
}) async {
  final picker = ImagePicker();
  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.white,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(12.r)),
    ),
    builder: (ctx) {
      return SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 16.h),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_outlined),
                title: const Text('相册图片'),
                onTap: () async {
                  Navigator.pop(ctx);
                  final file = await picker.pickImage(
                    source: ImageSource.gallery,
                    imageQuality: 85,
                    maxWidth: 1920,
                  );
                  if (file != null) await onPicked(file, 'IMAGE');
                },
              ),
              ListTile(
                leading: const Icon(Icons.videocam_outlined),
                title: const Text('相册视频（录屏文件）'),
                onTap: () async {
                  Navigator.pop(ctx);
                  final file = await picker.pickVideo(
                    source: ImageSource.gallery,
                    maxDuration: const Duration(seconds: 60),
                  );
                  if (file != null) await onPicked(file, 'VIDEO');
                },
              ),
            ],
          ),
        ),
      );
    },
  );
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
    final radius = BorderRadius.only(
      topLeft: Radius.circular(14.r),
      topRight: Radius.circular(14.r),
      bottomLeft: Radius.circular(mine ? 14.r : 4.r),
      bottomRight: Radius.circular(mine ? 4.r : 14.r),
    );
    final bg = mine ? AppColors.navBlue : AppColors.sidebarInactive;
    final fg = mine ? Colors.white : AppColors.textPrimary;

    final Widget body = switch (type) {
      'IMAGE' => _ImageBody(
          mediaId: mediaId,
          ownerSide: ownerSide,
          fallback: content,
          fg: fg,
        ),
      'VIDEO' => _VideoBody(
          mediaId: mediaId,
          ownerSide: ownerSide,
          fallback: content,
          fg: fg,
        ),
      'SHARE' => InkWell(
          onTap: onOpenShare,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '业务分享',
                style: TextStyle(
                    fontSize: 11.sp, color: fg.withValues(alpha: 0.8)),
              ),
              SizedBox(height: 4.h),
              Text(
                content.isEmpty ? '[分享]' : content,
                style: TextStyle(fontSize: 14.sp, height: 1.4, color: fg),
              ),
              SizedBox(height: 4.h),
              Text(
                '点击查看详情',
                style: TextStyle(
                    fontSize: 11.sp, color: fg.withValues(alpha: 0.75)),
              ),
            ],
          ),
        ),
      _ => Text(
          content,
          style: TextStyle(fontSize: 14.sp, height: 1.45, color: fg),
        ),
    };

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: 0.72.sw),
        margin: EdgeInsets.only(bottom: 12.h),
        padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
        decoration: BoxDecoration(color: bg, borderRadius: radius),
        child: body,
      ),
    );
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
      return Text(fallback.isEmpty ? '[图片]' : fallback,
          style: TextStyle(fontSize: 14.sp, color: fg));
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
                  child: Text('图片加载失败',
                      style: TextStyle(color: Colors.white, fontSize: 14.sp)),
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
    required this.fg,
  });

  final String mediaId;
  final bool ownerSide;
  final String fallback;
  final Color fg;

  @override
  Widget build(BuildContext context) {
    if (mediaId.isEmpty) {
      return Text(fallback.isEmpty ? '[视频]' : fallback,
          style: TextStyle(fontSize: 14.sp, color: fg));
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
      child: SizedBox(
        width: 180.w,
        height: 100.h,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              decoration: BoxDecoration(
                color: Colors.black26,
                borderRadius: BorderRadius.circular(8.r),
              ),
            ),
            Icon(Icons.play_circle_fill, size: 42.sp, color: fg),
            Positioned(
              left: 8.w,
              bottom: 8.h,
              child: Text(
                fallback.isEmpty ? '视频' : fallback,
                style: TextStyle(fontSize: 11.sp, color: fg),
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

Future<void> showCsRefSheet(
  BuildContext context,
  Map<String, dynamic> ref,
) async {
  final title = ref['title']?.toString() ?? '详情';
  final summary = ref['summary']?.toString() ?? '';
  final entries = <(String, String)>[];
  void add(String k, dynamic v) {
    if (v == null) return;
    final s = v is num ? displayNumber(v) : '$v'.trim();
    if (s.isEmpty) return;
    entries.add((k, s));
  }

  final type = (ref['refType'] ?? '').toString().toUpperCase();
  switch (type) {
    case 'BET_ORDER':
      add('单号', ref['orderId']);
      add('彩种', ref['gameType']);
      add('期号', ref['issueNo']);
      add('金额', ref['totalAmount']);
      add('状态', ref['status']);
      add('内容', ref['content']);
    case 'SCORE_APP':
      add('申请号', ref['applicationId']);
      add('类型', ref['applyType']);
      add('金额', ref['amount']);
      add('状态', ref['status']);
      add('备注', ref['remark']);
    case 'WELFARE_LEDGER':
    case 'POINT_LEDGER':
      add('账变号', ref['ledgerId']);
      add('类型', ref['changeType']);
      add('金额', ref['amount']);
      add('余额', ref['balanceAfter']);
      add('期号', ref['issueNo']);
      add('备注', ref['remark']);
    case 'REBATE_PAYOUT':
      add('发放号', ref['payoutId']);
      add('金额', ref['amount']);
      add('类型', ref['kind']);
      add('来源', ref['source']);
      add('备注', ref['remark']);
    default:
      if (summary.isNotEmpty) add('摘要', summary);
  }

  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.white,
    isScrollControlled: true,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(12.r)),
    ),
    builder: (ctx) {
      return Padding(
        padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 24.h),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: TextStyle(
                    fontSize: 16.sp, fontWeight: FontWeight.w700)),
            if (summary.isNotEmpty) ...[
              SizedBox(height: 6.h),
              Text(summary,
                  style: TextStyle(
                      fontSize: 13.sp, color: AppColors.textSecondary)),
            ],
            SizedBox(height: 12.h),
            for (final e in entries) ...[
              Padding(
                padding: EdgeInsets.only(bottom: 8.h),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 72.w,
                      child: Text(e.$1,
                          style: TextStyle(
                              fontSize: 12.sp,
                              color: AppColors.textSecondary)),
                    ),
                    Expanded(
                      child: Text(e.$2,
                          style: TextStyle(fontSize: 13.sp)),
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
