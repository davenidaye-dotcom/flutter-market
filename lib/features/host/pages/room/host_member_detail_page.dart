import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../../config/theme/app_colors.dart';
import '../../../../data/repositories/providers.dart';
import '../../../../shared/widgets/emulator_safe_text_field.dart';
import '../../../../shared/widgets/page_app_bar.dart';
import '../../data/host_mock.dart';
import '../../widgets/host_ui.dart';

/// Member detail — load from members API; status/rebate via PUT
class HostMemberDetailPage extends ConsumerStatefulWidget {
  const HostMemberDetailPage({super.key, required this.roomId, required this.memberId});
  final String roomId;
  final String memberId;

  @override
  ConsumerState<HostMemberDetailPage> createState() => _HostMemberDetailPageState();
}

class _HostMemberDetailPageState extends ConsumerState<HostMemberDetailPage> {
  HostMember? _member;
  final _remark = TextEditingController();
  final _rebateCtrl = TextEditingController();
  final _rebateFocus = FocusNode();
  final _remarkFocus = FocusNode();
  bool _loading = true;
  bool _statusBusy = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  @override
  void dispose() {
    _remark.dispose();
    _rebateCtrl.dispose();
    _rebateFocus.dispose();
    _remarkFocus.dispose();
    super.dispose();
  }

  void _dismissKeyboard() {
    _rebateFocus.unfocus();
    _remarkFocus.unfocus();
    FocusManager.instance.primaryFocus?.unfocus();
    SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
  }

  HostMember? _findMember(List<Map<String, dynamic>> rows) {
    for (final r in rows) {
      final m = hostMemberFromMap(r);
      if (m.id == widget.memberId || m.userId == widget.memberId) {
        final rebate = r['rebateRatio'] ?? r['rebate'];
        if (rebate != null) _rebateCtrl.text = '$rebate';
        return m;
      }
    }
    return null;
  }

  Future<void> _load({bool silent = false}) async {
    // 状态变更后勿整页换成转圈：会拆掉仍挂着 IME 的输入框，模拟器易卡死
    if (!silent && mounted) {
      setState(() => _loading = true);
    }
    try {
      final data = await ref.read(ownerRepositoryProvider).getMembers(pageSize: 100);
      var found = _findMember(hostRowsOf(data));
      if (found == null) {
        final byKw = await ref.read(ownerRepositoryProvider).getMembers(
              keyword: widget.memberId,
              pageSize: 50,
            );
        found = _findMember(hostRowsOf(byKw));
      }
      found ??= HostMember(widget.memberId, '未知', '-', widget.memberId, '-', 0);
      if (!mounted) return;
      setState(() {
        _member = found;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _member ??= HostMember(widget.memberId, '未知', '-', widget.memberId, '-', 0);
        _loading = false;
      });
      if (!silent) AppToast.error(e.toString());
    }
  }

  Future<void> _setStatus(String status, String tip) async {
    if (_statusBusy) return;
    _dismissKeyboard();
    final cur = (_member?.status ?? 'NORMAL').toUpperCase();
    if (cur == status.toUpperCase()) {
      AppToast.info('当前已是$tip');
      return;
    }
    final ok = await hostConfirm(context, title: tip, message: tip, danger: true);
    if (!ok || !mounted) return;
    _dismissKeyboard();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    if (!mounted) return;

    _statusBusy = true;
    try {
      await ref.read(ownerRepositoryProvider).updateMemberStatus(widget.memberId, status);
      if (!mounted) return;
      final m = _member;
      if (m != null) {
        setState(() {
          _member = HostMember(
            m.id,
            m.nickname,
            m.username,
            m.userId,
            m.roleLabel,
            m.points,
            online: m.online,
            isMood: m.isMood,
            isTrial: m.isTrial,
            disabled: status.toUpperCase() != 'NORMAL',
            isAgent: m.isAgent,
            status: status.toUpperCase(),
          );
        });
      }
      AppToast.success('已提交');
      await _load(silent: true);
    } catch (e) {
      AppToast.error(e.toString());
    } finally {
      _statusBusy = false;
    }
  }

