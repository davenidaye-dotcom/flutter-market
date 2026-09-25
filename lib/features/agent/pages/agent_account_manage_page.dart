import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../config/theme/app_colors.dart';
import '../../../data/repositories/providers.dart';
import '../../../shared/widgets/emulator_safe_dialog.dart';
import '../../../shared/widgets/emulator_safe_text_field.dart';
import '../../../shared/widgets/page_app_bar.dart';
import '../../../shared/widgets/safe_text_controller.dart';
import '../widgets/agent_ui.dart';
import '../../../shared/widgets/app_page_loading.dart';

/// Agent account list / create
class AgentAccountManagePage extends ConsumerStatefulWidget {
  const AgentAccountManagePage({super.key, required this.roomId});

  final String roomId;

  @override
  ConsumerState<AgentAccountManagePage> createState() => _AgentAccountManagePageState();
}

class _AgentAccountManagePageState extends ConsumerState<AgentAccountManagePage> {
  final _searchCtrl = TextEditingController();
  int _page = 1;
  int _totalPages = 0;
  int _total = 0;
  bool _loading = false;
  String? _error;
  List<Map<String, dynamic>> _rows = [];

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await ref.read(agentRepositoryProvider).getAccounts(
            keyword: _searchCtrl.text.trim(),
            pageNum: _page,
            pageSize: 20,
          );
      final raw = data['rows'];
      final list = raw is List
          ? raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
          : <Map<String, dynamic>>[];
      final total = data['total'] is num ? (data['total'] as num).toInt() : list.length;
      final pageSize = data['pageSize'] is num ? (data['pageSize'] as num).toInt() : 20;
      if (!mounted) return;
      setState(() {
        _rows = list;
        _total = total;
        _totalPages = pageSize <= 0 ? 0 : ((total + pageSize - 1) ~/ pageSize);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
      AppToast.error(e.toString());
    }
  }

