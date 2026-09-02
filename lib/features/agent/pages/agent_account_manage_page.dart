import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../config/theme/app_colors.dart';
import '../../../data/repositories/providers.dart';
import '../../../shared/widgets/emulator_safe_text_field.dart';
import '../../../shared/widgets/page_app_bar.dart';
import '../widgets/agent_ui.dart';

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

  Future<void> _showCreate() async {
    final userCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    var type = 'AGENT_MEMBER';
    const accountTypeLabels = {
      'AGENT_MEMBER': '会员',
      'AGENT': '代理',
      'AGENT_DELEGATE': '协管',
    };
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text('新增账户', style: TextStyle(fontSize: 16.sp)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                EmulatorSafeTextField(
                  controller: userCtrl,
                  decoration: const InputDecoration(labelText: '用户名'),
                ),
                EmulatorSafeTextField(
                  controller: passCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: '密码'),
                ),
                EmulatorSafeTextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: '显示名称'),
                ),
                DropdownButton<String>(
                  value: type,
                  isExpanded: true,
                  items: [
                    for (final entry in accountTypeLabels.entries)
                      DropdownMenuItem(value: entry.key, child: Text(entry.value)),
                  ],
                  onChanged: (v) => setLocal(() => type = v ?? type),
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
    if (ok != true) return;
    try {
      await ref.read(agentRepositoryProvider).createAccount(
            username: userCtrl.text.trim(),
            password: passCtrl.text,
            accountType: type,
            displayName: nameCtrl.text.trim().isEmpty ? null : nameCtrl.text.trim(),
          );
      AppToast.success('\u521b\u5efa\u6210\u529f');
      _page = 1;
      await _load();
    } catch (e) {
      AppToast.error(e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return AgentPageFrame(
      title: '\u8d26\u6237\u7ba1\u7406',
      child: Column(
        children: [
          Expanded(
            child: AgentBorderBox(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: Container(
                          height: 36.h,
                          padding: EdgeInsets.symmetric(horizontal: 8.w),
                          decoration: BoxDecoration(border: Border.all(color: const Color(0xFFAAAAAA))),
                          child: EmulatorSafeTextField(
                            controller: _searchCtrl,
                            decoration: InputDecoration(
                              border: InputBorder.none,
                              hintText: '\u8d26\u6237\u641c\u7d22',
                              hintStyle: TextStyle(fontSize: 13.sp, color: AppColors.textHint),
                              isDense: true,
                            ),
                          ),
                        ),
                      ),
                      SizedBox(width: 4.w),
                      AgentTealButton(
                        label: '\u641c\u7d22',
                        onTap: () {
                          _page = 1;
                          _load();
                        },
                      ),
                      SizedBox(width: 4.w),
                      AgentTealButton(
                        label: '\u67e5\u770b\u5168\u90e8',
                        outlined: true,
                        onTap: () {
                          _searchCtrl.clear();
                          _page = 1;
                          _load();
                        },
                      ),
                      SizedBox(width: 4.w),
                      AgentTealButton(label: '\u65b0\u589e', onTap: _showCreate),
                    ],
                  ),
                  SizedBox(height: 10.h),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(border: Border.all(color: const Color(0xFFAAAAAA))),
                      child: _loading
                          ? const Center(child: CircularProgressIndicator())
                          : _error != null
                              ? Center(
                                  child: GestureDetector(
                                    onTap: _load,
                                    child: Text(
                                      '加载失败，点击重试',
                                      style: TextStyle(fontSize: 14.sp, color: AppColors.danger),
                                    ),
                                  ),
                                )
                              : _rows.isEmpty
                                  ? Center(
                                      child: Text(
                                        '暂无数据',
                                        style: TextStyle(fontSize: 14.sp, color: AppColors.textHint),
                                      ),
                                    )
                                  : ListView.separated(
                                      itemCount: _rows.length,
                                      separatorBuilder: (_, _) => const Divider(height: 1),
                                      itemBuilder: (_, i) {
                                        final r = _rows[i];
                                        return ListTile(
                                          dense: true,
                                          title: Text(
                                            '${r['displayName'] ?? r['username'] ?? ''}',
                                            style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600),
                                          ),
                                          subtitle: Text(
                                            '${r['username'] ?? ''} · ${agentAccountTypeLabel(r)} · ${agentAccountStatusLabel(r['status']?.toString())}',
                                            style: TextStyle(fontSize: 11.sp),
                                          ),
                                          trailing: Text(
                                            agentBalanceLabel(r['balance']),
                                            style: TextStyle(fontSize: 12.sp),
                                          ),
                                        );
                                      },
                                    ),
                    ),
                  ),
                  AgentPaginationBar(
                    compact: true,
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
            ),
          ),
          SizedBox(height: 8.h),
        ],
      ),
    );
  }
}
