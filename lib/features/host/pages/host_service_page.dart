import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:image_picker/image_picker.dart';
import '../../../config/theme/app_colors.dart';
import '../../../data/repositories/providers.dart';
import '../../lottery/providers/lottery_live_provider.dart';
import '../../room/cs_rich.dart';
import '../../room/cs_unread.dart';
import '../../../shared/widgets/emulator_safe_text_field.dart';
import '../../../shared/widgets/gradient_background.dart';
import '../../../shared/widgets/keyboard_input_lift.dart';
import '../../../shared/widgets/app_back.dart';
import '../../../shared/widgets/page_app_bar.dart';
import '../widgets/host_ui.dart';

class _CsSession {
  _CsSession({
    required this.accountId,
    required this.name,
    required this.avatarText,
    required this.last,
    required this.time,
    required this.unread,
  });

  final String accountId;
  final String name;
  final String avatarText;
  final String last;
  final String time;
  final int unread;
}

String _csDisplayName(Map<String, dynamic> row, String fallback) {
  final remark = row['remark']?.toString().trim() ?? '';
  if (remark.isNotEmpty) return remark;
  final nick = row['nickname']?.toString().trim() ?? '';
  if (!row.containsKey('remark')) {
    final passed = fallback.trim();
    if (passed.isNotEmpty) return passed;
  }
  if (nick.isNotEmpty) return nick;
  final user = row['username']?.toString().trim() ?? '';
  if (user.isNotEmpty) return user;
  return fallback.trim();
}

String _csAvatarText(Map<String, dynamic> row, String displayName) {
  final nick = row['nickname']?.toString().trim() ?? '';
  if (nick.isNotEmpty) return nick;
  return displayName;
}

/// Owner CS sessions — GET /owner/cs/sessions
class HostServicePage extends ConsumerStatefulWidget {
  const HostServicePage({
    super.key,
    required this.roomId,
    this.openAccountId,
    this.openName,
  });

  final String roomId;
  final String? openAccountId;
  final String? openName;

  @override
  ConsumerState<HostServicePage> createState() => _HostServicePageState();
}

class _HostServicePageState extends ConsumerState<HostServicePage> {
  _CsSession? _open;
  List<_CsSession> _sessions = [];
  bool _loading = true;
  StreamSubscription<CsChatPush>? _csSub;
  late final AppBackLayer _sessionBack = AppBackLayer(
    _closeOpenSession,
    navigatorOf: () => mounted ? Navigator.of(context) : null,
  );

  @override
  void initState() {
    super.initState();
    _csSub = ref
        .read(roomLotteryLiveProvider(widget.roomId).notifier)
        .csPushes
        .listen(_onCsPush);
    Future.microtask(_bootstrap);
  }

  bool _fromMemberChat() => (widget.openAccountId ?? '').trim().isNotEmpty;

  /// 底栏里的会话不是路由。系统返回先退回会话列表，再退 Tab。
  bool _closeOpenSession() {
    if (!mounted || _open == null || _fromMemberChat()) return false;
    if (!appBackLayerActive(context)) return false;
    setState(() => _open = null);
    unregisterAppBackLayer(_sessionBack);
    _loadSessions();
    return true;
  }

  void _syncSessionBack() {
    if (_open != null && !_fromMemberChat()) {
      registerAppBackLayer(_sessionBack);
    } else {
      unregisterAppBackLayer(_sessionBack);
    }
  }

  @override
  void dispose() {
    unregisterAppBackLayer(_sessionBack);
    _csSub?.cancel();
    super.dispose();
  }

  void _onCsPush(CsChatPush push) {
    if (!mounted || _open != null) return;
    unawaited(_loadSessions(silent: true));
  }

  /// 底栏未读变多，说明有玩家来信。会话推送没到时也要把新会话拉出来。
  void _onUnreadChanged(int? prev, int next) {
    if (!mounted || _open != null || prev == null || next <= prev) return;
    unawaited(_loadSessions(silent: true));
  }

