import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../config/theme/app_colors.dart';
import '../../../data/repositories/providers.dart';
import '../../../shared/format/display_number.dart';
import '../../../shared/widgets/page_app_bar.dart';
import '../../wallet/widgets/date_range_filter.dart';
import '../widgets/agent_ui.dart';
import '../../../shared/widgets/app_page_loading.dart';

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
  late DateTime _start;
  late DateTime _end;
  List<DateRangeQuickItem> _dayQuick = const [];
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

  String _fmt(DateTime d) => DateRangeFilter.format(d);

  String _shown(dynamic v) {
    if (v == null) return '—';
    final s = '$v'.trim();
    if (s.isEmpty) return '—';
    return displayNumber(v);
  }

  List<DateRangeQuickItem> _dayQuickItems() {
    return DateRangeFilter.buildQuickItems()
        .where((e) => e.label == '今日' || e.label == '昨日')
        .toList();
  }

  @override
  void initState() {
    super.initState();
    _dayQuick = _dayQuickItems();
    _quick = 0;
    _start = _end = _dayQuick[0].start;
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
      title: '额度变动',
      child: Column(
        children: [
          SizedBox(height: 8.h),
          AgentSurface(
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(child: AgentMetric(label: '给下级上分', value: _summary['creditToSubUp'], alignStart: true)),
                    Expanded(child: AgentMetric(label: '给下级下分', value: _summary['creditToSubDown'], alignStart: true)),
                  ],
                ),
                SizedBox(height: 12.h),
                Row(
                  children: [
                    Expanded(child: AgentMetric(label: '上级上分', value: _summary['creditFromParentUp'], alignStart: true)),
                    Expanded(child: AgentMetric(label: '上级下分', value: _summary['creditFromParentDown'], alignStart: true)),
                  ],
                ),
              ],
            ),
          ),
          SizedBox(height: 8.h),
          AgentSurface(
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(child: _dateField(_start, () => _pickDate(isStart: true))),
                    SizedBox(width: 8.w),
                    Expanded(child: _dateField(_end, () => _pickDate(isStart: false))),
                  ],
                ),
                SizedBox(height: 10.h),
                Row(
                  children: [
                    Expanded(child: _typeField()),
                    SizedBox(width: 8.w),
                    for (var i = 0; i < _dayQuick.length; i++) ...[
                      if (i > 0) SizedBox(width: 6.w),
                      _quickChip(i),
                    ],
                    SizedBox(width: 8.w),
                    AgentTealButton(
                      label: '查询',
                      onTap: () {
                        _page = 1;
                        _load();
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
          SizedBox(height: 8.h),
          Expanded(child: _changeList()),
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

  Widget _quickChip(int i) {
    final active = _quick == i;
    return GestureDetector(
      onTap: () {
        setState(() {
          _quick = i;
          _start = _end = _dayQuick[i].start;
        });
      },
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 8.h),
        decoration: BoxDecoration(
          color: active ? AgentChrome.accent : Colors.white,
          borderRadius: BorderRadius.circular(8.r),
          border: Border.all(color: active ? AgentChrome.accent : AgentChrome.cardBorder),
        ),
        child: Text(
          _dayQuick[i].label,
          style: TextStyle(fontSize: 12.sp, color: active ? Colors.white : AppColors.textPrimary),
        ),
      ),
    );
  }

  Widget _typeField() {
    return GestureDetector(
      onTap: () async {
        final i = await showModalBottomSheet<int>(
          context: context,
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(16.r)),
          ),
          builder: (ctx) {
            return SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(height: 8.h),
                  for (var j = 0; j < _types.length; j++)
                    ListTile(
                      title: Text(_types[j]),
                      onTap: () => Navigator.pop(ctx, j),
                    ),
                ],
              ),
            );
          },
        );
        if (i != null) setState(() => _typeIndex = i);
      },
      child: Container(
        height: 40.h,
        padding: EdgeInsets.symmetric(horizontal: 10.w),
        decoration: BoxDecoration(
          color: AgentChrome.fieldBg,
          borderRadius: BorderRadius.circular(8.r),
          border: Border.all(color: AgentChrome.cardBorder),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(_types[_typeIndex], maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13.sp)),
            ),
            Icon(Icons.keyboard_arrow_down, size: 18.sp, color: AppColors.textHint),
          ],
        ),
      ),
    );
  }

  Widget _changeList() {
    if (_loading) return const AppPageLoading();
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
        final when = r['createdAt']?.toString() ?? '';
        return AgentSurface(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${_changeTypeLabel('${r['changeType'] ?? ''}')} ${displayNumber(r['amount'])}',
                style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w700, color: AgentChrome.ink),
              ),
              SizedBox(height: 4.h),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  '总额后 ${_shown(r['totalAfter'])} · 占用后 ${_shown(r['occupiedAfter'])} · $when',
                  maxLines: 1,
                  softWrap: false,
                  style: TextStyle(fontSize: 12.sp, color: AppColors.textSecondary),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _dateField(DateTime d, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 40.h,
        padding: EdgeInsets.symmetric(horizontal: 10.w),
        decoration: BoxDecoration(
          color: AgentChrome.fieldBg,
          borderRadius: BorderRadius.circular(8.r),
          border: Border.all(color: AgentChrome.cardBorder),
        ),
        child: Row(
          children: [
            Icon(Icons.calendar_today_outlined, size: 14.sp, color: AppColors.textHint),
            SizedBox(width: 6.w),
            Text(_fmt(d), style: TextStyle(fontSize: 13.sp)),
          ],
        ),
      ),
    );
  }
}
