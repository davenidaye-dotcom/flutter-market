import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../../config/theme/app_colors.dart';
import '../../../../data/repositories/providers.dart';
import '../../../../shared/format/display_number.dart';
import '../../../../shared/widgets/page_app_bar.dart';
import '../../../wallet/widgets/date_range_filter.dart';
import '../../../wallet/widgets/member_page_bar.dart';
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
  bool _busy = false;
  bool _unbound = false;
  int _page = 1;
  int _total = 0;
  int _totalPages = 0;
  int _typeIndex = 0;
  int _req = 0;
  static const _pageSize = 20;

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
  void onQuery() => _reload();

  void _reload() {
    setState(() {
      _page = 1;
      _rows = [];
      _total = 0;
      _totalPages = 0;
    });
    _load();
  }

  Future<void> _load({int? page}) async {
    final target = page ?? _page;
    final req = ++_req;
    final blank = _rows.isEmpty;
    setState(() {
      if (blank) _loading = true;
      _busy = true;
      _unbound = false;
    });
    try {
      final repo = ref.read(ownerRepositoryProvider);
      final statusFuture = repo.getFeipanStatus();
      Object? reportError;
      final dataFuture = repo.getFeipanPointsChanges(
        changeType: _typeKeys[_typeIndex],
        startDate: DateRangeFilter.format(start),
        endDate: DateRangeFilter.format(end),
        pageNum: target,
        pageSize: _pageSize,
      ).catchError((Object e) {
        reportError = e;
        return <String, dynamic>{};
      });
      final status = await statusFuture;
      if (!mounted || req != _req) return;
      if (status['bound'] != true) {
        setState(() {
          _unbound = true;
          _rows = [];
          _total = 0;
          _totalPages = 0;
          _loading = false;
          _busy = false;
        });
        return;
      }
      final data = await dataFuture;
      if (reportError != null) {
        throw reportError!;
      }
      if (!mounted || req != _req) return;
      final list = hostRowsOf(data);
      final total = int.tryParse('${data['total'] ?? list.length}') ?? list.length;
      setState(() {
        _page = target;
        _rows = list;
        _total = total;
        _totalPages = memberTotalPages(total, _pageSize);
        _loading = false;
        _busy = false;
      });
    } catch (e) {
      if (!mounted || req != _req) return;
      setState(() {
        _loading = false;
        _busy = false;
      });
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
              _reload();
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
            child: _loading && _rows.isEmpty
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
          if (!_unbound)
            MemberPageBar(
              page: _page,
              totalPages: _totalPages,
              totalCount: _total,
              busy: _busy,
              onPrev: () {
                if (_busy || _page <= 1) return;
                _load(page: _page - 1);
              },
              onNext: () {
                if (_busy || _totalPages == 0 || _page >= _totalPages) {
                  if (!_busy) AppToast.info('已是最后一页');
                  return;
                }
                _load(page: _page + 1);
              },
            ),
        ],
      ),
    );
  }
}
