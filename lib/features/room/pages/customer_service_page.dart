import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:image_picker/image_picker.dart';

import '../../../config/theme/app_colors.dart';
import '../../../data/repositories/providers.dart';
import '../../lottery/providers/lottery_live_provider.dart';
import '../../../shared/widgets/emulator_safe_text_field.dart';
import '../../../shared/widgets/gradient_background.dart';
import '../../../shared/widgets/keyboard_input_lift.dart';
import '../../../shared/widgets/page_app_bar.dart';
import 'room_shell_page.dart';
import '../../../shared/widgets/app_page_loading.dart';
import '../cs_rich.dart';

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
    _ingest(csPushRow(push));
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
      list.add(csMessageRow(row));
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
      final server = list.map(csMessageRow).toList();
      _messagesNotifier.value = mergeCsHistory(server, _messagesNotifier.value);
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
    final optimistic = csMessageRow({
      'id': '',
      'direction': 'IN',
      'content': text,
      'msgType': 'TEXT',
      'createdAt': DateTime.now().toIso8601String(),
    });
    _messagesNotifier.value = [..._messagesNotifier.value, optimistic];
    _scrollToEnd();
    try {
      final saved = await ref.read(memberRepositoryProvider).sendCsMessage(text);
      if (!mounted) return;
      _ingest(csMessageRow(saved));
    } catch (e) {
      _messagesNotifier.value =
          _messagesNotifier.value.where((m) => m != optimistic).toList();
      AppToast.error(e.toString());
    } finally {
      _sendingNotifier.value = false;
    }
  }

  Future<void> _pickAndSend() async {
    await showCsAttachSheet(
      context: context,
      onPicked: (file, msgType) => _uploadAndSend(file, msgType),
    );
  }

  Future<void> _uploadAndSend(XFile file, String msgType) async {
    if (_sendingNotifier.value) return;
    _sendingNotifier.value = true;
    try {
      final meta = await ref.read(memberRepositoryProvider).uploadCsMedia(
            file.path,
            filename: file.name,
          );
      final mediaId = '${meta['mediaId'] ?? ''}';
      if (mediaId.isEmpty) throw Exception('上传失败');
      final saved = await ref.read(memberRepositoryProvider).sendCsMessage(
            '',
            msgType: msgType,
            mediaId: mediaId,
          );
      if (!mounted) return;
      _ingest(csMessageRow(saved));
    } catch (e) {
      AppToast.error(e.toString());
    } finally {
      _sendingNotifier.value = false;
    }
  }

  Future<void> _openShare(Map<String, dynamic> m) async {
    final refType = m['refType']?.toString() ?? '';
    final refId = m['refId']?.toString() ?? '';
    if (refType.isEmpty || refId.isEmpty) return;
    try {
      final detail =
          await ref.read(memberRepositoryProvider).getCsRef(refType, refId);
      if (!mounted) return;
      await showCsRefSheet(context, detail);
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
                              style: TextStyle(
                                  fontSize: 13.sp,
                                  color: AppColors.textSecondary),
                            ),
                          );
                        }
                        return ListView.builder(
                          controller: _scroll,
                          padding: EdgeInsets.fromLTRB(12.w, 12.h, 12.w, 8.h),
                          itemCount: messages.length,
                          itemBuilder: (_, i) {
                            final m = messages[i];
                            final mine =
                                (m['direction']?.toString().toUpperCase() ??
                                        '') ==
                                    'IN';
                            final rawTime = m['createdAt']?.toString() ?? '';
                            final time = rawTime.length >= 16
                                ? rawTime.substring(11, 16)
                                : rawTime;
                            return Column(
                              crossAxisAlignment: mine
                                  ? CrossAxisAlignment.end
                                  : CrossAxisAlignment.start,
                              children: [
                                Text(
                                  mine ? '我' : '客服',
                                  style: TextStyle(
                                      fontSize: 12.sp,
                                      color: AppColors.textSecondary),
                                ),
                                SizedBox(height: 4.h),
                                CsMessageBubble(
                                  message: m,
                                  mine: mine,
                                  ownerSide: false,
                                  onOpenShare: () => _openShare(m),
                                ),
                                if (time.isNotEmpty)
                                  Text(
                                    time,
                                    style: TextStyle(
                                        fontSize: 10.sp,
                                        color: AppColors.textHint),
                                  ),
                              ],
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
                      padding: EdgeInsets.fromLTRB(8.w, 8.h, 8.w, 10.h),
                      child: ValueListenableBuilder<bool>(
                        valueListenable: _sendingNotifier,
                        builder: (_, sending, __) {
                          return Row(
                            children: [
                              IconButton(
                                onPressed: sending ? null : _pickAndSend,
                                icon: Icon(Icons.add_circle_outline,
                                    color: AppColors.navBlue, size: 26.sp),
                              ),
                              Expanded(
                                child: EmulatorSafeTextField(
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
                                    contentPadding: EdgeInsets.symmetric(
                                        horizontal: 14.w, vertical: 10.h),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(20.r),
                                      borderSide: BorderSide.none,
                                    ),
                                  ),
                                ),
                              ),
                              IconButton(
                                onPressed: sending ? null : _send,
                                icon: Icon(Icons.send,
                                    color: AppColors.navBlue, size: 26.sp),
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
