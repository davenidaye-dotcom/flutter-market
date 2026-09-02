import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../config/theme/app_colors.dart';
import '../../../data/repositories/providers.dart';
import '../../../shared/widgets/emulator_safe_text_field.dart';
import '../../../shared/widgets/gradient_background.dart';
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
  const HostServicePage({super.key, required this.roomId});

  final String roomId;

  @override
  ConsumerState<HostServicePage> createState() => _HostServicePageState();
}

class _HostServicePageState extends ConsumerState<HostServicePage> {
  _CsSession? _open;
  List<_CsSession> _sessions = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    Future.microtask(_loadSessions);
  }

  Future<void> _loadSessions() async {
    setState(() => _loading = true);
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
      return _ChatView(
        session: _open!,
        onBack: () {
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
                onBack: () => goHostLottery(context, widget.roomId),
              ),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
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
  const _ChatView({required this.session, required this.onBack});

  final _CsSession session;
  final VoidCallback onBack;

  @override
  ConsumerState<_ChatView> createState() => _ChatViewState();
}

class _ChatViewState extends ConsumerState<_ChatView> {
  final _ctrl = TextEditingController();
  final _msgs = <(bool, String)>[];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    Future.microtask(_loadMessages);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _loadMessages() async {
    setState(() => _loading = true);
    try {
      final list = await ref.read(ownerRepositoryProvider).getCsMessages(
            widget.session.accountId,
            limit: 50,
          );
      if (!mounted) return;
      setState(() {
        _msgs
          ..clear()
          ..addAll(
            list.map((m) {
              final out = (m['direction'] ?? '').toString().toUpperCase() == 'OUT';
              return (out, m['content']?.toString() ?? '');
            }),
          );
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      AppToast.error(e.toString());
    }
  }

  Future<void> _send() async {
    final t = _ctrl.text.trim();
    if (t.isEmpty) return;
    try {
      await ref.read(ownerRepositoryProvider).sendCsReply(
            widget.session.accountId,
            t,
          );
      if (!mounted) return;
      setState(() {
        _msgs.add((true, t));
        _ctrl.clear();
      });
    } catch (e) {
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
                    ? const Center(child: CircularProgressIndicator())
                    : ListView.builder(
                        padding: EdgeInsets.all(16.w),
                        itemCount: _msgs.length,
                        itemBuilder: (_, i) {
                          final (mine, text) = _msgs[i];
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
              Container(
                color: Colors.white,
                padding: EdgeInsets.fromLTRB(12.w, 8.h, 12.w, 8.h),
                child: Row(
                  children: [
                    Expanded(
                      child: EmulatorSafeTextField(
                        controller: _ctrl,
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
            ],
          ),
        ),
      ),
    );
  }
}
