import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../../config/theme/app_colors.dart';
import '../../../../data/repositories/providers.dart';
import '../../../../shared/widgets/app_pull_refresh.dart';
import '../../../../shared/widgets/emulator_safe_text_field.dart';
import '../../../../shared/widgets/page_app_bar.dart';
import '../../widgets/host_ui.dart';

class _Assistant {
  _Assistant({
    required this.delegationId,
    required this.accountId,
    required this.name,
    required this.username,
    required this.permissions,
    required this.active,
  });

  final String delegationId;
  final String accountId;
  final String name;
  final String username;
  final Set<String> permissions;
  final bool active;
}

/// Owner assistants — /owner/room/assistants
class HostAssistantsPage extends ConsumerStatefulWidget {
  const HostAssistantsPage({super.key, required this.roomId});
  final String roomId;

  @override
  ConsumerState<HostAssistantsPage> createState() => _HostAssistantsPageState();
}

class _HostAssistantsPageState extends ConsumerState<HostAssistantsPage> {
  static const _allPermissions = ['成员', '审核', '赔率', '反水', '报表', '客服'];

  static const _permToCode = {
    '成员': 'ROOM_MEMBER_MANAGE',
    '审核': 'MANAGE_APPLICATION',
    '赔率': 'ROOM_ODDS',
    '反水': 'ROOM_REBATE',
    '报表': 'MANAGE_REPORT',
    '客服': 'CS_REPLY',
  };

  static const _codeToPerm = {
    'ROOM_MEMBER_MANAGE': '成员',
    'MANAGE_APPLICATION': '审核',
    'ROOM_ODDS': '赔率',
    'ROOM_REBATE': '反水',
    'MANAGE_REPORT': '报表',
    'CS_REPLY': '客服',
  };

