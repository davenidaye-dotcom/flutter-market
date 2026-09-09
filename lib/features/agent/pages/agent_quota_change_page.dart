import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../config/theme/app_colors.dart';
import '../../../data/repositories/providers.dart';
import '../../../shared/widgets/page_app_bar.dart';
import '../widgets/agent_ui.dart';

class AgentQuotaChangePage extends ConsumerStatefulWidget {
  const AgentQuotaChangePage({super.key, required this.roomId});

  final String roomId;

  @override
  ConsumerState<AgentQuotaChangePage> createState() =>
      _AgentQuotaChangePageState();
}

class _AgentQuotaChangePageState extends ConsumerState<AgentQuotaChangePage> {
  int _quick = 0;
  int _typeIndex = 0;
  int _page = 1;
  int _totalPages = 0;
  int _total = 0;
  bool _loading = false;
  DateTime _start = DateTime.now();
  DateTime _end = DateTime.now();
  List<Map<String, dynamic>> _rows = [];
  Map<String, dynamic> _summary = {};

  static const _types = [
    '全部',
    '上分',
    '下分',
    '飞单占用',
    '占用释放',
    '结算赢',
    '结算输',
    '调整',
  ];
  static const _typeKeys = [
    'ALL',
    'UP',
    'DOWN',
    'FLIGHT_OCCUPY',
    'FLIGHT_RELEASE',
    'FLIGHT_SETTLE_WIN',
    'FLIGHT_SETTLE_LOSS',
    'ADJUST',
  ];

  String _changeTypeLabel(String? raw) {
    switch (raw?.toUpperCase()) {
      case 'UP':
        return '上分';
      case 'DOWN':
        return '下分';
      case 'FLIGHT_OCCUPY':
        return '飞单占用';
      case 'FLIGHT_RELEASE':
        return '占用释放';
      case 'FLIGHT_SETTLE_WIN':
        return '结算赢';
      case 'FLIGHT_SETTLE_LOSS':
        return '结算输';
      case 'ADJUST':
        return '调整';
      default:
        return raw?.isNotEmpty == true ? raw! : '—';
    }
  }