  Future<void> _bootstrap() async {
    final id = widget.openAccountId?.trim() ?? '';
    if (id.isNotEmpty) {
      try {
        final row = await ref.read(ownerRepositoryProvider).ensureCsSession(id);
        if (!mounted) return;
        final at = row['lastMessageAt']?.toString() ?? '';
        final name = _csDisplayName(row, widget.openName ?? id);
        setState(() {
          _open = _CsSession(
            accountId: '${row['accountId'] ?? id}',
            name: name,
            avatarText: _csAvatarText(row, name),
            last: row['lastMessage']?.toString() ?? '',
            time: at.length >= 16 ? at.substring(11, 16) : at,
            unread: int.tryParse('${row['unreadCount'] ?? 0}') ?? 0,
          );
          _loading = false;
        });
      } catch (e) {
        if (!mounted) return;
        setState(() => _loading = false);
        AppToast.error(e.toString());
      }
      return;
    }
    await _loadSessions();
  }

  Future<void> _clearSession(_CsSession s) async {
    final ok = await confirmCsClearHistory(context);
    if (!ok || !mounted) return;
    try {
      await ref.read(ownerRepositoryProvider).clearCsSessionMessages(s.accountId);
      setState(() {
        _sessions.removeWhere((e) => e.accountId == s.accountId);
        if (_open?.accountId == s.accountId) {
          _open = null;
        }
      });
      AppToast.info('已删除');
    } catch (e) {
      AppToast.error(e.toString());
    }
  }

