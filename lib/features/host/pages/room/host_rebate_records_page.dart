import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../../config/theme/app_colors.dart';
import '../../../../data/repositories/providers.dart';
import '../../../../shared/widgets/page_app_bar.dart';
import '../../../wallet/widgets/date_range_filter.dart';
import '../../data/host_mock.dart';
import '../../widgets/host_ui.dart';

/// 彩票回水记录，或代理抽佣记录。数据结构和筛选相同，kind 不同。
class HostRebateRecordsPage extends ConsumerStatefulWidget {
  const HostRebateRecordsPage({
    super.key,
    required this.roomId,
    this.commission = false,
  });

  final String roomId;
  final bool commission;

  @override
  ConsumerState<HostRebateRecordsPage> createState() =>
      _HostRebateRecordsPageState();
}

class _HostRebateRecordsPageState extends ConsumerState<HostRebateRecordsPage>
    with DateRangePageMixin {
  List<Map<String, dynamic>> _rows = [];
  int _total = 0;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  @override
  void onQuery() => _load();

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final repo = ref.read(ownerRepositoryProvider);
      final data = widget.commission
          ? await repo.getCommissionRecords(
              startDate: DateRangeFilter.format(start),
              endDate: DateRangeFilter.format(end),
              pageSize: 200,
            )
          : await repo.getRebateRecords(
              startDate: DateRangeFilter.format(start),
              endDate: DateRangeFilter.format(end),
              pageSize: 200,
            );
      if (!mounted) return;
      final rows = hostRowsOf(data);
      setState(() {
        _rows = rows;
        _total = int.tryParse('${data['total'] ?? rows.length}') ?? rows.length;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      AppToast.error(e.toString());
    }
  }

  String _who(Map<String, dynamic> r) {
    final nick = '${r['nickname'] ?? ''}'.trim();
    final user = '${r['username'] ?? ''}'.trim();
    if (nick.isNotEmpty) return nick;
    if (user.isNotEmpty) return user;
    return '${r['accountId'] ?? ''}'.trim();
  }

  String _desc(Map<String, dynamic> r) {
    final remark = '${r['remark'] ?? ''}'.trim();
    if (remark.isNotEmpty) return remark;
    final label = '${r['claimSourceLabel'] ?? ''}'.trim();
    if (label.isNotEmpty) return label;
    final src = '${r['claimSource'] ?? ''}'.toUpperCase();
    return switch (src) {
      'SELF' => '自行领取',
      'OWNER' => '房主一键',
      'SYSTEM' => '系统自动',
      _ => widget.commission ? '抽佣' : '回水',
    };
  }

  String _time(Map<String, dynamic> r) {
    final raw = '${r['claimedAt'] ?? r['createdAt'] ?? ''}'.trim();
    if (raw.length >= 16) {
      // 2026-09-22 22:40:00 → 09-22 22:40
      final m = RegExp(r'(\d{2})-(\d{2})\s+(\d{2}:\d{2})').firstMatch(raw);
      if (m != null) return '${m.group(1)}-${m.group(2)} ${m.group(3)}';
    }
    return raw;
  }

  @override
  Widget build(BuildContext context) {
    return HostSubPageScaffold(
      title: widget.commission ? '代理抽佣记录' : '彩票回水记录',
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
                : _rows.isEmpty
                    ? Center(
                        child: Text(
                          widget.commission ? '暂无抽佣记录' : '暂无回水记录',
                          style: TextStyle(
                            fontSize: 14.sp,
                            color: AppColors.textHint,
                          ),
                        ),
                      )
                    : ListView.separated(
                        padding: EdgeInsets.fromLTRB(16.w, 0, 16.w, 16.h),
                        itemCount: _rows.length + 1,
                        separatorBuilder: (_, i) => i >= _rows.length - 1
                            ? const SizedBox.shrink()
                            : SizedBox(height: 10.h),
                        itemBuilder: (_, i) {
                          if (i == _rows.length) {
                            return Padding(
                              padding: EdgeInsets.only(top: 12.h, bottom: 8.h),
                              child: Center(
                                child: Text(
                                  '没有更多了，共 $_total 条',
                                  style: TextStyle(
                                    fontSize: 12.sp,
                                    color: AppColors.textHint,
                                  ),
                                ),
                              ),
                            );
                          }
                          final r = _rows[i];
                          return HostWhiteCard(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        _who(r),
                                        style: TextStyle(
                                          fontSize: 15.sp,
                                          fontWeight: FontWeight.w700,
                                          color: const Color(0xFF222222),
                                        ),
                                      ),
                                    ),
                                    Text(
                                      hostNumStr(r['amount'], fraction: 2),
                                      style: TextStyle(
                                        fontSize: 16.sp,
                                        fontWeight: FontWeight.w700,
                                        color: const Color(0xFF2E7D32),
                                      ),
                                    ),
                                  ],
                                ),
                                SizedBox(height: 6.h),
                                Text(
                                  _desc(r),
                                  style: TextStyle(
                                    fontSize: 13.sp,
                                    color: const Color(0xFF333333),
                                  ),
                                ),
                                SizedBox(height: 6.h),
                                Text(
                                  _time(r),
                                  style: TextStyle(
                                    fontSize: 12.sp,
                                    color: AppColors.textSecondary,
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
