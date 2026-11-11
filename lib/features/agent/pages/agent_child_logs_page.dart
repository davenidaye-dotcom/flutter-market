import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../config/theme/app_colors.dart';
import '../../../shared/format/game_series.dart';
import '../../../data/repositories/providers.dart';
import '../../auth/providers/auth_session_provider.dart';
import '../../../shared/widgets/app_page_loading.dart';
import '../../../shared/widgets/page_app_bar.dart';
import '../widgets/agent_ui.dart';
import 'agent_account_child_page.dart';

/// 下级登录日志 + 操作日志
class AgentChildLogsPage extends ConsumerStatefulWidget {
  const AgentChildLogsPage({super.key, required this.row}) : self = false;

  const AgentChildLogsPage.self({super.key})
      : row = const {},
        self = true;

  final Map<String, dynamic> row;
  final bool self;

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
  List<Map<String, dynamic>> _changeRows = [];
  int _changePage = 1;
  bool _changeMore = true;
  bool _changeReady = false;
  String _changeKind = 'ALL';
  static const _pageSize = 50;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _tabs.addListener(_onTab);
    Future.microtask(_load);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  void _onTab() {
    if (_tabs.indexIsChanging || _tabs.index != 2 || _changeReady || _loading) return;
    _load(reset: true, tab: 2);
  }

