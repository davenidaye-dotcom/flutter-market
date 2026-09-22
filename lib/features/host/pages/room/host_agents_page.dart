import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../../config/theme/app_colors.dart';
import '../../../../data/repositories/providers.dart';
import '../../../../shared/widgets/emulator_safe_text_field.dart';
import '../../../../shared/widgets/page_app_bar.dart';
import '../../widgets/host_ui.dart';
import 'host_agent_downlines_page.dart';

/// 代理成员 — 搜索 + 卡片列表 + 更多菜单（对齐竞品截图）
class HostAgentsPage extends ConsumerStatefulWidget {
  const HostAgentsPage({super.key, required this.roomId});
  final String roomId;

  @override
  ConsumerState<HostAgentsPage> createState() => _HostAgentsPageState();
}

class _HostAgentsPageState extends ConsumerState<HostAgentsPage> {
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = await ref.read(ownerRepositoryProvider).getAgents(
            keyword: _search.text.trim(),
            pageSize: 100,
          );
      if (!mounted) return;
      setState(() {
        _rows = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      AppToast.error(e.toString());
    }
  }

  String _idOf(Map<String, dynamic> m) =>
      (m['accountId'] ?? m['agentId'] ?? m['id'] ?? '').toString();

  String _nameOf(Map<String, dynamic> m) =>
      (m['nickname'] ?? m['displayName'] ?? m['username'] ?? '').toString();

  Future<num> _loadCommission(String accountId) async {
    try {
      final detail = await ref.read(ownerRepositoryProvider).getMemberDetail(accountId);
      final c = detail['commissionRatio'];
      if (c is num) return c;
      return num.tryParse('$c') ?? 1;
    } catch (_) {
      return 1;
    }
  }

  Future<void> _openDownlines(Map<String, dynamic> m, {bool openAdd = false}) async {
    final id = _idOf(m);
    if (id.isEmpty) return;
    final commission = await _loadCommission(id);
    if (!mounted) return;
    await pushHostPage(
      context,
      HostAgentDownlinesPage(
        roomId: widget.roomId,
        agentAccountId: id,
        agentName: _nameOf(m),
        initialCommission: commission,
        openAddOnStart: openAdd,
      ),
    );
    if (mounted) await _load();
  }

  Future<void> _addDownline(Map<String, dynamic> m) async {
    final id = _idOf(m);
    final name = _nameOf(m);
    if (id.isEmpty) return;
    final defaultRatio = await _loadCommission(id);
    if (!mounted) return;
    final result = await showAddAgentDownlineSheet(
      context,
      agentName: name,
      defaultCommission: defaultRatio,
    );
    if (result == null || !mounted) return;
    try {
      final repo = ref.read(ownerRepositoryProvider);
      await repo.addAgentDownline(
        agentAccountId: id,
        memberAccountId: result.memberAccountId,
      );
      // 抽佣 = POST /owner/room/members/{id}/agent { commissionRatio }
      await repo.setMemberAgent(
        accountId: id,
        commissionRatio: result.commissionRatio,
      );
      AppToast.success('已添加下线');
      await _load();
    } catch (e) {
      AppToast.error(e.toString());
    }
  }

  Future<void> _more(Map<String, dynamic> m) async {
    final id = _idOf(m);
    final name = _nameOf(m);
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
                Text(name, style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w700)),
                SizedBox(height: 12.h),
                _sheetItem(Icons.groups_outlined, '下线管理', () => Navigator.pop(ctx, 'downlines')),
                _sheetItem(Icons.person_add_alt_1_outlined, '添加下线', () => Navigator.pop(ctx, 'add')),
                _sheetItem(Icons.person_remove_outlined, '取消代理', () => Navigator.pop(ctx, 'cancel'), danger: true),
                _sheetItem(Icons.block, '封禁用户', () => Navigator.pop(ctx, 'ban'), danger: true),
                _sheetItem(Icons.delete_outline, '删除用户', () => Navigator.pop(ctx, 'delete'), danger: true),
              ],
            ),
          ),
        ),
      ),
    );
    if (action == null || !mounted) return;
    if (action == 'downlines') {
      await _openDownlines(m);
      return;
    }
    if (action == 'add') {
      await _addDownline(m);
      return;
    }
    final repo = ref.read(ownerRepositoryProvider);
    try {
      switch (action) {
        case 'cancel':
          await repo.cancelMemberAgent(id);
          AppToast.success('已取消代理');
          await _load();
          break;
        case 'ban':
          await repo.updateMemberStatus(id, 'BAN_ENTER');
          AppToast.success('已封禁');
          await _load();
          break;
        case 'delete':
          await repo.deleteMember(id);
          AppToast.success('已删除');
          await _load();
          break;
      }
    } catch (e) {
      AppToast.error(e.toString());
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
    return HostSubPageScaffold(
      title: '代理成员',
      body: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 8.h),
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
                        child: Text('暂无代理', style: TextStyle(fontSize: 14.sp, color: AppColors.textHint)),
                      )
                    : ListView.separated(
                        padding: EdgeInsets.fromLTRB(16.w, 4.h, 16.w, 16.h),
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
                          final nick = _nameOf(m);
                          final user = (m['username'] ?? '').toString();
                          final id = _idOf(m);
                          final subCount = m['subordinateCount'] ?? m['memberCount'] ?? 0;
                          final initial = nick.isNotEmpty ? nick.characters.first : '?';
                          return Material(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12.r),
                            child: InkWell(
                              onTap: () => _openDownlines(m),
                              borderRadius: BorderRadius.circular(12.r),
                              child: Padding(
                                padding: EdgeInsets.fromLTRB(12.w, 12.h, 12.w, 12.h),
                                child: Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 22.r,
                                      backgroundColor: const Color(0xFFBDE0FE),
                                      child: Text(initial, style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w600)),
                                    ),
                                    SizedBox(width: 10.w),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            nick,
                                            style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w700),
                                          ),
                                          SizedBox(height: 4.h),
                                          Text(
                                            'ID:$id${user.isEmpty ? '' : ' · $user'}',
                                            style: TextStyle(fontSize: 12.sp, color: AppColors.textSecondary),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      children: [
                                        Text(
                                          '下线人数:$subCount',
                                          style: TextStyle(fontSize: 13.sp, color: blue, fontWeight: FontWeight.w600),
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
