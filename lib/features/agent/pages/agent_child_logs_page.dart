import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../config/theme/app_colors.dart';
import '../../../data/repositories/providers.dart';
import '../../../shared/widgets/app_page_loading.dart';
import '../../../shared/widgets/page_app_bar.dart';
import '../widgets/agent_ui.dart';
import 'agent_account_child_page.dart';

/// 下级登录日志 + 操作日志
class AgentChildLogsPage extends ConsumerStatefulWidget {
  const AgentChildLogsPage({super.key, required this.row});

  final Map<String, dynamic> row;

  @override
  ConsumerState<AgentChildLogsPage> createState() => _AgentChildLogsPageState();
}

class _AgentChildLogsPageState extends ConsumerState<AgentChildLogsPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  bool _loading = false;
  List<Map<String, dynamic>> _loginRows = [];
  List<Map<String, dynamic>> _opRows = [];

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    Future.microtask(_load);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final id = agentRowAccountId(widget.row);
    if (id == null) return;
    setState(() => _loading = true);
    try {
      final repo = ref.read(agentRepositoryProvider);
      final login = await repo.getLoginLogs(accountId: id, pageSize: 50);
      final ops = await repo.getOpLogs(accountId: id, pageSize: 50);
      if (!mounted) return;
      setState(() {
        _loginRows = _rowsOf(login);
        _opRows = _rowsOf(ops);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      AppToast.error(e.toString());
    }
  }

  List<Map<String, dynamic>> _rowsOf(Map<String, dynamic> data) {
    final raw = data['rows'];
    if (raw is! List) return [];
    return raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final title = '日志 · ${agentRowName(widget.row)}';
    return AgentPageFrame(
      title: title,
      onRefresh: _load,
      child: Column(
        children: [
          TabBar(
            controller: _tabs,
            labelColor: AppColors.navBlue,
            unselectedLabelColor: AppColors.textSecondary,
            indicatorColor: AppColors.navBlue,
            tabs: const [
              Tab(text: '登录日志'),
              Tab(text: '操作日志'),
            ],
          ),
          Expanded(
            child: _loading
                ? const AppPageLoading()
                : TabBarView(
                    controller: _tabs,
                    children: [
                      _loginList(),
                      _opList(),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _loginList() {
    if (_loginRows.isEmpty) {
      return Center(child: Text('暂无登录日志', style: TextStyle(fontSize: 14.sp, color: AppColors.textHint)));
    }
    return ListView.separated(
      padding: EdgeInsets.all(12.w),
      itemCount: _loginRows.length,
      separatorBuilder: (_, _) => SizedBox(height: 8.h),
      itemBuilder: (_, i) {
        final r = _loginRows[i];
        return AgentSurface(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${r['username'] ?? ''}', style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600)),
              SizedBox(height: 4.h),
              Text('${r['loginAt'] ?? ''}', style: TextStyle(fontSize: 12.sp, color: AppColors.textSecondary)),
              SizedBox(height: 2.h),
              Text(
                '${r['clientIp'] ?? ''} · ${r['ipRegion'] ?? ''}',
                style: TextStyle(fontSize: 12.sp, color: AppColors.textSecondary),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _opList() {
    if (_opRows.isEmpty) {
      return Center(child: Text('暂无操作日志', style: TextStyle(fontSize: 14.sp, color: AppColors.textHint)));
    }
    return ListView.separated(
      padding: EdgeInsets.all(12.w),
      itemCount: _opRows.length,
      separatorBuilder: (_, _) => SizedBox(height: 8.h),
      itemBuilder: (_, i) {
        final r = _opRows[i];
        return AgentSurface(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${r['opType'] ?? r['content'] ?? ''}',
                  style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600)),
              SizedBox(height: 4.h),
              Text('${r['operTime'] ?? ''}', style: TextStyle(fontSize: 12.sp, color: AppColors.textSecondary)),
              SizedBox(height: 2.h),
              Text(
                '操作人 ${r['operator'] ?? '—'}',
                style: TextStyle(fontSize: 12.sp, color: AppColors.textSecondary),
              ),
            ],
          ),
        );
      },
    );
  }
}
