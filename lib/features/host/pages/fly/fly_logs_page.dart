import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../../config/theme/app_colors.dart';
import '../../../../data/repositories/providers.dart';
import '../../../../shared/widgets/page_app_bar.dart';
import '../../../wallet/widgets/date_range_filter.dart';
import '../../data/host_mock.dart';
import '../../widgets/host_ui.dart';

String _feipanLogTypeLabel(String? action) {
  final a = (action ?? '').trim().toUpperCase();
  return switch (a) {
    'FEIPAN_BIND' => '绑定会员',
    'FEIPAN_UNBIND' => '解绑会员',
    'FEIPAN_AGENT_PWD' => '修改密码',
    'FEIPAN_SWITCH' => '飞单开关',
    'FEIPAN_RATIO' => '飞单比例',
    'FEIPAN_ODDS' => '飞单赔率',
    'FEIPAN_REPORT' => '飞单报表',
    _ => a.isEmpty ? '飞单设置' : a,
  };
}

/// Feipan op logs — GET /owner/feipan/op-logs（仅 FEIPAN_*）
class FlyLogsPage extends ConsumerStatefulWidget {
  const FlyLogsPage({super.key, required this.roomId});
  final String roomId;

  @override
  ConsumerState<FlyLogsPage> createState() => _FlyLogsPageState();
}

class _FlyLogsPageState extends ConsumerState<FlyLogsPage>
    with DateRangePageMixin {
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;
  bool _unbound = false;

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
      final data = await repo.getFeipanOpLogs(
        startDate: DateRangeFilter.format(start),
        endDate: DateRangeFilter.format(end),
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

  String _fmtAt(dynamic raw) {
    final s = '${raw ?? ''}'.trim();
    if (s.isEmpty) return '';
    // 2026-10-08 14:50:00 → 10-08 14:50
    final m = RegExp(r'(\d{4})-(\d{2})-(\d{2})[ T](\d{2}):(\d{2})').firstMatch(s);
    if (m != null) {
      return '${m.group(2)}-${m.group(3)} ${m.group(4)}:${m.group(5)}';
    }
    return s;
  }

  @override
  Widget build(BuildContext context) {
    return HostSubPageScaffold(
      title: '操作日志',
      body: Column(
        children: [
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
                            itemCount: _rows.length + 1,
                            separatorBuilder: (_, _) => SizedBox(height: 8.h),
                            itemBuilder: (_, i) {
                              if (i == _rows.length) {
                                return Padding(
                                  padding: EdgeInsets.only(bottom: 12.h),
                                  child: Center(
                                    child: Text(
                                      '没有更多了，共 ${_rows.length} 条',
                                      style: TextStyle(
                                        fontSize: 12.sp,
                                        color: AppColors.textHint,
                                      ),
                                    ),
                                  ),
                                );
                              }
                              final r = _rows[i];
                              final action = '${r['action'] ?? ''}';
                              final content = hostOpContentLabel(
                                '${r['content'] ?? ''}',
                              );
                              final op = '${r['operatorName'] ?? ''}';
                              final at = _fmtAt(r['createdAt']);
                              return HostWhiteCard(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(
                                          Icons.tune,
                                          size: 16.sp,
                                          color: AppColors.navBlue,
                                        ),
                                        SizedBox(width: 6.w),
                                        Expanded(
                                          child: Text(
                                            _feipanLogTypeLabel(action),
                                            style: TextStyle(
                                              fontSize: 14.sp,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                        Container(
                                          padding: EdgeInsets.symmetric(
                                            horizontal: 8.w,
                                            vertical: 2.h,
                                          ),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFE8F8EE),
                                            borderRadius:
                                                BorderRadius.circular(10.r),
                                          ),
                                          child: Text(
                                            '设置成功',
                                            style: TextStyle(
                                              fontSize: 11.sp,
                                              color: const Color(0xFF2E9B57),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    SizedBox(height: 8.h),
                                    Text(
                                      content.isEmpty ? '—' : content,
                                      style: TextStyle(fontSize: 13.sp),
                                    ),
                                    SizedBox(height: 8.h),
                                    Row(
                                      children: [
                                        Icon(
                                          Icons.person_outline,
                                          size: 13.sp,
                                          color: AppColors.textHint,
                                        ),
                                        SizedBox(width: 2.w),
                                        Flexible(
                                          child: Text(
                                            '操作人员:${op.isEmpty ? '—' : op}',
                                            style: TextStyle(
                                              fontSize: 11.sp,
                                              color: AppColors.textHint,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        SizedBox(width: 8.w),
                                        Icon(
                                          Icons.access_time,
                                          size: 13.sp,
                                          color: AppColors.textHint,
                                        ),
                                        SizedBox(width: 2.w),
                                        Text(
                                          at.isEmpty ? '—' : at,
                                          style: TextStyle(
                                            fontSize: 11.sp,
                                            color: AppColors.textHint,
                                          ),
                                        ),
                                      ],
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