  String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _start = _end = DateTime(now.year, now.month, now.day);
    Future.microtask(_load);
  }

  Future<void> _pickDate({required bool isStart}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isStart ? _start : _end,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (isStart) {
        _start = picked;
      } else {
        _end = picked;
      }
    });
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await ref.read(agentRepositoryProvider).getCreditChanges(
            startDate: _fmt(_start),
            endDate: _fmt(_end),
            changeType: _typeKeys[_typeIndex],
            pageNum: _page,
            pageSize: 20,
          );
      if (!mounted) return;
      final raw = data['rows'];
      final rows = raw is List
          ? raw
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList()
          : <Map<String, dynamic>>[];
      final total =
          data['total'] is num ? (data['total'] as num).toInt() : rows.length;
      final pageSize =
          data['pageSize'] is num ? (data['pageSize'] as num).toInt() : 20;
      final summary = data['summary'] is Map
          ? Map<String, dynamic>.from(data['summary'] as Map)
          : <String, dynamic>{};
      setState(() {
        _rows = rows;
        _total = total;
        _totalPages =
            pageSize <= 0 ? 0 : ((total + pageSize - 1) ~/ pageSize);
        _summary = summary;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      AppToast.error(e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return AgentPageFrame(
      title: '',
      child: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(12.w, 8.h, 12.w, 4.h),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '\u989d\u5ea6\u53d8\u52a8',
                  style: TextStyle(
                    fontSize: 14.sp,
                    color: AppColors.textSecondary,
                  ),
                ),
                SizedBox(width: 16.w),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '给下级上分:${_summary['creditToSubUp'] ?? 0}',
                        style: TextStyle(fontSize: 13.sp),
                      ),
                      SizedBox(height: 4.h),
                      Text(
                        '给下级下分:${_summary['creditToSubDown'] ?? 0}',
                        style: TextStyle(fontSize: 13.sp),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '上级上分:${_summary['creditFromParentUp'] ?? 0}',
                        style: TextStyle(fontSize: 13.sp, color: Colors.red),
                      ),
                      SizedBox(height: 4.h),
                      Text(
                        '上级下分:${_summary['creditFromParentDown'] ?? 0}',
                        style: TextStyle(fontSize: 13.sp, color: Colors.red),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: AgentBorderBox(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _dateField(_start, () => _pickDate(isStart: true)),
                      ),
                      SizedBox(width: 8.w),
                      Expanded(
                        child: _dateField(_end, () => _pickDate(isStart: false)),
                      ),
                    ],
                  ),
                  SizedBox(height: 10.h),
                  Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: GestureDetector(
                          onTap: () async {
                            final i = await showModalBottomSheet<int>(
                              context: context,
                              backgroundColor: Colors.white,
                              builder: (ctx) {
                                return Material(
                                  color: Colors.white,
                                  child: SafeArea(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        for (var j = 0; j < _types.length; j++)
                                          ListTile(
                                            tileColor: Colors.white,
                                            title: Text(_types[j]),
                                            onTap: () => Navigator.pop(ctx, j),
                                          ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            );
                            if (i != null) setState(() => _typeIndex = i);
                          },
                          child: Container(
                            height: 36.h,
                            padding: EdgeInsets.symmetric(horizontal: 10.w),
                            decoration: BoxDecoration(
                              border: Border.all(color: const Color(0xFFAAAAAA)),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    _types[_typeIndex],
                                    style: TextStyle(fontSize: 13.sp),
                                  ),
                                ),
                                Icon(Icons.arrow_drop_down, size: 20.sp),
                              ],
                            ),
                          ),
                        ),
                      ),
                      SizedBox(width: 4.w),
                      AgentQuotaQuickBtn(
                        label: '\u4eca\u5929',
                        active: _quick == 0,
                        blue: true,
                        onTap: () {
                          final n = DateTime.now();
                          setState(() {
                            _quick = 0;
                            _start = _end = DateTime(n.year, n.month, n.day);
                          });
                        },
                      ),
                      SizedBox(width: 4.w),
                      AgentQuotaQuickBtn(
                        label: '\u6628\u5929',
                        active: _quick == 1,
                        onTap: () {
                          final y =
                              DateTime.now().subtract(const Duration(days: 1));
                          setState(() {
                            _quick = 1;
                            _start = _end = DateTime(y.year, y.month, y.day);
                          });
                        },
                      ),
                      SizedBox(width: 4.w),
                      AgentTealButton(
                        label: '\u67e5\u8be2',
                        onTap: () {
                          _page = 1;
                          _load();
                        },
                      ),
                    ],
                  ),
                  SizedBox(height: 12.h),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: const Color(0xFFCCCCCC)),
                      ),
                      child: _loading
                          ? const Center(child: CircularProgressIndicator())
                          : _rows.isEmpty
                              ? Center(
                                  child: Text(
                                    '\u6682\u65e0\u6570\u636e',
                                    style: TextStyle(
                                      fontSize: 14.sp,
                                      color: AppColors.textHint,
                                    ),
                                  ),
                                )
                              : ListView.separated(
                                  itemCount: _rows.length,
                                  separatorBuilder: (_, _) =>
                                      const Divider(height: 1),
                                  itemBuilder: (_, i) {
                                    final r = _rows[i];
                                    return ListTile(
                                      dense: true,
                                      title: Text(
                                        '${_changeTypeLabel('${r['changeType'] ?? ''}')}  ${r['amount'] ?? ''}',
                                        style: TextStyle(fontSize: 13.sp),
                                      ),
                                      subtitle: Text(
                                        '总额后:${r['totalAfter'] ?? '—'}  占用后:${r['occupiedAfter'] ?? '—'}  ${r['createdAt'] ?? ''}',
                                        style: TextStyle(fontSize: 11.sp),
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

  Widget _dateField(DateTime d, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 36.h,
        padding: EdgeInsets.symmetric(horizontal: 8.w),
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFFAAAAAA)),
        ),
        child: Row(
          children: [
            Icon(Icons.access_time, size: 16.sp, color: AppColors.textHint),
            SizedBox(width: 6.w),
            Text(_fmt(d), style: TextStyle(fontSize: 13.sp)),
          ],
        ),
      ),
    );
  }
}
