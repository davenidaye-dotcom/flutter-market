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
import 'room_shell_page.dart';
import '../../../shared/widgets/app_page_loading.dart';

/// Online CS chat for member room.
class CustomerServicePage extends ConsumerStatefulWidget {
  const CustomerServicePage({super.key, required this.roomId});

  final String roomId;

  @override
  ConsumerState<CustomerServicePage> createState() => _CustomerServicePageState();
}

class _CustomerServicePageState extends ConsumerState<CustomerServicePage> {
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();
  final _messagesNotifier = ValueNotifier<List<Map<String, dynamic>>>([]);
  final _loadingNotifier = ValueNotifier(true);
  final _sendingNotifier = ValueNotifier(false);
  StreamSubscription<CsChatPush>? _csSub;

  @override
  void initState() {
    super.initState();
    _csSub = ref
        .read(roomLotteryLiveProvider(widget.roomId).notifier)
        .csPushes
        .listen(_onCsPush);
    Future.microtask(_load);
  }

  @override
  void dispose() {
    _csSub?.cancel();
    _ctrl.dispose();
    _scroll.dispose();
    _messagesNotifier.dispose();
    _loadingNotifier.dispose();
    _sendingNotifier.dispose();
    super.dispose();
  }

  void _onCsPush(CsChatPush push) {
    if (!mounted) return;
    if (push.resync) {
      unawaited(_load(silent: true));
      return;
    }
    _ingest({
      'id': push.messageId,
      'direction': push.direction,
      'content': push.content,
      'createdAt': push.createdAt,
    });
  }

  void _ingest(Map<String, dynamic> row) {
    final id = (row['id'] ?? '').toString();
    final content = row['content']?.toString() ?? '';
    final dir = (row['direction'] ?? '').toString().toUpperCase();
    final list = [
      for (final m in _messagesNotifier.value) Map<String, dynamic>.from(m),
    ];
    list.removeWhere((m) =>
        (m['id'] ?? '').toString().isEmpty &&
        (m['direction'] ?? '').toString().toUpperCase() == dir &&
        (m['content'] ?? '').toString() == content);
    if (id.isEmpty || list.every((m) => (m['id'] ?? '').toString() != id)) {
      list.add({
        'id': id,
        'direction': dir,
        'content': content,
        'createdAt': row['createdAt']?.toString() ?? '',
      });
    }
    _messagesNotifier.value = list;
    _scrollToEnd();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) _loadingNotifier.value = true;
    try {
      final list = await ref.read(memberRepositoryProvider).getCsMessages();
      if (!mounted) return;
      _messagesNotifier.value = mergeCsHistory(list, _messagesNotifier.value);
      _loadingNotifier.value = false;
      _scrollToEnd();
    } catch (e) {
      if (!mounted) return;
      _loadingNotifier.value = false;
      AppToast.error(e.toString());
    }
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty || _sendingNotifier.value) return;
    _sendingNotifier.value = true;
    _ctrl.clear();
    final optimistic = {
      'id': '',
      'direction': 'IN',
      'content': text,
      'createdAt': DateTime.now().toIso8601String(),
    };
    _messagesNotifier.value = [..._messagesNotifier.value, optimistic];
    _scrollToEnd();
    try {
      final saved = await ref.read(memberRepositoryProvider).sendCsMessage(text);
      if (!mounted) return;
      _ingest({
        'id': '${saved['id'] ?? ''}',
        'direction': '${saved['direction'] ?? 'IN'}',
        'content': '${saved['content'] ?? text}',
        'createdAt': '${saved['createdAt'] ?? optimistic['createdAt']}',
      });
    } catch (e) {
      _messagesNotifier.value = _messagesNotifier.value.where((m) => m != optimistic).toList();
      AppToast.error(e.toString());
    } finally {
      _sendingNotifier.value = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppPageScaffold(
      body: GradientBackground(
        child: SafeArea(
          child: Column(
            children: [
              PageAppBar(
                title: '在线客服',
                onBack: () => appRoomBack(context, widget.roomId),
              ),
              Expanded(
                child: ValueListenableBuilder<bool>(
                  valueListenable: _loadingNotifier,
                  builder: (_, loading, __) {
                    if (loading) {
                      return const AppPageLoading();
                    }
                    return ValueListenableBuilder<List<Map<String, dynamic>>>(
                      valueListenable: _messagesNotifier,
                      builder: (_, messages, __) {
                        if (messages.isEmpty) {
                          return Center(
                            child: Text(
                              '暂无消息，请输入咨询',
                              style: TextStyle(fontSize: 13.sp, color: AppColors.textSecondary),
                            ),
                          );
                        }
                        return ListView.builder(
                          controller: _scroll,
                          padding: EdgeInsets.fromLTRB(12.w, 12.h, 12.w, 8.h),
                          itemCount: messages.length,
                          itemBuilder: (_, i) {
                            final m = messages[i];
                            final mine = (m['direction']?.toString().toUpperCase() ?? '') == 'IN';
                            final content = m['content']?.toString() ?? '';
                            final rawTime = m['createdAt']?.toString() ?? '';
                            final time = rawTime.length >= 16 ? rawTime.substring(11, 16) : rawTime;
                            final radius = BorderRadius.only(
                              topLeft: Radius.circular(14.r),
                              topRight: Radius.circular(14.r),
                              bottomLeft: Radius.circular(mine ? 14.r : 4.r),
                              bottomRight: Radius.circular(mine ? 4.r : 14.r),
                            );
                            return RepaintBoundary(
                              child: Align(
                                alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                                child: Container(
                                  constraints: BoxConstraints(maxWidth: 0.72.sw),
                                  margin: EdgeInsets.only(bottom: 12.h),
                                  child: Column(
                                    crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        mine ? '我' : '客服',
                                        style: TextStyle(fontSize: 12.sp, color: AppColors.textSecondary),
                                      ),
                                      SizedBox(height: 4.h),
                                      Container(
                                        padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
                                        decoration: BoxDecoration(
                                          color: mine ? AppColors.navBlue : AppColors.sidebarInactive,
                                          borderRadius: radius,
                                        ),
                                        child: Text(
                                          content,
                                          style: TextStyle(
                                            fontSize: 14.sp,
                                            height: 1.45,
                                            color: mine ? Colors.white : AppColors.textPrimary,
                                          ),
                                        ),
                                      ),
                                      if (time.isNotEmpty) ...[
                                        SizedBox(height: 4.h),
                                        Text(
                                          time,
                                          style: TextStyle(fontSize: 10.sp, color: AppColors.textHint),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        );
                      },
                    );
                  },
                ),
              ),
              KeyboardInputLift(
                child: Material(
                color: const Color(0xFFEEEEEE),
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(12.w, 8.h, 8.w, 10.h),
                    child: ValueListenableBuilder<bool>(
                      valueListenable: _sendingNotifier,
                      builder: (_, sending, __) {
                        return Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _ctrl,
                                enabled: !sending,
                                keyboardType: TextInputType.text,
                                enableSuggestions: true,
                                autocorrect: true,
                                textInputAction: TextInputAction.send,
                                onSubmitted: (_) => _send(),
                                decoration: InputDecoration(
                                  hintText: '请输入消息',
                                  filled: true,
                                  fillColor: Colors.white,
                                  contentPadding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 10.h),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(20.r),
                                    borderSide: BorderSide.none,
                                  ),
                                ),
                              ),
                            ),
                            IconButton(
                              onPressed: sending ? null : _send,
                              icon: Icon(Icons.send, color: AppColors.navBlue, size: 26.sp),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
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
