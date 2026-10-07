import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../config/theme/app_colors.dart';
import '../../../data/repositories/providers.dart';
import '../../../shared/widgets/emulator_safe_dialog.dart';
import '../../../shared/widgets/emulator_safe_text_field.dart';
import '../../../shared/widgets/page_app_bar.dart';
import '../widgets/agent_ui.dart';
import '../../../shared/widgets/app_page_loading.dart';
import 'agent_account_child_page.dart';
import 'agent_child_credit_page.dart';
import 'agent_child_logs_page.dart';
import 'agent_child_odds_page.dart';
import 'agent_child_settings_page.dart';
import 'agent_child_share_page.dart';
import 'agent_quota_change_page.dart';

/// 账户管理：直属列表、卡片下钻、底栏功能选择
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

  /// 下钻栈：每层 {agentId, accountId, username, displayName, agentLevel}
  final List<Map<String, dynamic>> _drill = [];
  String _childType = 'ALL';

  int? get _parentAgentId {
    if (_drill.isEmpty) return null;
    final id = _drill.last['agentId'];
    if (id is int) return id;
    return int.tryParse('$id');
  }

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
            parentAgentId: _parentAgentId,
            childType: _childType,
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

  void _drillInto(Map<String, dynamic> row, {required String childType}) {
    final agentId = row['agentId'];
    final id = agentId is int ? agentId : int.tryParse('$agentId');
    if (id == null) {
      AppToast.error('无法下钻：缺少代理节点');
      return;
    }
    setState(() {
      _drill.add({
        'agentId': id,
        'accountId': agentRowAccountId(row),
        'username': '${row['username'] ?? ''}',
        'displayName': '${row['displayName'] ?? row['username'] ?? ''}',
        'agentLevel': row['agentLevel'],
      });
      _childType = childType;
      _page = 1;
      _searchCtrl.clear();
    });
    _load();
  }

  void _popDrill() {
    if (_drill.isEmpty) return;
    setState(() {
      _drill.removeLast();
      _childType = 'ALL';
      _page = 1;
    });
    _load();
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
                      items: [
                        for (final e in accountTypeLabels.entries)
                          DropdownMenuItem(value: e.key, child: Text(e.value)),
                      ],
                      onChanged: (v) {
                        if (v == null) return;
                        setLocal(() => type = v);
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('确定')),
          ],
        ),
      ),
    );
    final username = userCtrl.text.trim();
    final password = passCtrl.text;
    final confirmPassword = confirmCtrl.text;
    final displayName = nameCtrl.text.trim();
    userCtrl.dispose();
    passCtrl.dispose();
    confirmCtrl.dispose();
    nameCtrl.dispose();
    if (ok != true) return;
    if (username.isEmpty || password.isEmpty) {
      AppToast.error('请填写用户名和密码');
      return;
    }
    try {
      await ref.read(agentRepositoryProvider).createAccount(
            username: username,
            password: password,
            confirmPassword: confirmPassword,
            type: type,
            displayName: displayName.isEmpty ? null : displayName,
            parentAgentId: _parentAgentId,
          );
      AppToast.success('创建成功');
      _page = 1;
      await _load();
    } catch (e) {
      AppToast.error(e.toString());
    }
  }

  Future<void> _openSheet(Map<String, dynamic> row) async {
    final id = agentRowAccountId(row);
    final name = agentRowName(row);
    final username = '${row['username'] ?? ''}';
    final isAgent = agentRowIsAgent(row);
    final isDelegate = agentRowIsDelegate(row);
    final showShare = isAgent;
    final showOdds = !isDelegate;

    final actions = <({String label, Future<void> Function() run})>[
      (
        label: '上下分',
        run: () async {
          if (id == null) return;
          final changed = await Navigator.of(context).push<bool>(
            MaterialPageRoute(
              builder: (_) => AgentChildCreditPage(
                accountId: id,
                title: name,
                available: row['balance'] ?? row['available'],
              ),
            ),
          );
          if (changed == true && mounted) await _load();
        },
      ),
      (
        label: '账号设置',
        run: () async {
          final changed = await Navigator.of(context).push<bool>(
            MaterialPageRoute(builder: (_) => AgentChildSettingsPage(row: row)),
          );
          if (changed == true && mounted) await _load();
        },
      ),
      if (showShare)
        (
          label: '占成',
          run: () async {
            if (id == null) return;
            final changed = await Navigator.of(context).push<bool>(
              MaterialPageRoute(
                builder: (_) => AgentChildSharePage(accountId: id, title: name),
              ),
            );
            if (changed == true && mounted) await _load();
          },
        ),
      if (showOdds)
        (
          label: '赔率返水',
          run: () async {
            if (id == null) return;
            await Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => AgentChildOddsPage(accountId: id, title: name),
              ),
            );
          },
        ),
      (
        label: '积分明细',
        run: () async {
          if (id == null) return;
          await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => AgentQuotaChangePage(
                roomId: widget.roomId,
                accountId: id,
                titleName: name,
              ),
            ),
          );
        },
      ),
      (
        label: '日志',
        run: () async {
          await Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => AgentChildLogsPage(row: row)),
          );
        },
      ),
    ];

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16.r)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 8.h),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                username.isEmpty ? name : '$username（$name）',
                style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w700, color: AgentChrome.ink),
              ),
              SizedBox(height: 2.h),
              Text('请选择操作', style: TextStyle(fontSize: 12.sp, color: AppColors.textSecondary)),
              SizedBox(height: 8.h),
              for (final a in actions)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(a.label, style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w600)),
                  trailing: Icon(Icons.chevron_right, color: AppColors.textHint, size: 20.sp),
                  onTap: () async {
                    Navigator.pop(ctx);
                    await a.run();
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _focusBar() {
    if (_drill.isEmpty) return const SizedBox.shrink();
    final cur = _drill.last;
    final name = '${cur['displayName'] ?? cur['username'] ?? ''}';
    final user = '${cur['username'] ?? ''}';
    final level = cur['agentLevel'];
    final levelText = level is num ? '${level.toInt()}级代理' : '代理';
    final id = cur['accountId'];
    return Padding(
      padding: EdgeInsets.only(bottom: 10.h),
      child: AgentSurface(
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('上级信息', style: TextStyle(fontSize: 11.sp, color: AppColors.textHint)),
                  SizedBox(height: 2.h),
                  Text(
                    user.isEmpty ? name : '$user（$name）',
                    style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w700, color: AgentChrome.ink),
                  ),
                  Text(
                    '$levelText · ID ${id ?? '—'}',
                    style: TextStyle(fontSize: 12.sp, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
            OutlinedButton.icon(
              onPressed: _popDrill,
              icon: Icon(Icons.chevron_left, size: 18.sp),
              label: Text('返回上级', style: TextStyle(fontSize: 12.sp)),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.navBlue,
                side: BorderSide(color: AgentChrome.cardBorder),
                padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 8.h),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _metricTile(String label, String value, {bool accent = false, VoidCallback? onTap}) {
    final child = Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 8.h),
      decoration: BoxDecoration(
        color: AgentChrome.fieldBg,
        borderRadius: BorderRadius.circular(8.r),
        border: Border.all(color: AgentChrome.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 11.sp, color: AppColors.textSecondary)),
          SizedBox(height: 4.h),
          Row(
            children: [
              Expanded(
                child: Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14.sp,
                    fontWeight: FontWeight.w700,
                    color: accent ? AgentChrome.pnlUp : AgentChrome.ink,
                  ),
                ),
              ),
              if (onTap != null) Icon(Icons.chevron_right, size: 16.sp, color: AppColors.textHint),
            ],
          ),
        ],
      ),
    );
    if (onTap == null) return child;
    return Material(
      color: Colors.transparent,
      child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(8.r), child: child),
    );
  }

  Widget _accountCard(Map<String, dynamic> r) {
    final name = agentRowName(r);
    final username = '${r['username'] ?? ''}';
    final typeLabel = agentAccountTypeLabel(r);
    final status = agentAccountStatusLabel(r['status']?.toString());
    final isAgent = agentRowIsAgent(r);
    final parent = '${r['parentUsername'] ?? ''}';
    final id = agentRowAccountId(r);
    final nick = '${r['displayName'] ?? ''}'.trim();
    final showNick = nick.isNotEmpty && nick != username && nick != name;

    return AgentSurface(
      padding: EdgeInsets.all(12.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => _openSheet(r),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40.w,
                  height: 40.w,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    color: AppColors.navBlue,
                    shape: BoxShape.circle,
                  ),
                  child: Text('设置', style: TextStyle(fontSize: 11.sp, color: Colors.white, fontWeight: FontWeight.w600)),
                ),
                SizedBox(width: 10.w),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 6.w,
                        runSpacing: 4.h,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            username.isEmpty ? name : username,
                            style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w700, color: AgentChrome.ink),
                          ),
                          if (showNick)
                            Text('[$nick]', style: TextStyle(fontSize: 12.sp, color: const Color(0xFFE67E22))),
                          _chip(typeLabel, isAgent ? AppColors.navBlue : AgentChrome.pnlUp),
                          _chip(status, AgentChrome.pnlUp),
                        ],
                      ),
                      SizedBox(height: 4.h),
                      Text(
                        'ID ${id ?? '—'} · 上级 ${parent.isEmpty ? '—' : parent}',
                        style: TextStyle(fontSize: 12.sp, color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: 10.h),
          if (isAgent)
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 8.h,
              crossAxisSpacing: 8.w,
              childAspectRatio: 2.4,
              children: [
                _metricTile('余额', agentBalanceLabel(r['balance']), accent: true),
                _metricTile('下级余额', agentBalanceLabel(r['subordinateBalance'])),
                _metricTile(
                  '直属会员',
                  '${r['childMemberCount'] ?? 0}',
                  onTap: () => _drillInto(r, childType: 'MEMBER'),
                ),
                _metricTile(
                  '下级代理',
                  '${r['childAgentCount'] ?? 0}',
                  onTap: () => _drillInto(r, childType: 'AGENT'),
                ),
              ],
            )
          else
            InkWell(
              onTap: () => _openSheet(r),
              child: _metricTile('余额', agentBalanceLabel(r['balance']), accent: true),
            ),
        ],
      ),
    );
  }

  Widget _chip(String text, Color color) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 2.h),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4.r),
      ),
      child: Text(text, style: TextStyle(fontSize: 11.sp, color: color, fontWeight: FontWeight.w600)),
    );
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
      itemBuilder: (_, i) => _accountCard(_rows[i]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AgentPageFrame(
      title: '账户管理',
      child: Column(
        children: [
          SizedBox(height: 8.h),
          _focusBar(),
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
                        _childType = 'ALL';
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
