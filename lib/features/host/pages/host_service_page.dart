import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../config/theme/app_colors.dart';
import '../../../data/repositories/providers.dart';
import '../../lottery/providers/lottery_live_provider.dart';
import '../../../shared/widgets/emulator_safe_text_field.dart';
import '../../../shared/widgets/gradient_background.dart';
import '../../../shared/widgets/keyboard_input_lift.dart';
import '../../../shared/widgets/page_app_bar.dart';
import '../widgets/host_ui.dart';
import 'host_shell_page.dart';

class _CsSession {
  _CsSession({
    required this.accountId,
    required this.name,
    required this.last,
    required this.time,
    required this.unread,
  });

  final String accountId;
  final String name;
  final String last;
  final String time;
  final int unread;
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

  @override
  void initState() {
    super.initState();
    _csSub = ref
        .read(roomLotteryLiveProvider(widget.roomId).notifier)
        .csPushes
        .listen(_onCsPush);
    Future.microtask(_bootstrap);
  }

  @override
  void dispose() {
    _csSub?.cancel();
    super.dispose();
  }

  void _onCsPush(CsChatPush push) {
    if (!mounted || _open != null) return;
    unawaited(_loadSessions(silent: true));
  }

  Future<void> _bootstrap() async {
    final id = widget.openAccountId?.trim() ?? '';
    if (id.isNotEmpty) {
      try {
        final row = await ref.read(ownerRepositoryProvider).ensureCsSession(id);
        if (!mounted) return;
        final at = row['lastMessageAt']?.toString() ?? '';
        setState(() {
          _open = _CsSession(
            accountId: '${row['accountId'] ?? id}',
            name: row['nickname']?.toString().trim().isNotEmpty == true
                ? row['nickname'].toString()
                : (widget.openName ?? id),
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
              return _CsSession(
                accountId: '${m['accountId'] ?? ''}',
                name: m['nickname']?.toString() ?? m['username']?.toString() ?? '',
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
    if (_open != null) {
      final fromMember = (widget.openAccountId ?? '').trim().isNotEmpty;
      return _ChatView(
        roomId: widget.roomId,
        session: _open!,
        onBack: () {
          // 会员详情发起私聊：返回直接关页回到详情；底栏进客服：退回会话列表
          if (fromMember) {
            final nav = Navigator.of(context);
            if (nav.canPop()) {
              nav.pop();
              return;
            }
            final closer = ShellCoverCloser.maybeOf(context);
            if (closer != null) {
              closer.close();
              return;
            }
          }
          setState(() => _open = null);
          _loadSessions();
        },
      );
    }

    return AppPageScaffold(
      body: GradientBackground(
        child: SafeArea(
          child: Column(
            children: [
              PageAppBar(
                title: '在线客服',
                onBack: () {
                  // 从会员详情「发起私聊」压栈/盖层进来：必须 pop/关盖层回到详情，不能 goHostLottery 把栈冲掉
                  final nav = Navigator.of(context);
                  if (nav.canPop()) {
                    nav.pop();
                    return;
                  }
                  final closer = ShellCoverCloser.maybeOf(context);
                  if (closer != null) {
                    closer.close();
                    return;
                  }
                  goHostLottery(context, widget.roomId);
                },
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
                                child: Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 22.r,
                                      backgroundColor: const Color(0xFFBDE0FE),
                                      child: Text(
                                        s.name.isNotEmpty ? s.name.characters.first : '?',
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
  StreamSubscription<CsChatPush>? _csSub;

  @override
  void initState() {
    super.initState();
    _csSub = ref
        .read(roomLotteryLiveProvider(widget.roomId).notifier)
        .csPushes
        .listen(_onCsPush);
    Future.microtask(_loadMessages);
  }

  @override
  void dispose() {
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
    _ingest({
      'id': push.messageId,
      'direction': push.direction,
      'content': push.content,
      'createdAt': push.createdAt,
    });
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
      _msgs.add({
        'id': id,
        'direction': dir,
        'content': content,
        'createdAt': row['createdAt']?.toString() ?? '',
      });
    }
    if (!mounted) return;
    setState(() {});
    _scrollToEnd();
  }

  Future<void> _loadMessages({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    try {
      final list = await ref.read(ownerRepositoryProvider).getCsMessages(
            widget.session.accountId,
            limit: 50,
          );
      if (!mounted) return;
      final server = list
          .map((m) => {
                'id': '${m['id'] ?? ''}',
                'direction': (m['direction'] ?? '').toString(),
                'content': m['content']?.toString() ?? '',
                'createdAt': m['createdAt']?.toString() ?? '',
              })
          .toList();
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
      AppToast.error(e.toString());
    }
  }

  Future<void> _send() async {
    final t = _ctrl.text.trim();
    if (t.isEmpty) return;
    final optimistic = {
      'id': '',
      'direction': 'OUT',
      'content': t,
      'createdAt': '',
    };
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
      _ingest({
        'id': '${saved['id'] ?? ''}',
        'direction': '${saved['direction'] ?? 'OUT'}',
        'content': '${saved['content'] ?? t}',
        'createdAt': '${saved['createdAt'] ?? ''}',
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _msgs.remove(optimistic));
      AppToast.error(e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
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
                          final mine = (m['direction'] ?? '').toString().toUpperCase() == 'OUT';
                          final text = m['content']?.toString() ?? '';
                          return Align(
                            alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                            child: Container(
                              margin: EdgeInsets.only(bottom: 8.h),
                              padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
                              decoration: BoxDecoration(
                                color: mine ? AppColors.navBlue : Colors.white,
                                borderRadius: BorderRadius.circular(8.r),
                              ),
                              child: Text(
                                text,
                                style: TextStyle(
                                  fontSize: 14.sp,
                                  color: mine ? Colors.white : AppColors.textPrimary,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
              KeyboardInputLift(
                child: Container(
                color: Colors.white,
                padding: EdgeInsets.fromLTRB(12.w, 8.h, 12.w, 8.h),
                child: Row(
                  children: [
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
                          hintStyle: TextStyle(fontSize: 13.sp, color: AppColors.textHint),
                          border: InputBorder.none,
                        ),
                      ),
                    ),
                    TextButton(onPressed: _send, child: const Text('发送')),
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