  Future<void> _load({bool reset = true, int? tab}) async {
    final id = widget.self ? null : agentRowAccountId(widget.row);
    if (!widget.self && id == null) return;
    final which = tab ?? _tabs.index;
    final changesOnly = which == 2;
    if (!reset) {
      if (_loadingMore || _loading) return;
      if (which == 0 && !_loginMore) return;
      if (which == 1 && !_opMore) return;
      if (which == 2 && !_changeMore) return;
      setState(() => _loadingMore = true);
    } else if (changesOnly) {
      setState(() {
        _loading = true;
        _changePage = 1;
        _changeMore = true;
      });
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
    final changePage = !reset && which == 2 ? _changePage + 1 : 1;
    try {
      final repo = ref.read(agentRepositoryProvider);
      if (!changesOnly && (reset || which == 0)) {
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
      if (!changesOnly && (reset || which == 1)) {
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
      if (changesOnly) {
        final requestedKind = _changeKind;
        final data = await repo.getChangeLogs(
          type: requestedKind,
          accountId: id,
          pageNum: changePage,
          pageSize: _pageSize,
        );
        if (!mounted || requestedKind != _changeKind) return;
        final rows = _rowsOf(data);
        final total = int.tryParse('${data['total'] ?? rows.length}') ?? rows.length;
        setState(() {
          _changeRows = reset ? rows : [..._changeRows, ...rows];
          _changePage = changePage;
          _changeMore = _changeRows.length < total && rows.isNotEmpty;
          _changeReady = true;
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
    final title = widget.self ? '我的日志' : '日志 · ${maskAgentName(agentRowName(widget.row))}';
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
              Tab(text: '修改日志'),
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
                      _changeTab(),
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
      padding: EdgeInsets.fromLTRB(12.w, 8.h, 12.w, 12.h),
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
        final username = _showName(r['username']);
        final nick = _showName(r['displayName']);
        final status = _text(r['sessionStatus']);
        return _LogCard(
          title: username == '—' ? '登录' : username,
          time: _text(r['loginAt']),
          badge: status.isEmpty ? null : status,
          badgeColor: _statusColor(status),
          rows: [
            if (nick != '—' && nick != username) ('昵称', nick),
            ('登录渠道', _orDash(r['loginChannel'])),
            ('登录IP', _orDash(r['clientIp'])),
            ('IP归属', _orDash(r['ipRegion'])),
            ('设备', _orDash(r['device'])),
            ('会话', _orDash(r['sessionMode'])),
          ],
        );
      },
    );
  }

  Widget _opList() {
    if (_opRows.isEmpty) {
      return Center(child: Text('暂无操作日志', style: TextStyle(fontSize: 14.sp, color: AppColors.textHint)));
    }
    return ListView.separated(
      padding: EdgeInsets.fromLTRB(12.w, 8.h, 12.w, 12.h),
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
        final user = widget.self ? ref.read(authSessionProvider).user : null;
        final names = <String>[
          if (user != null) user.username,
          if (user != null) user.nickname,
          if (!widget.self) agentRowName(widget.row),
          if (!widget.self) '${widget.row['username'] ?? ''}',
          _text(r['operator']),
          _text(r['targetAccount']),
          _text(r['targetName']),
          _text(r['username']),
          _text(r['displayName']),
        ];
        final target = _showName(r['targetAccount']);
        final nick = _showName(r['targetName']);
        final result = _text(r['result']);
        final opType = _maskText(_text(r['opType']), names);
        return _LogCard(
          title: opType.isEmpty ? '操作' : opType,
          time: _text(r['operTime']),
          badge: result.isEmpty ? null : result,
          badgeColor: result == '失败' ? AppColors.danger : const Color(0xFF2E9E5B),
          rows: [
            ('操作内容', _maskText(_orDash(r['content']), names)),
            ('被改账号', target),
            if (nick != '—' && nick != target) ('昵称', nick),
            if (_text(r['oldValue']).isNotEmpty) ('操作前', _maskText(_text(r['oldValue']), names)),
            if (_text(r['newValue']).isNotEmpty) ('操作后', _maskText(_text(r['newValue']), names)),
            if (_text(r['remark']).isNotEmpty) ('备注', _maskText(_text(r['remark']), names)),
            ('操作人', _showName(r['operator'])),
            ('操作IP', _orDash(r['clientIp'])),
            ('IP归属', _orDash(r['ipRegion'])),
            if (_text(r['errorMsg']).isNotEmpty) ('失败原因', _maskText(_text(r['errorMsg']), names)),
          ],
        );
      },
    );
  }
}

  Widget _changeTab() {
    return Column(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(12.w, 8.h, 12.w, 0),
          child: Row(
            children: [
              _kindChip('ALL', '全部'),
              SizedBox(width: 8.w),
              _kindChip('ODDS', '赔率'),
              SizedBox(width: 8.w),
              _kindChip('SHARE', '占成'),
            ],
          ),
        ),
        Expanded(child: _changeList()),
      ],
    );
  }

  Widget _kindChip(String kind, String label) {
    final on = _changeKind == kind;
    return GestureDetector(
      onTap: () {
        if (on || _loading) return;
        setState(() {
          _changeKind = kind;
          _changeReady = false;
        });
        _load(reset: true, tab: 2);
      },
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 4.h),
        decoration: BoxDecoration(
          color: on ? AppColors.navBlue.withValues(alpha: 0.12) : const Color(0x00000000),
          borderRadius: BorderRadius.circular(12.r),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13.sp,
            fontWeight: on ? FontWeight.w600 : FontWeight.normal,
            color: on ? AppColors.navBlue : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _changeList() {
    if (_changeRows.isEmpty) {
      return Center(child: Text('暂无修改日志', style: TextStyle(fontSize: 14.sp, color: AppColors.textHint)));
    }
    return ListView.separated(
      padding: EdgeInsets.fromLTRB(12.w, 8.h, 12.w, 12.h),
      itemCount: _changeRows.length + 1,
      separatorBuilder: (_, i) => i >= _changeRows.length - 1 ? const SizedBox.shrink() : SizedBox(height: 8.h),
      itemBuilder: (_, i) {
        if (i == _changeRows.length) {
          if (_changeMore && !_loadingMore) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _load(reset: false, tab: 2);
            });
          }
          return Padding(
            padding: EdgeInsets.only(top: 8.h),
            child: Center(child: Text(_changeMore ? '加载中' : '没有更多了', style: TextStyle(fontSize: 12.sp, color: AppColors.textHint))),
          );
        }
        final r = _changeRows[i];
        final odds = '${r['type']}' == 'ODDS';
        final play = _text(r['playCode']);
        final game = GameSeries.displayName(_text(r['gameType']));
        final rows = <(String, String)>[
          if (odds) ('改前', _orDash(r['oldValue'])),
          if (odds) ('改后', _orDash(r['newValue'])),
          if (!odds) ('改前占成', _pct(r['oldValue'])),
          if (!odds) ('改后占成', _pct(r['newValue'])),
          if (!odds && (_text(r['oldCap']).isNotEmpty || _text(r['newCap']).isNotEmpty)) ('改前上限', _pct(r['oldCap'])),
          if (!odds && (_text(r['oldCap']).isNotEmpty || _text(r['newCap']).isNotEmpty)) ('改后上限', _pct(r['newCap'])),
          ('操作人', _showName(r['actor'])),
        ];
        return _LogCard(
          title: odds ? (play.isEmpty ? '赔率' : '赔率 · $play') : '占成',
          time: _text(r['changedAt']),
          badge: game.isEmpty ? null : game,
          badgeColor: AppColors.navBlue,
          rows: rows,
        );
      },
    );
  }

/// 代理名称：保留前两位和后两位，中间用 **。不足四位时保留首尾各一位。
String maskAgentName(String raw) {
  final s = raw.trim();
  if (s.isEmpty || s == '-' || s == '—') return s.isEmpty ? '—' : s;
  final chars = s.characters.toList();
  final n = chars.length;
  if (n <= 2) return s;
  if (n < 4) return '${chars.first}**${chars.last}';
  return '${chars.sublist(0, 2).join()}**${chars.sublist(n - 2).join()}';
}

String _text(dynamic v) => v == null ? '' : '$v'.trim();

String _orDash(dynamic v) {
  final s = _text(v);
  return s.isEmpty || s == '-' ? '—' : s;
}

String _pct(dynamic v) {
  final s = _text(v);
  if (s.isEmpty || s == '-') return '—';
  final n = num.tryParse(s);
  if (n == null) return s;
  final shown = n.abs() <= 1 ? n * 100 : n;
  final text = shown == shown.roundToDouble() ? shown.toInt().toString() : shown.toString();
  return '$text%';
}

String _showName(dynamic v) => maskAgentName(_text(v));

String _maskText(String text, List<String> names) {
  if (text.isEmpty) return text;
  final list = names.map((e) => e.trim()).where((e) => e.length >= 3).toSet().toList()
    ..sort((a, b) => b.length.compareTo(a.length));
  var out = text;
  for (final name in list) {
    if (out.contains(name)) out = out.replaceAll(name, maskAgentName(name));
  }
  return out;
}

Color _statusColor(String status) {
  return switch (status) {
    '在线' || '成功' => const Color(0xFF2E9E5B),
    '失败' => AppColors.danger,
    '已过期' => const Color(0xFFE6A23C),
    _ => AppColors.textSecondary,
  };
}

class _LogCard extends StatelessWidget {
  const _LogCard({
    required this.title,
    required this.time,
    required this.rows,
    this.badge,
    this.badgeColor,
  });