  List<_Assistant> _assistants = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  Future<void> _load({bool fromPull = false, bool silent = false}) async {
    // 下拉/创建后勿拆掉列表（RefreshIndicator / 模拟器 IME 场景）
    if (!fromPull && !silent && mounted) setState(() => _loading = true);
    try {
      final list = await ref.read(ownerRepositoryProvider).getAssistants();
      if (!mounted) return;
      setState(() {
        _assistants = list.map((m) {
          final perms = m['permissions'];
          final codes = perms is List ? perms.map((e) => '$e').toList() : <String>[];
          return _Assistant(
            delegationId: '${m['delegationId'] ?? m['id'] ?? ''}',
            accountId: '${m['accountId'] ?? ''}',
            name: m['displayName']?.toString() ?? m['username']?.toString() ?? '',
            username: m['username']?.toString() ?? '',
            permissions: codes
                .map((c) => _codeToPerm[c] ?? c)
                .where((p) => _allPermissions.contains(p))
                .toSet(),
            active: (m['status']?.toString().toUpperCase() ?? 'ACTIVE') == 'ACTIVE',
          );
        }).where((a) => a.delegationId.isNotEmpty).toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      AppToast.error(e.toString());
    }
  }

  List<String> _toCodes(Set<String> selected) =>
      selected.map((p) => _permToCode[p] ?? p).whereType<String>().toList();

  Future<void> _createAssistant() async {
    if (_assistants.length >= 2) {
      AppToast.info('最多 2 名协管');
      return;
    }
    final nameCtrl = TextEditingController();
    final userCtrl = TextEditingController();
    final pwdCtrl = TextEditingController(text: 'Pass1234');
    final selected = <String>{'成员', '审核'};
    final ok = await hostFormSheet(
      context,
      title: '创建协管',
      confirmText: '确定',
      buildFields: (ctx, setSheet) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          EmulatorSafeTextField(
            controller: nameCtrl,
            decoration: InputDecoration(
              hintText: '昵称',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10.r)),
            ),
          ),
          SizedBox(height: 8.h),
          EmulatorSafeTextField(
            controller: userCtrl,
            decoration: InputDecoration(
              hintText: '用户名',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10.r)),
            ),
          ),
          SizedBox(height: 8.h),
          EmulatorSafeTextField(
            controller: pwdCtrl,
            obscureText: true,
            decoration: InputDecoration(
              hintText: '初始密码',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10.r)),
            ),
          ),
          SizedBox(height: 12.h),
          Text('权限', style: TextStyle(fontSize: 13.sp, color: AppColors.textSecondary)),
          SizedBox(height: 6.h),
          Wrap(
            spacing: 6.w,
            runSpacing: 6.h,
            children: [
              for (final p in _allPermissions)
                FilterChip(
                  label: Text(p, style: TextStyle(fontSize: 12.sp)),
                  selected: selected.contains(p),
                  onSelected: (v) => setSheet(() {
                    if (v) {
                      selected.add(p);
                    } else {
                      selected.remove(p);
                    }
                  }),
                ),
            ],
          ),
        ],
      ),
    );
    if (!ok) {
      nameCtrl.dispose();
      userCtrl.dispose();
      pwdCtrl.dispose();
      return;
    }
    if (nameCtrl.text.trim().isEmpty || userCtrl.text.trim().isEmpty) {
      AppToast.error('请填写昵称和用户名');
      nameCtrl.dispose();
      userCtrl.dispose();
      pwdCtrl.dispose();
      return;
    }
    try {
      await ref.read(ownerRepositoryProvider).createAssistant(
            username: userCtrl.text.trim(),
            password: pwdCtrl.text,
            displayName: nameCtrl.text.trim(),
            permissions: _toCodes(selected),
          );
      nameCtrl.dispose();
      userCtrl.dispose();
      pwdCtrl.dispose();
      if (!mounted) return;
      AppToast.success('协管已创建');
      await _load(silent: true);
    } catch (e) {
      nameCtrl.dispose();
      userCtrl.dispose();
      pwdCtrl.dispose();
      AppToast.error(e.toString());
    }
  }

  Future<void> _stop(_Assistant a) async {
    final ok = await hostConfirm(
      context,
      title: '停用协管',
      message: '确定停用「${a.name}」吗？',
      danger: true,
    );
    if (!ok || !mounted) return;
    try {
      await ref.read(ownerRepositoryProvider).updateAssistant(
            a.delegationId,
            status: 'DISABLED',
          );
      AppToast.success('已停用');
      await _load(silent: true);
    } catch (e) {
      AppToast.error(e.toString());
    }
  }

  Future<void> _delete(_Assistant a) async {
    final ok = await hostConfirm(
      context,
      title: '删除协管',
      message: '确定删除「${a.name}」吗？',
      danger: true,
    );
    if (!ok || !mounted) return;
    try {
      await ref.read(ownerRepositoryProvider).deleteAssistant(a.delegationId);
      AppToast.success('已删除');
      await _load(silent: true);
    } catch (e) {
      AppToast.error(e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return HostSubPageScaffold(
      title: '协管管理',
      trailing: TextButton(
        onPressed: _createAssistant,
        child: Text('创建', style: TextStyle(fontSize: 14.sp, color: AppColors.navBlue)),
      ),
      body: AppPullRefresh(
        onRefresh: () => _load(fromPull: true),
        child: _loading && _assistants.isEmpty
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(height: 120),
                  Center(child: CircularProgressIndicator()),
                ],
              )
            : _assistants.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      SizedBox(height: 120.h),
                      Center(
                        child: Text('暂无协管', style: TextStyle(fontSize: 14.sp, color: AppColors.textHint)),
                      ),
                    ],
                  )
                : ListView.separated(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 16.h),
                  itemCount: _assistants.length,
                  separatorBuilder: (_, _) => SizedBox(height: 8.h),
                  itemBuilder: (_, i) {
                    final a = _assistants[i];
                    return HostWhiteCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      a.name,
                                      style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w600),
                                    ),
                                    SizedBox(height: 2.h),
                                    Text(
                                      a.username,
                                      style: TextStyle(fontSize: 12.sp, color: AppColors.textSecondary),
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 2.h),
                                decoration: BoxDecoration(
                                  color: (a.active ? AppColors.success : AppColors.textHint)
                                      .withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(10.r),
                                ),
                                child: Text(
                                  a.active ? '启用' : '停用',
                                  style: TextStyle(
                                    fontSize: 11.sp,
                                    color: a.active ? AppColors.success : AppColors.textHint,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: 8.h),
                          Wrap(
                            spacing: 6.w,
                            runSpacing: 4.h,
                            children: [
                              for (final p in a.permissions)
                                Container(
                                  padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 3.h),
                                  decoration: BoxDecoration(
                                    color: AppColors.navBlue.withValues(alpha: 0.08),
                                    borderRadius: BorderRadius.circular(10.r),
                                  ),
                                  child: Text(
                                    p,
                                    style: TextStyle(fontSize: 11.sp, color: AppColors.navBlue),
                                  ),
                                ),
                            ],
                          ),
                          SizedBox(height: 10.h),
                          Row(
                            children: [
                              if (a.active)
                                Expanded(
                                  child: HostPrimaryButton(
                                    label: '停用',
                                    color: AppColors.warning,
                                    onPressed: () => _stop(a),
                                  ),
                                ),
                              if (a.active) SizedBox(width: 8.w),
                              Expanded(
                                child: HostPrimaryButton(
                                  label: '删除',
                                  color: AppColors.danger,
                                  onPressed: () => _delete(a),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
      ),
    );
  }
}
