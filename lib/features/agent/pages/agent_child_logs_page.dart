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
  bool _loadingMore = false;
  List<Map<String, dynamic>> _loginRows = [];
  List<Map<String, dynamic>> _opRows = [];
  int _loginPage = 1;
  int _opPage = 1;
  bool _loginMore = true;
  bool _opMore = true;
  static const _pageSize = 50;

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

  Future<void> _load({bool reset = true, int? tab}) async {
    final id = agentRowAccountId(widget.row);
    if (id == null) return;
    final which = tab ?? _tabs.index;
    if (!reset) {
      if (_loadingMore || _loading) return;
      if (which == 0 && !_loginMore) return;
      if (which == 1 && !_opMore) return;
      setState(() => _loadingMore = true);
    } else {
      setState(() {
        _loading = true;
        _loginPage = 1;
        _opPage = 1;
        _loginMore = true;
        _opMore = true;
      });
    }
    final loginPage = reset || which != 0 ? _loginPage : _loginPage + 1;
    final opPage = reset || which != 1 ? _opPage : _opPage + 1;
    try {
      final repo = ref.read(agentRepositoryProvider);
      if (reset || which == 0) {
        final login = await repo.getLoginLogs(accountId: id, pageNum: reset ? 1 : loginPage, pageSize: _pageSize);
        if (!mounted) return;
        final rows = _rowsOf(login);
        final total = int.tryParse('${login['total'] ?? rows.length}') ?? rows.length;
        setState(() {
          _loginRows = reset ? rows : [..._loginRows, ...rows];
          _loginPage = reset ? 1 : loginPage;
          _loginMore = _loginRows.length < total && rows.isNotEmpty;
        });
      }
      if (reset || which == 1) {
        final ops = await repo.getOpLogs(accountId: id, pageNum: reset ? 1 : opPage, pageSize: _pageSize);
        if (!mounted) return;
        final rows = _rowsOf(ops);
        final total = int.tryParse('${ops['total'] ?? rows.length}') ?? rows.length;
        setState(() {
          _opRows = reset ? rows : [..._opRows, ...rows];
          _opPage = reset ? 1 : opPage;
          _opMore = _opRows.length < total && rows.isNotEmpty;
        });
      }
      if (mounted) {
        setState(() {
          _loading = false;
          _loadingMore = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadingMore = false;
      });
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
      title: '',
      onRefresh: _load,
      child: Column(
        children: [
          AgentBackTitle(title: title),
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
      itemCount: _loginRows.length + 1,
      separatorBuilder: (_, i) => i >= _loginRows.length - 1 ? const SizedBox.shrink() : SizedBox(height: 8.h),
      itemBuilder: (_, i) {
        if (i == _loginRows.length) {
          if (_loginMore && !_loadingMore) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _load(reset: false, tab: 0);
            });
          }
          return Padding(
            padding: EdgeInsets.only(top: 8.h),
            child: Center(child: Text(_loginMore ? '加载中' : '没有更多了', style: TextStyle(fontSize: 12.sp, color: AppColors.textHint))),
          );
        }
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
      itemCount: _opRows.length + 1,
      separatorBuilder: (_, i) => i >= _opRows.length - 1 ? const SizedBox.shrink() : SizedBox(height: 8.h),
      itemBuilder: (_, i) {
        if (i == _opRows.length) {
          if (_opMore && !_loadingMore) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _load(reset: false, tab: 1);
            });
          }
          return Padding(
            padding: EdgeInsets.only(top: 8.h),
            child: Center(child: Text(_opMore ? '加载中' : '没有更多了', style: TextStyle(fontSize: 12.sp, color: AppColors.textHint))),
          );
        }
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
