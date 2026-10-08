import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../../config/theme/app_colors.dart';
import '../../../../data/repositories/providers.dart';
import '../../../../shared/format/display_number.dart';
import '../../../../shared/widgets/page_app_bar.dart';
import '../../../wallet/widgets/date_range_filter.dart';
import '../../data/host_mock.dart';
import '../../widgets/host_ui.dart';

String _feipanChangeTypeLabel(String? raw) {
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

/// Feipan points — GET /owner/feipan/points/changes
/// 含绑定代理会员 UP/DOWN + 本房飞单占用/释放/结算
class FlyBalancePage extends ConsumerStatefulWidget {
  const FlyBalancePage({super.key, required this.roomId});
  final String roomId;

  @override
  ConsumerState<FlyBalancePage> createState() => _FlyBalancePageState();
}

class _FlyBalancePageState extends ConsumerState<FlyBalancePage>
    with DateRangePageMixin {
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;
  bool _unbound = false;
  int _typeIndex = 0;

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

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  @override
  void onQuery() => _load();

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _unbound = false;
    });
    try {
      final repo = ref.read(ownerRepositoryProvider);
      final status = await repo.getFeipanStatus();
      if (status['bound'] != true) {
        if (!mounted) return;
        setState(() {
          _unbound = true;
          _rows = [];
          _loading = false;
        });
        return;
      }
      final data = await repo.getFeipanPointsChanges(
        changeType: _typeKeys[_typeIndex],
        startDate: DateRangeFilter.format(start),
        endDate: DateRangeFilter.format(end),
        pageSize: 50,
      );
      if (!mounted) return;
      setState(() {
        _rows = hostRowsOf(data);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      AppToast.error(e.toString());
    }
  }

  Widget _typeChips() {
    return SizedBox(
      height: 36.h,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: 12.w),
        itemCount: _types.length,
        separatorBuilder: (_, _) => SizedBox(width: 6.w),
        itemBuilder: (_, i) {
          final active = i == _typeIndex;
          return GestureDetector(
            onTap: () {
              if (_typeIndex == i) return;
              setState(() => _typeIndex = i);
              _load();
            },
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 12.w),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: active ? AppColors.navBlue : const Color(0xFFD6EBFA),
                borderRadius: BorderRadius.circular(14.r),
              ),
              child: Text(
                _types[i],
                style: TextStyle(
                  fontSize: 12.sp,
                  color: active ? Colors.white : AppColors.navBlue,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return HostSubPageScaffold(
      title: '额度变更',
      body: Column(
        children: [
          SizedBox(height: 8.h),
          _typeChips(),
          SizedBox(height: 8.h),
          DateRangeFilter(
            quickIndex: quickIndex,
            start: start,
            end: end,
            quickItems: quickItems,
            onQuickTap: onQuickTap,
            onPickStart: () => pickDate(isStart: true),
            onPickEnd: () => pickDate(isStart: false),
            onQuery: onQuery,
          ),
          SizedBox(height: 8.h),
          Expanded(
            child: _loading
                ? const AppPageLoading()
                : _unbound
                    ? Center(
                        child: Text(
                          '请先绑定代理会员',
                          style: TextStyle(fontSize: 14.sp, color: AppColors.textHint),
                        ),
                      )
                    : _rows.isEmpty
                        ? Center(
                            child: Text(
                              '暂无数据',
                              style: TextStyle(color: AppColors.textHint),
                            ),
                          )
                        : ListView.separated(
                            padding: EdgeInsets.all(16.w),
                            itemCount: _rows.length,
                            separatorBuilder: (_, _) => SizedBox(height: 8.h),
                            itemBuilder: (_, i) {
                              final r = _rows[i];
                              final type = '${r['changeType'] ?? ''}';
                              final amount = r['amount'] ?? '';
                              return HostWhiteCard(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${_feipanChangeTypeLabel(type)}  ${displayNumber(amount)}',
                                      style: TextStyle(
                                        fontSize: 14.sp,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    SizedBox(height: 4.h),
                                    Text(
                                      '总额后:${displayNumber(r['totalAfter'])}  占用后:${displayNumber(r['occupiedAfter'])}',
                                      style: TextStyle(
                                        fontSize: 12.sp,
                                        color: AppColors.textSecondary,
                                      ),
                                    ),
                                    if ('${r['remark'] ?? ''}'.isNotEmpty) ...[
                                      SizedBox(height: 2.h),
                                      Text(
                                        '${r['remark']}',
                                        style: TextStyle(
                                          fontSize: 12.sp,
                                          color: AppColors.textHint,
                                        ),
                                      ),
                                    ],
                                    SizedBox(height: 2.h),
                                    Text(
                                      '${r['createdAt'] ?? ''}',
                                      style: TextStyle(
                                        fontSize: 12.sp,
                                        color: AppColors.textHint,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }
}
