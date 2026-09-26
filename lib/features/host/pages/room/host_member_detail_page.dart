import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../../config/theme/app_colors.dart';
import '../../../../data/repositories/providers.dart';
import '../../../../shared/widgets/page_app_bar.dart';
import '../../data/host_mock.dart';
import '../../widgets/host_ui.dart';
import '../host_service_page.dart';
import '../reports/host_member_report_page.dart';

/// 玩家信息 — 资料卡 + 分组菜单（对齐竞品截图）
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
    super.dispose();
  }

  void _dismissKeyboard() {
    FocusManager.instance.primaryFocus?.unfocus();
    SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent && mounted) setState(() => _loading = true);
    try {
      final raw = await ref.read(ownerRepositoryProvider).getMemberDetail(widget.memberId);
      final found = hostMemberFromMap(raw);
      final rebate = raw['rebateRatio'] ?? raw['rebate'];
      if (rebate != null) {
        _rebateCtrl.text = hostNumStr(rebate, fraction: 2);
      } else {
        _rebateCtrl.text = '0';
      }
      final remark = raw['remark']?.toString() ?? '';
      if (_remark.text != remark) _remark.text = remark;
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

  String _playerTitle(HostMember member) {
    final nick = member.nickname.trim();
    final remark = _remark.text.trim();
    if (remark.isEmpty) return nick;
    if (nick.isEmpty) return remark;
    return '$remark($nick)';
  }

  String _csOpenName(HostMember member) {
    final remark = _remark.text.trim();
    if (remark.isNotEmpty) return remark;
    return member.nickname;
  }

  Future<bool> _saveRemark() async {
    _dismissKeyboard();
    try {
      await ref.read(ownerRepositoryProvider).updateMemberRemark(widget.memberId, _remark.text.trim());
      AppToast.success('备注已保存');
      return true;
    } catch (e) {
      AppToast.error(e.toString());
      return false;
    }
  }

  Future<void> _editRemark() async {
    final text = await hostInputSheet(
      context,
      title: '设置备注',
      initial: _remark.text,
      hint: '房间备注（仅本房间可见）',
      systemKeyboard: true,
    );
    if (text == null || !mounted) return;
    final previous = _remark.text;
    setState(() => _remark.text = text);
    final ok = await _saveRemark();
    if (!ok && mounted) setState(() => _remark.text = previous);
  }

  Future<void> _copyId() async {
    final id = (_member?.id.isNotEmpty == true) ? _member!.id : widget.memberId;
    if (id.isEmpty) {
      AppToast.info('暂无ID');
      return;
    }
    await Clipboard.setData(ClipboardData(text: id));
    AppToast.success('已复制ID');
  }

  Future<void> _creditDialog(String direction) async {
    final title = direction == 'UP' ? '给会员上分' : '给会员下分';
    final amount = await hostInputSheet(
      context,
      title: title,
      hint: direction == 'UP' ? '请输入上分金额' : '请输入下分金额',
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      confirmText: '提交',
    );
    final v = num.tryParse(amount ?? '');
    if (v == null || v <= 0) return;
    try {
      await ref.read(ownerRepositoryProvider).memberCredit(
            accountId: widget.memberId,
            direction: direction,
            amount: v,
          );
      AppToast.success('已提交');
      await _load(silent: true);
    } catch (e) {
      AppToast.error(e.toString());
    }
  }

  Future<void> _setAgentDialog() async {
    final text = await hostInputSheet(
      context,
      title: '设置代理',
      hint: '请输入代理抽佣比例',
      suffixText: '%',
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
    );
    final v = num.tryParse(text ?? '');
    if (v == null) return;
    try {
      await ref.read(ownerRepositoryProvider).setMemberAgent(
            accountId: widget.memberId,
            commissionRatio: v,
          );
      AppToast.success('已设置');
      await _load(silent: true);
    } catch (e) {
      AppToast.error(e.toString());
    }
  }

  Future<void> _cancelAgent() async {
    final ok = await hostConfirm(
      context,
      title: '取消代理',
      message: '取消后抽佣比例清零，下线关系也会清空。确定取消？',
      danger: true,
    );
    if (!ok || !mounted) return;
    try {
      await ref.read(ownerRepositoryProvider).cancelMemberAgent(widget.memberId);
      AppToast.success('已取消代理');
      await _load(silent: true);
    } catch (e) {
      AppToast.error(e.toString());
    }
  }

  Future<void> _editRebate() async {
    final text = await hostInputSheet(
      context,
      title: '特殊回水',
      initial: _rebateCtrl.text,
      hint: '请输入回水比例',
      suffixText: '%',
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
    );
    if (text == null) return;
    final normalized = text.trim().replaceAll('%', '').replaceAll(',', '').replaceAll('，', '');
    final v = double.tryParse(normalized);
    if (v == null) {
      AppToast.info('请输入有效比例');
      return;
    }
    if (v < 0 || v > 100) {
      AppToast.info('回水比例须为 0~100');
      return;
    }
    try {
      await ref.read(ownerRepositoryProvider).updateMemberRebate(widget.memberId, v);
      _rebateCtrl.text = hostNumStr(v, fraction: 2);
      AppToast.success('已保存');
    } catch (e) {
      AppToast.error(e.toString());
    }
  }

  Future<void> _markFake() async {
    final toFake = !(_member?.isTrial ?? false);
    final ok = await hostConfirm(
      context,
      title: toFake ? '标记试玩号' : '切回正式',
      message: toFake
          ? '确认将该玩家切为试玩号？对方会被退出登录，需要重新登录。'
          : '确认将该玩家切回正式？对方会被退出登录，需要重新登录。',
    );
    if (!ok || !mounted) return;
    try {
      await ref.read(ownerRepositoryProvider).markMemberFake(widget.memberId, fake: toFake);
      AppToast.success(toFake ? '已切为试玩号' : '已切回正式');
      await _load(silent: true);
    } catch (e) {
      AppToast.error(e.toString());
    }
  }

  Future<void> _deleteMember() async {
    final ok = await hostConfirm(context, title: '删除玩家', message: '确认删除该玩家？', danger: true);
    if (!ok || !mounted) return;
    try {
      await ref.read(ownerRepositoryProvider).deleteMember(widget.memberId);
      if (!mounted) return;
      AppToast.success('已删除');
      Navigator.of(context).pop();
    } catch (e) {
      AppToast.error(e.toString());
    }
  }

  Future<void> _setStatus(String status, String tip) async {
    if (_statusBusy) return;
    final cur = (_member?.status ?? 'NORMAL').toUpperCase();
    if (cur == status.toUpperCase()) {
      AppToast.info('当前已是$tip');
      return;
    }
    final ok = await hostConfirm(context, title: tip, message: tip, danger: true);
    if (!ok || !mounted) return;
    _statusBusy = true;
    try {
      await ref.read(ownerRepositoryProvider).updateMemberStatus(widget.memberId, status);
      AppToast.success('已提交');
      await _load(silent: true);
    } catch (e) {
      AppToast.error(e.toString());
    } finally {
      _statusBusy = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final member = _member;
    final blue = AppColors.navBlue;
    return HostSubPageScaffold(
      title: '玩家信息',
      body: _loading || member == null
          ? const AppPageLoading()
          : ListView(
              padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 24.h),
              children: [
                // 资料卡
                Container(
                  padding: EdgeInsets.all(14.w),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.92),
                    borderRadius: BorderRadius.circular(12.r),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      CircleAvatar(
                        radius: 28.r,
                        backgroundColor: const Color(0xFFBDE0FE),
                        child: Text(
                          member.nickname.isNotEmpty ? member.nickname.characters.first : '?',
                          style: TextStyle(fontSize: 18.sp, color: blue),
                        ),
                      ),
                      SizedBox(width: 12.w),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    _playerTitle(member),
                                    style: TextStyle(fontSize: 17.sp, fontWeight: FontWeight.w700),
                                  ),
                                ),
                                if (member.isTrial) ...[
                                  SizedBox(width: 6.w),
                                  Container(
                                    padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 2.h),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFE53935),
                                      borderRadius: BorderRadius.circular(4.r),
                                    ),
                                    child: Text('试玩号', style: TextStyle(fontSize: 10.sp, color: Colors.white)),
                                  ),
                                ],
                                if (member.isMood) ...[
                                  SizedBox(width: 6.w),
                                  Container(
                                    padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 2.h),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF43A047),
                                      borderRadius: BorderRadius.circular(4.r),
                                    ),
                                    child: Text('机器人', style: TextStyle(fontSize: 10.sp, color: Colors.white)),
                                  ),
                                ],
                              ],
                            ),
                            SizedBox(height: 4.h),
                            Text('ID: ${member.id}', style: TextStyle(fontSize: 12.sp, color: AppColors.textSecondary)),
                            SizedBox(height: 4.h),
                            Text(
                              '彩票余额: ${hostNumStr(member.points, fraction: 2)}',
                              style: TextStyle(fontSize: 13.sp, color: blue, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(width: 8.w),
                      Material(
                        color: blue.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8.r),
                        child: InkWell(
                          onTap: _copyId,
                          borderRadius: BorderRadius.circular(8.r),
                          child: Padding(
                            padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 8.h),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.copy_outlined, size: 14.sp, color: blue),
                                SizedBox(width: 4.w),
                                Text(
                                  '复制ID',
                                  style: TextStyle(fontSize: 12.sp, color: blue, fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 14.h),
                // 用户操作
                _sectionTitle('用户操作'),
                _menuCard([
                  _MenuItem(Icons.edit_outlined, '设置备注', _editRemark),
                  _MenuItem(Icons.chat_bubble_outline, '发起私聊', () {
                    pushHostPage(
                      context,
                      HostServicePage(
                        roomId: widget.roomId,
                        openAccountId: widget.memberId,
                        openName: _csOpenName(member),
                      ),
                    );
                  }),
                  if (!member.isMood) _MenuItem(Icons.trending_up, '给会员上分', () => _creditDialog('UP')),
                  if (!member.isMood) _MenuItem(Icons.trending_down, '给会员下分', () => _creditDialog('DOWN')),
                ]),
                SizedBox(height: 14.h),
                // 账号管理
                _sectionTitle('账号管理'),
                _menuCard([
                  _MenuItem(Icons.percent, '特殊回水', _editRebate),
                  if (!member.isMood)
                    member.isAgent
                        ? _MenuItem(Icons.person_remove_outlined, '取消代理', _cancelAgent, danger: true)
                        : _MenuItem(Icons.manage_accounts_outlined, '设置代理', _setAgentDialog),
                  if (!member.isMood)
                    _MenuItem(
                      Icons.smart_toy_outlined,
                      member.isTrial ? '切回正式' : '标记试玩号',
                      _markFake,
                    ),
                  _MenuItem(
                    Icons.block,
                    member.status.toUpperCase() == 'BAN_ENTER' ? '当前已禁止进房' : '封禁玩家',
                    member.status.toUpperCase() == 'BAN_ENTER' || _statusBusy
                        ? null
                        : () => _setStatus('BAN_ENTER', '禁止进房'),
                    danger: true,
                  ),
                  _MenuItem(Icons.delete_outline, '删除玩家', _deleteMember, danger: true),
                ]),
                SizedBox(height: 14.h),
                _sectionTitle('报表入口'),
                _menuCard([
                  _MenuItem(Icons.account_balance_wallet_outlined, '积分账变', () {
                    pushHostPage(
                      context,
                      HostMemberReportPage(
                        roomId: widget.roomId,
                        accountId: widget.memberId,
                        kind: 'credits',
                      ),
                    );
                  }),
                  _MenuItem(Icons.search, '竞猜记录', () {
                    pushHostPage(
                      context,
                      HostMemberReportPage(
                        roomId: widget.roomId,
                        accountId: widget.memberId,
                        kind: 'bets',
                      ),
                    );
                  }),
                  _MenuItem(Icons.card_giftcard_outlined, '福利报表', () {
                    pushHostPage(
                      context,
                      HostMemberReportPage(
                        roomId: widget.roomId,
                        accountId: widget.memberId,
                        kind: 'welfare',
                      ),
                    );
                  }),
                  _MenuItem(Icons.redeem_outlined, '红包报表', () {
                    pushHostPage(
                      context,
                      HostMemberReportPage(
                        roomId: widget.roomId,
                        accountId: widget.memberId,
                        kind: 'redpacks',
                      ),
                    );
                  }),
                  _MenuItem(Icons.swap_vert, '上下分记录', () {
                    pushHostPage(
                      context,
                      HostMemberReportPage(
                        roomId: widget.roomId,
                        accountId: widget.memberId,
                        kind: 'updown',
                      ),
                    );
                  }),
                ]),
              ],
            ),
    );
  }

  Widget _sectionTitle(String text) {
    return Padding(
      padding: EdgeInsets.only(left: 4.w, bottom: 8.h),
      child: Text(text, style: TextStyle(fontSize: 12.sp, color: AppColors.textSecondary)),
    );
  }

  Widget _menuCard(List<_MenuItem> items) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12.r),
      ),
      child: Column(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) Divider(height: 1, indent: 48.w, color: const Color(0xFFF0F0F0)),
            _menuRow(items[i]),
          ],
        ],
      ),
    );
  }

  Widget _menuRow(_MenuItem item) {
    final c = item.danger ? AppColors.danger : const Color(0xFF333333);
    final iconC = item.danger ? AppColors.danger : AppColors.navBlue;
    return InkWell(
      onTap: item.onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 14.h),
        child: Row(
          children: [
            Icon(item.icon, size: 20.sp, color: item.onTap == null ? AppColors.textHint : iconC),
            SizedBox(width: 12.w),
            Expanded(
              child: Text(
                item.label,
                style: TextStyle(
                  fontSize: 15.sp,
                  color: item.onTap == null ? AppColors.textHint : c,
                ),
              ),
            ),
            Icon(Icons.chevron_right, size: 18.sp, color: const Color(0xFFBDBDBD)),
          ],
        ),
      ),
    );
  }
}

class _MenuItem {
  const _MenuItem(this.icon, this.label, this.onTap, {this.danger = false});
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool danger;
}
