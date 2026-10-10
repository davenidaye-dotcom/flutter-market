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

/// 账户管理：直属列表、卡片内功能按钮、下钻查看下级
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
      'AGENT_DELEGATE': '子账号',
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

  static const _btnGreen = Color(0xFF4CAF50);
  static const _btnCoral = Color(0xFFE57373);
  static const _btnTeal = Color(0xFF4E9BA3);
  static const _typeGreen = Color(0xFF81C784);
  static const _statusBlue = Color(0xFF64B5F6);

  Future<void> _openCredit(Map<String, dynamic> row, {required String direction}) async {
    final id = agentRowAccountId(row);
    if (id == null) return;
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => AgentChildCreditPage(
          accountId: id,
          title: agentRowName(row),
          available: row['balance'] ?? row['available'],
          initialDirection: direction,
        ),
      ),
    );
    if (changed == true && mounted) await _load();
  }

  Future<void> _openSettings(Map<String, dynamic> row) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => AgentChildSettingsPage(row: row)),
    );
    if (changed == true && mounted) await _load();
  }

  Future<void> _openQuota(Map<String, dynamic> row) async {
    final id = agentRowAccountId(row);
    if (id == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AgentQuotaChangePage(
          roomId: widget.roomId,
          accountId: id,
          titleName: agentRowName(row),
        ),
      ),
    );
  }

  Future<void> _openShare(Map<String, dynamic> row) async {
    final id = agentRowAccountId(row);
    if (id == null || !agentRowIsAgent(row)) {
      AppToast.error('仅代理可设置占成');
      return;
    }
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => AgentChildSharePage(accountId: id, title: agentRowName(row)),
      ),
    );
    if (changed == true && mounted) await _load();
  }

  Future<void> _openOdds(Map<String, dynamic> row) async {
    final id = agentRowAccountId(row);
    if (id == null || agentRowIsDelegate(row)) {
      AppToast.error('当前类型不可设置赔率');
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AgentChildOddsPage(accountId: id, title: agentOddsSubjectTitle(row)),
      ),
    );
  }

  Future<void> _openLogs(Map<String, dynamic> row) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => AgentChildLogsPage(row: row)),
    );
  }

  void _viewChildren(Map<String, dynamic> row) {
    if (!agentRowIsAgent(row)) {
      AppToast.error('仅代理可查看下级');
      return;
    }
    _drillInto(row, childType: 'ALL');
  }

  /// 徽章：几级代理 / 代理会员 / 子账号
  String _typeBadgeLabel(Map<String, dynamic> row) => agentAccountTypeLabel(row);

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

  Widget _accountCard(Map<String, dynamic> r) {
    final username = '${r['username'] ?? ''}';
    final name = agentRowName(r);
    final status = agentAccountStatusLabel(r['status']?.toString());
    final isAgent = agentRowIsAgent(r);
    final id = agentRowAccountId(r);
    final nick = '${r['displayName'] ?? ''}'.trim();
    final showNick = nick.isNotEmpty && nick != username;
    final canShare = isAgent;
    final canOdds = !agentRowIsDelegate(r);
    final canChildren = isAgent;

    return AgentSurface(
      padding: EdgeInsets.fromLTRB(10.w, 10.h, 10.w, 10.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 3.h),
                decoration: BoxDecoration(
                  color: _typeGreen.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(4.r),
                ),
                child: Text(
                  _typeBadgeLabel(r),
                  style: TextStyle(fontSize: 12.sp, color: const Color(0xFF2E7D32), fontWeight: FontWeight.w600),
                ),
              ),
              const Spacer(),
              Flexible(
                child: Text(
                  username.isEmpty ? name : username,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w700, color: AgentChrome.ink),
                ),
              ),
              SizedBox(width: 6.w),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 2.h),
                decoration: BoxDecoration(
                  color: _statusBlue.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(4.r),
                ),
                child: Text(status, style: TextStyle(fontSize: 11.sp, color: const Color(0xFF1565C0))),
              ),
            ],
          ),
          SizedBox(height: 6.h),
          Row(
            children: [
              Expanded(
                child: Text(
                  'ID: ${id ?? '—'}',
                  style: TextStyle(fontSize: 13.sp, color: AgentChrome.ink),
                ),
              ),
              if (showNick)
                Text(
                  nick,
                  textAlign: TextAlign.right,
                  style: TextStyle(fontSize: 13.sp, color: AgentChrome.ink),
                ),
            ],
          ),
          SizedBox(height: 4.h),
          Row(
            children: [
              Expanded(
                child: Text(
                  '额度: ${agentBalanceLabel(r['balance'])}',
                  style: TextStyle(fontSize: 13.sp, color: AgentChrome.ink),
                ),
              ),
              Expanded(
                child: Text(
                  '下级额度: ${isAgent ? agentBalanceLabel(r['subordinateBalance']) : '0'}',
                  textAlign: TextAlign.right,
                  style: TextStyle(fontSize: 13.sp, color: AgentChrome.ink),
                ),
              ),
            ],
          ),
          SizedBox(height: 10.h),
          _actionGrid([
            _ActionBtn('上分', _btnGreen, () => _openCredit(r, direction: 'UP')),
            _ActionBtn('积分明细', _btnCoral, () => _openQuota(r)),
            _ActionBtn('编辑', _btnGreen, () => _openSettings(r)),
            _ActionBtn('下分', _btnCoral, () => _openCredit(r, direction: 'DOWN')),
            _ActionBtn('日志', _btnTeal, () => _openLogs(r)),
            _ActionBtn('设置占成', _btnTeal, canShare ? () => _openShare(r) : null),
            _ActionBtn('设置赔率', _btnTeal, canOdds ? () => _openOdds(r) : null),
            _ActionBtn('查看下级', _btnTeal, canChildren ? () => _viewChildren(r) : null),
          ]),
        ],
      ),
    );
  }

  Widget _actionGrid(List<_ActionBtn> buttons) {
    return Column(
      children: [
        for (var row = 0; row < 2; row++) ...[
          if (row > 0) SizedBox(height: 6.h),
          Row(
            children: [
              for (var col = 0; col < 4; col++) ...[
                if (col > 0) SizedBox(width: 6.w),
                Expanded(child: _actionButton(buttons[row * 4 + col])),
              ],
            ],
          ),
        ],
      ],
    );
  }

  Widget _actionButton(_ActionBtn btn) {
    final enabled = btn.onTap != null;
    return Material(
      color: enabled ? btn.color : btn.color.withValues(alpha: 0.35),
      borderRadius: BorderRadius.circular(6.r),
      child: InkWell(
        onTap: btn.onTap,
        borderRadius: BorderRadius.circular(6.r),
        child: SizedBox(
          height: 32.h,
          child: Center(
            child: Text(
              btn.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11.sp, color: Colors.white, fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ),
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
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    height: 36.h,
                    padding: EdgeInsets.symmetric(horizontal: 10.w),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(4.r),
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
                ),
                SizedBox(width: 6.w),
                AgentTealButton(
                  label: '搜索',
                  onTap: () {
                    _page = 1;
                    _load();
                  },
                ),
                SizedBox(width: 6.w),
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
                SizedBox(width: 6.w),
                AgentTealButton(label: '新增', onTap: _showCreate),
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

class _ActionBtn {
  const _ActionBtn(this.label, this.color, this.onTap);
  final String label;
  final Color color;
  final VoidCallback? onTap;
}