  Future<void> _saveRebate() async {
    _dismissKeyboard();
    final v = num.tryParse(_rebateCtrl.text.trim());
    if (v == null) {
      AppToast.info('请输入反水比例');
      return;
    }
    try {
      await ref.read(ownerRepositoryProvider).updateMemberRebate(widget.memberId, v);
      AppToast.success('已保存');
    } catch (e) {
      AppToast.error(e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final member = _member;
    final status = (member?.status ?? 'NORMAL').toUpperCase();
    final statusColor = switch (status) {
      'FROZEN' || 'DISABLED' || 'BAN_ENTER' => AppColors.danger,
      _ => AppColors.navBlue,
    };
    return HostSubPageScaffold(
      title: '成员详情',
      body: _loading || member == null
          ? const Center(child: CircularProgressIndicator())
          : GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _dismissKeyboard,
              child: ListView(
                padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 24.h),
                children: [
                  HostWhiteCard(
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 28.r,
                          backgroundColor: const Color(0xFFBDE0FE),
                          child: Text(
                            member.nickname.isNotEmpty ? member.nickname.characters.first : '?',
                            style: TextStyle(fontSize: 18.sp, color: AppColors.navBlue),
                          ),
                        ),
                        SizedBox(width: 12.w),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(member.nickname, style: TextStyle(fontSize: 17.sp, fontWeight: FontWeight.w600)),
                              Text(
                                '${member.username} · ${member.userId}',
                                style: TextStyle(fontSize: 12.sp, color: AppColors.textSecondary),
                              ),
                              Text(member.roleLabel, style: TextStyle(fontSize: 12.sp, color: AppColors.navBlue)),
                              Text(
                                '状态：${member.statusLabel}',
                                style: TextStyle(fontSize: 12.sp, color: statusColor, fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ),
                        Text('${member.points}', style: TextStyle(fontSize: 20.sp, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                  SizedBox(height: 10.h),
                  HostWhiteCard(
                    child: EmulatorSafeTextField(
                      controller: _remark,
                      focusNode: _remarkFocus,
                      decoration: InputDecoration(
                        border: InputBorder.none,
                        hintText: '房间备注（仅本房间可见）',
                        hintStyle: TextStyle(fontSize: 13.sp, color: AppColors.textHint),
                      ),
                    ),
                  ),
                  SizedBox(height: 10.h),
                  HostWhiteCard(
                    child: Row(
                      children: [
                        Text('特殊反水%', style: TextStyle(fontSize: 14.sp)),
                        SizedBox(width: 12.w),
                        Expanded(
                          child: EmulatorSafeTextField(
                            controller: _rebateCtrl,
                            focusNode: _rebateFocus,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
                          ),
                        ),
                        TextButton(onPressed: _saveRebate, child: const Text('保存')),
                      ],
                    ),
                  ),
                  SizedBox(height: 10.h),
                  _statusAction(
                    code: 'DISABLED',
                    activeLabel: '已禁用',
                    idleLabel: '禁用',
                    tip: '禁用成员',
                    current: status,
                  ),
                  _statusAction(
                    code: 'FROZEN',
                    activeLabel: '已冻结',
                    idleLabel: '冻结',
                    tip: '冻结成员',
                    current: status,
                  ),
                  _statusAction(
                    code: 'NORMAL',
                    activeLabel: '当前正常',
                    idleLabel: '恢复正常',
                    tip: '恢复正常',
                    current: status,
                    danger: false,
                  ),
                  _statusAction(
                    code: 'BAN_ENTER',
                    activeLabel: '已禁止进房',
                    idleLabel: '禁止进房',
                    tip: '加入黑名单',
                    current: status,
                  ),
                ],
              ),
            ),
    );
  }

  Widget _statusAction({
    required String code,
    required String activeLabel,
    required String idleLabel,
    required String tip,
    required String current,
    bool danger = true,
  }) {
    final active = current == code;
    return _action(
      active ? activeLabel : idleLabel,
      active || _statusBusy ? null : () => _setStatus(code, tip),
      danger: danger && !active,
      muted: active,
    );
  }

  Widget _action(String label, VoidCallback? onTap, {bool danger = false, bool muted = false}) {
    final color = muted
        ? AppColors.textHint
        : (danger ? AppColors.danger : AppColors.textPrimary);
    return Padding(
      padding: EdgeInsets.only(bottom: 8.h),
      child: HostWhiteCard(
        onTap: onTap,
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 15.sp,
                  color: color,
                  fontWeight: muted ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
            if (!muted) Icon(Icons.chevron_right, color: AppColors.textHint, size: 18.sp),
          ],
        ),
      ),
    );
  }
}