  Future<void> _loadSessions({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    try {
      final data = await ref.read(ownerRepositoryProvider).getCsSessions();
      final rows = data['rows'];
      final list = rows is List
          ? rows.whereType<Map>().map((e) {
              final m = Map<String, dynamic>.from(e);
              final at = m['lastMessageAt']?.toString() ?? '';
              final time = at.length >= 16 ? at.substring(11, 16) : at;
              final name = _csDisplayName(m, '');
              return _CsSession(
                accountId: '${m['accountId'] ?? ''}',
                name: name,
                avatarText: _csAvatarText(m, name),
                last: m['lastMessage']?.toString() ?? '',
                time: time,
                unread: int.tryParse('${m['unreadCount'] ?? 0}') ?? 0,
              );
            }).where((s) => s.accountId.isNotEmpty).toList()
          : <_CsSession>[];
      if (!mounted) return;
      setState(() {
        _sessions = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      AppToast.error(e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    _syncSessionBack();
    ref.listen<int>(csUnreadCountProvider, _onUnreadChanged);
    if (_open != null) {
      return _ChatView(
        roomId: widget.roomId,
        session: _open!,
        onBack: () => appHandleBack(context),
      );
    }

    return AppPageScaffold(
      body: GradientBackground(
        child: SafeArea(
          child: Column(
            children: [
              PageAppBar(
                title: '在线客服',
                onBack: () => appHandleBack(context),
              ),
              Expanded(
                child: _loading
                    ? const AppPageLoading()
                    : _sessions.isEmpty
                        ? Center(
                            child: Text(
                              '暂无客服会话',
                              style: TextStyle(fontSize: 14.sp, color: AppColors.textHint),
                            ),
                          )
                        : ListView.separated(
                            padding: EdgeInsets.fromLTRB(16.w, 0, 16.w, 16.h),
                            itemCount: _sessions.length,
                            separatorBuilder: (_, _) => SizedBox(height: 8.h),
                            itemBuilder: (_, i) {
                              final s = _sessions[i];
                              return HostWhiteCard(
                                onTap: () => setState(() => _open = s),
                                onLongPress: () => _clearSession(s),
                                child: Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 22.r,
                                      backgroundColor: const Color(0xFFBDE0FE),
                                      child: Text(
                                        s.avatarText.isNotEmpty ? s.avatarText.characters.first : '?',
                                        style: const TextStyle(color: AppColors.navBlue),
                                      ),
                                    ),
                                    SizedBox(width: 12.w),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            s.name,
                                            style: TextStyle(
                                              fontSize: 15.sp,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          SizedBox(height: 4.h),
                                          Text(
                                            s.last,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 12.sp,
                                              color: AppColors.textSecondary,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      children: [
                                        Text(
                                          s.time,
                                          style: TextStyle(
                                            fontSize: 11.sp,
                                            color: AppColors.textHint,
                                          ),
                                        ),
                                        if (s.unread > 0) ...[
                                          SizedBox(height: 6.h),
                                          Container(
                                            padding: EdgeInsets.symmetric(
                                              horizontal: 6.w,
                                              vertical: 2.h,
                                            ),
                                            decoration: BoxDecoration(
                                              color: AppColors.danger,
                                              borderRadius: BorderRadius.circular(10.r),
                                            ),
                                            child: Text(
                                              '${s.unread}',
                                              style: TextStyle(
                                                fontSize: 10.sp,
                                                color: Colors.white,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChatView extends ConsumerStatefulWidget {
  const _ChatView({
    required this.roomId,
    required this.session,
    required this.onBack,
  });

  final String roomId;
  final _CsSession session;
  final VoidCallback onBack;

  @override
  ConsumerState<_ChatView> createState() => _ChatViewState();
}

class _ChatViewState extends ConsumerState<_ChatView> {
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();
  final _msgs = <Map<String, dynamic>>[];
  bool _loading = true;
  bool _attachOpen = false;
  StreamSubscription<CsChatPush>? _csSub;
  Timer? _poll;
  bool _pulling = false;
  late final AppBackLayer _attachBack = AppBackLayer(
    () {
      if (!mounted || !_attachOpen || !appBackLayerActive(context)) return false;
      setState(() => _attachOpen = false);
      unregisterAppBackLayer(_attachBack);
      return true;
    },
    navigatorOf: () => mounted ? Navigator.of(context) : null,
  );

  @override
  void initState() {
    super.initState();
    _csSub = ref
        .read(roomLotteryLiveProvider(widget.roomId).notifier)
        .csPushes
        .listen(_onCsPush);
    Future.microtask(_loadMessages);
    // 推送若排在开奖后面，停在会话里会晚一拍。接口和退回列表一样快，开着就自己拉。
    _poll = Timer.periodic(const Duration(seconds: 1), (_) {
      unawaited(_loadMessages(silent: true));
    });
  }

  void _syncAttachBack() {
    if (_attachOpen) {
      registerAppBackLayer(_attachBack);
    } else {
      unregisterAppBackLayer(_attachBack);
    }
  }

  @override
  void dispose() {
    unregisterAppBackLayer(_attachBack);
    _poll?.cancel();
    _csSub?.cancel();
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onCsPush(CsChatPush push) {
    if (!mounted) return;
    if (push.resync) {
      unawaited(_loadMessages(silent: true));
      return;
    }
    if (push.accountId.isNotEmpty && push.accountId != widget.session.accountId) {
      return;
    }
    _ingest(csPushRow(push));
    // 正在看这个会话：玩家新消息直接标已读，底栏改成剩余未读
    if (push.direction == 'IN') {
      unawaited(_loadMessages(silent: true));
    }
  }

  /// 人停在会话里时，未读变多就拉这条会话，不必退出再进。
  void _onUnreadChanged(int? prev, int next) {
    if (!mounted || prev == null || next <= prev) return;
    unawaited(_loadMessages(silent: true));
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  void _ingest(Map<String, dynamic> row) {
    final id = (row['id'] ?? '').toString();
    final content = row['content']?.toString() ?? '';
    final dir = (row['direction'] ?? '').toString().toUpperCase();
    _msgs.removeWhere((m) =>
        (m['id'] ?? '').toString().isEmpty &&
        (m['direction'] ?? '').toString().toUpperCase() == dir &&
        (m['content'] ?? '').toString() == content);
    final exists = id.isNotEmpty && _msgs.any((m) => (m['id'] ?? '').toString() == id);
    if (!exists) {
      _msgs.add(csMessageRow(row));
    }
    if (!mounted) return;
    setState(() {});
    _scrollToEnd();
  }

  Future<void> _loadMessages({bool silent = false}) async {
    if (_pulling) return;
    _pulling = true;
    if (!silent) setState(() => _loading = true);
    try {
      final list = await ref.read(ownerRepositoryProvider).getCsMessages(
            widget.session.accountId,
            limit: 50,
          );
      if (!mounted) return;
      final server = list.map(csMessageRow).toList();
      final local = [for (final m in _msgs) Map<String, dynamic>.from(m)];
      setState(() {
        _msgs
          ..clear()
          ..addAll(mergeCsHistory(server, local));
        _loading = false;
      });
      _scrollToEnd();
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      if (!silent) AppToast.error(e.toString());
    } finally {
      _pulling = false;
    }
  }

  Future<void> _send() async {
    final t = _ctrl.text.trim();
    if (t.isEmpty) return;
    final optimistic = csMessageRow({
      'id': '',
      'direction': 'OUT',
      'content': t,
      'msgType': 'TEXT',
      'createdAt': '',
    });
    setState(() {
      _msgs.add(optimistic);
      _ctrl.clear();
    });
    _scrollToEnd();
    try {
      final saved = await ref.read(ownerRepositoryProvider).sendCsReply(
            widget.session.accountId,
            t,
          );
      if (!mounted) return;
      _ingest(csMessageRow(saved));
    } catch (e) {
      if (!mounted) return;
      setState(() => _msgs.remove(optimistic));
      AppToast.error(e.toString());
    }
  }

  Future<void> _pickImage() async {
    final file = await pickCsGalleryImage();
    if (file == null || !mounted) return;
    setState(() => _attachOpen = false);
    await _uploadAndSend(file, 'IMAGE');
  }

  Future<void> _hideMessage(Map<String, dynamic> m) async {
    final id = (m['id'] ?? '').toString();
    if (id.isEmpty) return;
    final ok = await confirmCsSideDelete(context);
    if (!ok || !mounted) return;
    try {
      await ref.read(ownerRepositoryProvider).hideCsMessage(
            widget.session.accountId,
            id,
          );
      setState(() {
        _msgs.removeWhere((e) => (e['id'] ?? '').toString() == id);
      });
      AppToast.info('已删除');
    } catch (e) {
      AppToast.error(e.toString());
    }
  }

  Future<void> _uploadAndSend(XFile file, String msgType) async {
    try {
      final meta = await ref.read(ownerRepositoryProvider).uploadCsMedia(
            file.path,
            filename: file.name,
          );
      final mediaId = '${meta['mediaId'] ?? ''}';
      if (mediaId.isEmpty) throw Exception('上传失败');
      final saved = await ref.read(ownerRepositoryProvider).sendCsReply(
            widget.session.accountId,
            '',
            msgType: msgType,
            mediaId: mediaId,
          );
      if (!mounted) return;
      _ingest(csMessageRow(saved));
    } catch (e) {
      AppToast.error(e.toString());
    }
  }

  Future<void> _openShare(Map<String, dynamic> m) async {
    final refType = m['refType']?.toString() ?? '';
    final refId = m['refId']?.toString() ?? '';
    if (refType.isEmpty || refId.isEmpty) return;
    try {
      final detail = await ref.read(ownerRepositoryProvider).getCsRef(
            widget.session.accountId,
            refType,
            refId,
          );
      if (!mounted) return;
      await showCsRefSheet(context, detail);
    } catch (e) {
      AppToast.error(e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    _syncAttachBack();
    ref.listen<int>(csUnreadCountProvider, _onUnreadChanged);
    return AppPageScaffold(
      body: GradientBackground(
        child: SafeArea(
          child: Column(
            children: [
              PageAppBar(title: widget.session.name, onBack: widget.onBack),
              Expanded(
                child: _loading
                    ? const AppPageLoading()
                    : ListView.builder(
                        controller: _scroll,
                        padding: EdgeInsets.all(16.w),
                        itemCount: _msgs.length,
                        itemBuilder: (_, i) {
                          final m = _msgs[i];
                          final mine =
                              (m['direction'] ?? '').toString().toUpperCase() ==
                                  'OUT';
                          return CsMessageBubble(
                            message: m,
                            mine: mine,
                            ownerSide: true,
                            onOpenShare: () => _openShare(m),
                            onLongPress: () => _hideMessage(m),
                          );
                        },
                      ),
              ),
              KeyboardInputLift(
                child: ColoredBox(
                  color: Colors.white,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: EdgeInsets.fromLTRB(8.w, 8.h, 12.w, 8.h),
                        child: Row(
                          children: [
                            IconButton(
                              onPressed: () => setState(
                                () => _attachOpen = !_attachOpen,
                              ),
                              icon: Icon(
                                _attachOpen
                                    ? Icons.close
                                    : Icons.add_circle_outline,
                                color: AppColors.navBlue,
                                size: 26.sp,
                              ),
                            ),
                            Expanded(
                              child: EmulatorSafeTextField(
                                controller: _ctrl,
                                keyboardType: TextInputType.text,
                                enableSuggestions: true,
                                autocorrect: true,
                                textInputAction: TextInputAction.send,
                                onSubmitted: (_) => _send(),
                                decoration: InputDecoration(
                                  hintText: '输入回复（用户端显示为房间客服）',
                                  hintStyle: TextStyle(
                                      fontSize: 13.sp,
                                      color: AppColors.textHint),
                                  border: InputBorder.none,
                                ),
                              ),
                            ),
                            TextButton(
                                onPressed: _send, child: const Text('发送')),
                          ],
                        ),
                      ),
                      if (_attachOpen)
                        CsAttachPanel(
                          onPickImage: _pickImage,
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
