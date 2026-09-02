import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../config/theme/app_colors.dart';
import '../../../data/repositories/providers.dart';
import '../../../shared/widgets/emulator_safe_text_field.dart';
import '../../../shared/widgets/gradient_background.dart';
import '../../../shared/widgets/page_app_bar.dart';
import 'room_shell_page.dart';

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

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _scroll.dispose();
    _messagesNotifier.dispose();
    _loadingNotifier.dispose();
    _sendingNotifier.dispose();
    super.dispose();
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
      _messagesNotifier.value = list;
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
      'direction': 'IN',
      'content': text,
      'createdAt': DateTime.now().toIso8601String(),
    };
    _messagesNotifier.value = [..._messagesNotifier.value, optimistic];
    _scrollToEnd();
    try {
      await ref.read(memberRepositoryProvider).sendCsMessage(text);
      if (mounted) await _load(silent: true);
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
                      return const Center(child: CircularProgressIndicator());
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
                          padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
                          itemCount: messages.length,
                          itemBuilder: (_, i) {
                            final m = messages[i];
                            final mine = (m['direction']?.toString().toUpperCase() ?? '') == 'IN';
                            final content = m['content']?.toString() ?? '';
                            final time = m['createdAt']?.toString() ?? '';
                            return RepaintBoundary(
                              child: Align(
                                alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                                child: Container(
                                  margin: EdgeInsets.only(bottom: 8.h),
                                  padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
                                  constraints: BoxConstraints(maxWidth: 0.72.sw),
                                  decoration: BoxDecoration(
                                    color: mine ? AppColors.navBlue : Colors.white,
                                    borderRadius: BorderRadius.circular(12.r),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        content,
                                        style: TextStyle(
                                          fontSize: 14.sp,
                                          color: mine ? Colors.white : AppColors.textPrimary,
                                        ),
                                      ),
                                      if (time.isNotEmpty) ...[
                                        SizedBox(height: 4.h),
                                        Text(
                                          time.length >= 16 ? time.substring(11, 16) : time,
                                          style: TextStyle(
                                            fontSize: 10.sp,
                                            color: mine ? Colors.white70 : AppColors.textHint,
                                          ),
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
              Material(
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
                              child: EmulatorSafeTextField(
                                controller: _ctrl,
                                enabled: !sending,
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
            ],
          ),
        ),
      ),
    );
  }
}
