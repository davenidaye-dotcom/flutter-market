import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../../config/theme/app_colors.dart';
import '../../../../data/repositories/providers.dart';
import '../../../../shared/widgets/emulator_safe_text_field.dart';
import '../../../../shared/widgets/page_app_bar.dart';
import '../../data/host_mock.dart';
import '../../widgets/host_ui.dart';

/// 下线管理 — GET /owner/room/agents/{id}/downlines
/// 抽佣比例（代理回水）走 POST /owner/room/members/{代理id}/agent { commissionRatio }
class HostAgentDownlinesPage extends ConsumerStatefulWidget {
  const HostAgentDownlinesPage({
    super.key,
    required this.roomId,
    required this.agentAccountId,
    required this.agentName,
    this.initialCommission,
    this.openAddOnStart = false,
  });

  final String roomId;
  final String agentAccountId;
  final String agentName;
  final num? initialCommission;
  final bool openAddOnStart;

  @override
  ConsumerState<HostAgentDownlinesPage> createState() =>
      _HostAgentDownlinesPageState();
}

class _HostAgentDownlinesPageState extends ConsumerState<HostAgentDownlinesPage> {
  final _search = TextEditingController();
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;
  late String _commissionText;

  @override
  void initState() {
    super.initState();
    final c = widget.initialCommission;
    _commissionText = c == null ? '1' : hostNumStr(c);
    Future.microtask(() async {
      await _load();
      if (widget.openAddOnStart && mounted) {
        await _showAddSheet();
      }
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final repo = ref.read(ownerRepositoryProvider);
      final list = await repo.getAgentDownlines(
        widget.agentAccountId,
        keyword: _search.text.trim(),
        pageSize: 100,
      );
      // 抽佣比例在代理成员上，见成员详情
      final detail = await repo.getMemberDetail(widget.agentAccountId);
      final c = detail['commissionRatio'];
      final ratio = c is num ? c : num.tryParse('$c');
      if (!mounted) return;
      setState(() {
        _rows = list;
        if (ratio != null) _commissionText = hostNumStr(ratio);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      AppToast.error(e.toString());
    }
  }

  Future<void> _saveCommission(num ratio) async {
    await ref.read(ownerRepositoryProvider).setMemberAgent(
          accountId: widget.agentAccountId,
          commissionRatio: ratio,
        );
    if (!mounted) return;
    setState(() => _commissionText = hostNumStr(ratio));
    AppToast.success('抽佣比例已更新');
  }

  Future<void> _editCommission() async {
    final text = await hostInputSheet(
      context,
      title: '设置抽佣比例',
      initial: _commissionText,
      hint: '如 1 表示 1%',
      suffixText: '%',
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
    );
    if (text == null || !mounted) return;
    final ratio = num.tryParse(text.trim());
    if (ratio == null || ratio < 0) {
      AppToast.error('请输入有效抽佣比例');
      return;
    }
    try {
      await _saveCommission(ratio);
    } catch (e) {
      AppToast.error(e.toString());
    }
  }

  Future<void> _showAddSheet() async {
    final result = await showAddAgentDownlineSheet(
      context,
      agentName: widget.agentName,
      defaultCommission: num.tryParse(_commissionText) ?? 1,
    );
    if (result == null || !mounted) return;
    try {
      final repo = ref.read(ownerRepositoryProvider);
      await repo.addAgentDownline(
        agentAccountId: widget.agentAccountId,
        memberAccountId: result.memberAccountId,
      );
      await repo.setMemberAgent(
        accountId: widget.agentAccountId,
        commissionRatio: result.commissionRatio,
      );
      if (!mounted) return;
      setState(() => _commissionText = hostNumStr(result.commissionRatio));
      AppToast.success('已添加下线');
      await _load();
    } catch (e) {
      AppToast.error(e.toString());
    }
  }

  Future<void> _remove(String memberId, String name) async {
    final ok = await hostConfirm(
      context,
      title: '解除上下级关系',
      message: '确定解除与 $name 的上下级关系？',
      danger: true,
    );
    if (!ok || !mounted) return;
    try {
      await ref.read(ownerRepositoryProvider).removeAgentDownline(
            agentAccountId: widget.agentAccountId,
            memberAccountId: memberId,
          );
      AppToast.success('已解除');
      await _load();
    } catch (e) {
      AppToast.error(e.toString());
    }
  }

  Future<void> _more(Map<String, dynamic> m) async {
    final id = (m['accountId'] ?? m['id'] ?? '').toString();
    final nick = (m['nickname'] ?? m['username'] ?? '').toString();
    final user = (m['username'] ?? '').toString();
    final display = nick.isEmpty ? user : nick;
    if (id.isEmpty) return;

    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(16.r)),
        ),
        child: SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 16.h),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 36.w,
                  height: 4.h,
                  decoration: BoxDecoration(
                    color: const Color(0xFFDDDDDD),
                    borderRadius: BorderRadius.circular(2.r),
                  ),
                ),
                SizedBox(height: 12.h),
                Text(display, style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w700)),
                SizedBox(height: 12.h),
                _sheetItem(
                  Icons.tune,
                  '设置抽佣比例',
                  () => Navigator.pop(ctx, 'commission'),
                ),
                _sheetItem(
                  Icons.link_off,
                  '解除上下级关系',
                  () => Navigator.pop(ctx, 'remove'),
                  danger: true,
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (action == null || !mounted) return;
    if (action == 'commission') {
      await _editCommission();
      return;
    }
    if (action == 'remove') {
      await _remove(id, display);
    }
  }

  Widget _sheetItem(IconData icon, String label, VoidCallback onTap, {bool danger = false}) {
    final c = danger ? const Color(0xFFE53935) : const Color(0xFF333333);
    return Padding(
      padding: EdgeInsets.only(bottom: 8.h),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10.r),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10.r),
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 14.h),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10.r),
              border: Border.all(color: const Color(0xFFE8E8E8)),
            ),
            child: Row(
              children: [
                Icon(icon, size: 20.sp, color: c),
                SizedBox(width: 10.w),
                Expanded(
                  child: Text(label, style: TextStyle(fontSize: 15.sp, color: c, fontWeight: FontWeight.w500)),
                ),
                Icon(Icons.chevron_right, color: const Color(0xFFBDBDBD), size: 20.sp),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final blue = AppColors.navBlue;
    final title = widget.agentName.isEmpty ? '下级会员' : '${widget.agentName}下级会员';
    return HostSubPageScaffold(
      title: title,
      trailing: TextButton(
        onPressed: _showAddSheet,
        child: Text('添加', style: TextStyle(fontSize: 14.sp, color: Colors.white)),
      ),
      body: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(16.w, 10.h, 16.w, 8.h),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    height: 40.h,
                    padding: EdgeInsets.symmetric(horizontal: 12.w),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10.r),
                      border: Border.all(color: const Color(0xFFE0E0E0)),
                    ),
                    alignment: Alignment.center,
                    child: EmulatorSafeTextField(
                      controller: _search,
                      onSubmitted: (_) => _load(),
                      decoration: InputDecoration(
                        border: InputBorder.none,
                        hintText: '请输入玩家用户昵称或备注',
                        hintStyle: TextStyle(fontSize: 13.sp, color: AppColors.textHint),
                        isDense: true,
                      ),
                    ),
                  ),
                ),
                SizedBox(width: 8.w),
                GestureDetector(
                  onTap: _load,
                  child: Container(
                    width: 40.w,
                    height: 40.h,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: blue,
                      borderRadius: BorderRadius.circular(10.r),
                    ),
                    child: Icon(Icons.search, color: Colors.white, size: 22.sp),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _rows.isEmpty
                    ? Center(
                        child: Text(
                          '暂无下线，点右上角添加',
                          style: TextStyle(fontSize: 14.sp, color: AppColors.textHint),
                        ),
                      )
                    : ListView.separated(
                        padding: EdgeInsets.fromLTRB(16.w, 0, 16.w, 16.h),
                        itemCount: _rows.length + 1,
                        separatorBuilder: (_, i) =>
                            i >= _rows.length - 1 ? const SizedBox.shrink() : SizedBox(height: 10.h),
                        itemBuilder: (_, i) {
                          if (i == _rows.length) {
                            return Padding(
                              padding: EdgeInsets.only(top: 12.h),
                              child: Center(
                                child: Text(
                                  '没有更多了，共 ${_rows.length} 条',
                                  style: TextStyle(fontSize: 12.sp, color: AppColors.textHint),
                                ),
                              ),
                            );
                          }
                          final m = _rows[i];
                          final nick = (m['nickname'] ?? m['username'] ?? '').toString();
                          final user = (m['username'] ?? '').toString();
                          final id = (m['accountId'] ?? m['id'] ?? '').toString();
                          final balance = m['balance'] ?? 0;
                          final initial = nick.isNotEmpty ? nick.characters.first : '?';
                          final display = nick.isEmpty ? user : nick;
                          return Material(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12.r),
                            child: Padding(
                              padding: EdgeInsets.fromLTRB(12.w, 12.h, 12.w, 12.h),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    radius: 22.r,
                                    backgroundColor: const Color(0xFFBDE0FE),
                                    child: Text(
                                      initial,
                                      style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                  SizedBox(width: 10.w),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          display,
                                          style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w700),
                                        ),
                                        SizedBox(height: 4.h),
                                        Text(
                                          'ID:$id',
                                          style: TextStyle(fontSize: 12.sp, color: AppColors.textSecondary),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        '余额 ${hostNumStr(balance, fraction: 2)}',
                                        style: TextStyle(fontSize: 13.sp, color: blue, fontWeight: FontWeight.w600),
                                      ),
                                      SizedBox(height: 2.h),
                                      Text(
                                        '返佣比例:$_commissionText%',
                                        style: TextStyle(fontSize: 12.sp, color: AppColors.textSecondary),
                                      ),
                                      SizedBox(height: 8.h),
                                      GestureDetector(
                                        onTap: () => _more(m),
                                        child: Container(
                                          padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFF2F2F2),
                                            borderRadius: BorderRadius.circular(14.r),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(Icons.more_horiz, size: 16.sp, color: const Color(0xFF666666)),
                                              SizedBox(width: 2.w),
                                              Text('更多', style: TextStyle(fontSize: 12.sp, color: const Color(0xFF666666))),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

class AddAgentDownlineResult {
  const AddAgentDownlineResult({
    required this.memberAccountId,
    required this.commissionRatio,
  });
  final String memberAccountId;
  final num commissionRatio;
}

/// UI：添加{代理名}下线 — 会员ID + 抽佣比例（键盘避让走 hostFormSheet）
Future<AddAgentDownlineResult?> showAddAgentDownlineSheet(
  BuildContext context, {
  required String agentName,
  num defaultCommission = 1,
}) async {
  final memberId = TextEditingController();
  final ratio = TextEditingController(text: hostNumStr(defaultCommission));
  final name = agentName.isEmpty ? '代理' : agentName;
  AddAgentDownlineResult? result;

  final ok = await hostFormSheet(
    context,
    title: '添加$name下线',
    confirmText: '保存',
    buildFields: (ctx, setSheet) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('会员ID', style: TextStyle(fontSize: 14.sp, color: AppColors.textSecondary)),
        SizedBox(height: 6.h),
        EmulatorSafeTextField(
          controller: memberId,
          keyboardType: TextInputType.number,
          scrollPadding: EdgeInsets.fromLTRB(20.w, 20.h, 20.w, 160.h),
          decoration: InputDecoration(
            hintText: '请输入会员ID',
            hintStyle: TextStyle(fontSize: 14.sp, color: AppColors.textHint),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8.r)),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8.r),
              borderSide: const BorderSide(color: Color(0xFFDDDDDD)),
            ),
            contentPadding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 12.h),
          ),
        ),
        SizedBox(height: 14.h),
        Text('抽佣比例', style: TextStyle(fontSize: 14.sp, color: AppColors.textSecondary)),
        SizedBox(height: 6.h),
        EmulatorSafeTextField(
          controller: ratio,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          scrollPadding: EdgeInsets.fromLTRB(20.w, 20.h, 20.w, 160.h),
          decoration: InputDecoration(
            hintText: '百分比，如 1',
            hintStyle: TextStyle(fontSize: 14.sp, color: AppColors.textHint),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8.r)),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8.r),
              borderSide: const BorderSide(color: Color(0xFFDDDDDD)),
            ),
            contentPadding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 12.h),
          ),
        ),
      ],
    ),
    onConfirm: () async {
      final id = memberId.text.trim();
      final r = num.tryParse(ratio.text.trim());
      if (id.isEmpty) {
        AppToast.error('请输入会员ID');
        return false;
      }
      if (r == null || r < 0) {
        AppToast.error('请输入有效抽佣比例');
        return false;
      }
      result = AddAgentDownlineResult(memberAccountId: id, commissionRatio: r);
      return true;
    },
  );

  memberId.dispose();
  ratio.dispose();
  return ok ? result : null;
}