  final String title;
  final String time;
  final String? badge;
  final Color? badgeColor;
  final List<(String, String)> rows;

  @override
  Widget build(BuildContext context) {
    final badgeText = badge?.trim() ?? '';
    return AgentSurface(
      margin: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w600, color: AgentChrome.ink),
                ),
              ),
              if (badgeText.isNotEmpty) ...[
                SizedBox(width: 8.w),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 2.h),
                  decoration: BoxDecoration(
                    color: (badgeColor ?? AppColors.textSecondary).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10.r),
                  ),
                  child: Text(
                    badgeText,
                    style: TextStyle(
                      fontSize: 11.sp,
                      fontWeight: FontWeight.w600,
                      color: badgeColor ?? AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ],
          ),
          if (time.isNotEmpty) ...[
            SizedBox(height: 4.h),
            Text(time, style: TextStyle(fontSize: 12.sp, color: AppColors.textSecondary)),
          ],
          Padding(
            padding: EdgeInsets.only(top: 8.h, bottom: 4.h),
            child: const Divider(height: 1, color: AppColors.divider),
          ),
          for (final row in rows) ...[
            Padding(
              padding: EdgeInsets.only(top: 4.h),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 68.w,
                    child: Text(row.$1, style: TextStyle(fontSize: 12.sp, color: AppColors.textSecondary, height: 1.35)),
                  ),
                  Expanded(
                    child: Text(
                      row.$2,
                      style: TextStyle(fontSize: 13.sp, color: AgentChrome.ink, height: 1.35),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