  Widget _createField(String label, TextEditingController ctrl, {bool obscure = false}) {
    return Padding(
      padding: EdgeInsets.only(bottom: 10.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 12.sp, color: AppColors.textSecondary)),
          SizedBox(height: 4.h),
          Container(
            height: 40.h,
            padding: EdgeInsets.symmetric(horizontal: 10.w),
            decoration: BoxDecoration(
              color: AgentChrome.fieldBg,
              borderRadius: BorderRadius.circular(8.r),
              border: Border.all(color: AgentChrome.cardBorder),
            ),
            alignment: Alignment.centerLeft,
            child: EmulatorSafeTextField(
              controller: ctrl,
              obscureText: obscure,
              style: TextStyle(fontSize: 14.sp, color: AgentChrome.ink),
              decoration: const InputDecoration(
                border: InputBorder.none,
                isCollapsed: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showCreate() async {
    final userCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    var type = 'AGENT_MEMBER';
    const accountTypeLabels = {
      'AGENT_MEMBER': '代理会员',
      'AGENT': '代理',
      'AGENT_DELEGATE': '协管',
    };
    final ok = await showEmulatorSafeDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.r)),
          titlePadding: EdgeInsets.fromLTRB(18.w, 16.h, 18.w, 0),
          contentPadding: EdgeInsets.fromLTRB(18.w, 12.h, 18.w, 0),
          actionsPadding: EdgeInsets.fromLTRB(18.w, 4.h, 18.w, 14.h),
          title: Text(
            '新增账户',
            style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w700, color: AgentChrome.ink),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _createField('用户名', userCtrl),
                _createField('密码', passCtrl, obscure: true),
                _createField('确认密码', confirmCtrl, obscure: true),
                _createField('显示名称', nameCtrl),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text('账户类型', style: TextStyle(fontSize: 12.sp, color: AppColors.textSecondary)),
                ),
                SizedBox(height: 4.h),
                Container(
                  height: 40.h,
                  padding: EdgeInsets.symmetric(horizontal: 10.w),
                  decoration: BoxDecoration(
                    color: AgentChrome.fieldBg,
                    borderRadius: BorderRadius.circular(8.r),
                    border: Border.all(color: AgentChrome.cardBorder),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: type,
                      isExpanded: true,
                      icon: Icon(Icons.keyboard_arrow_down, size: 18.sp, color: AppColors.textSecondary),
                      style: TextStyle(fontSize: 14.sp, color: AgentChrome.ink),
                      items: [
                        for (final entry in accountTypeLabels.entries)
                          DropdownMenuItem(value: entry.key, child: Text(entry.value)),
                      ],
                      onChanged: (v) => setLocal(() => type = v ?? type),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                AgentTealButton(label: '取消', outlined: true, onTap: safeDialogPop(ctx, false)),
                SizedBox(width: 8.w),
                AgentTealButton(label: '确定', onTap: safeDialogPop(ctx, true)),
              ],
            ),
          ],
        ),
      ),
    );
    final username = userCtrl.text.trim();
    final password = passCtrl.text;
    final confirmPassword = confirmCtrl.text;
    final displayName = nameCtrl.text.trim();
    disposeTextControllersAfterFrame([userCtrl, passCtrl, confirmCtrl, nameCtrl]);
    if (ok != true) return;
    if (username.isEmpty || password.isEmpty) {
      AppToast.error('用户名和密码不能为空');
      return;
    }
    if (password != confirmPassword) {
      AppToast.error('新密码与确认密码不一致');
      return;
    }
    try {
      await ref.read(agentRepositoryProvider).createAccount(
            username: username,
            password: password,
            confirmPassword: confirmPassword,
            type: type,
            displayName: displayName.isEmpty ? null : displayName,
          );
      AppToast.success('创建成功');
      _page = 1;
      await _load();
    } catch (e) {
      AppToast.error(e.toString());
    }
  }

  Widget _accountList() {
    if (_loading) return const AppPageLoading();
    if (_error != null) {
      return Center(
        child: GestureDetector(
          onTap: _load,
          child: Text('加载失败，点击重试', style: TextStyle(fontSize: 14.sp, color: AppColors.danger)),
        ),
      );
    }
    if (_rows.isEmpty) {
      return Center(
        child: Text('暂无数据', style: TextStyle(fontSize: 14.sp, color: AppColors.textHint)),
      );
    }
    return ListView.separated(
      padding: EdgeInsets.only(bottom: 8.h),
      itemCount: _rows.length,
      separatorBuilder: (_, _) => SizedBox(height: 8.h),
      itemBuilder: (_, i) {
        final r = _rows[i];
        final name = '${r['displayName'] ?? r['username'] ?? ''}';
        final meta =
            '${r['username'] ?? ''} · ${agentAccountTypeLabel(r)} · ${agentAccountStatusLabel(r['status']?.toString())}';
        return AgentSurface(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w700, color: AgentChrome.ink),
                    ),
                  ),
                  SizedBox(width: 8.w),
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: Text(
                        agentBalanceLabel(r['balance']),
                        maxLines: 1,
                        softWrap: false,
                        style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w700, color: AgentChrome.ink),
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 4.h),
              Text(meta, style: TextStyle(fontSize: 12.sp, color: AppColors.textSecondary)),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return AgentPageFrame(
      title: '\u8d26\u6237\u7ba1\u7406',
      child: Column(
        children: [
          SizedBox(height: 8.h),
          AgentSurface(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  height: 40.h,
                  padding: EdgeInsets.symmetric(horizontal: 10.w),
                  decoration: BoxDecoration(
                    color: AgentChrome.fieldBg,
                    borderRadius: BorderRadius.circular(8.r),
                    border: Border.all(color: AgentChrome.cardBorder),
                  ),
                  alignment: Alignment.centerLeft,
                  child: EmulatorSafeTextField(
                    controller: _searchCtrl,
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      hintText: '账户搜索',
                      hintStyle: TextStyle(fontSize: 13.sp, color: AppColors.textHint),
                      isDense: true,
                    ),
                  ),
                ),
                SizedBox(height: 10.h),
                Row(
                  children: [
                    AgentTealButton(
                      label: '搜索',
                      onTap: () {
                        _page = 1;
                        _load();
                      },
                    ),
                    SizedBox(width: 8.w),
                    AgentTealButton(
                      label: '查看全部',
                      outlined: true,
                      onTap: () {
                        _searchCtrl.clear();
                        _page = 1;
                        _load();
                      },
                    ),
                    SizedBox(width: 8.w),
                    AgentTealButton(label: '新增', outlined: true, onTap: _showCreate),
                  ],
                ),
              ],
            ),
          ),
          SizedBox(height: 10.h),
          Expanded(child: _accountList()),
          AgentPaginationBar(
            page: _page,
            totalPages: _totalPages,
            total: _total,
            onPrev: () {
              if (_page > 1) {
                setState(() => _page--);
                _load();
              }
            },
            onNext: () {
              if (_page < _totalPages) {
                setState(() => _page++);
                _load();
              }
            },
          ),
        ],
      ),
    );
  }
}
