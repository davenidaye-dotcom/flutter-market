import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../../config/theme/app_colors.dart';
import '../../../../data/repositories/providers.dart';
import '../../../../shared/widgets/page_app_bar.dart';
import '../../../wallet/widgets/date_range_filter.dart';
import '../../data/host_mock.dart';
import '../../widgets/host_ui.dart';

/// Credit records — GET /owner/manage/credits/records
class ScoreFlowPage extends ConsumerStatefulWidget {
  const ScoreFlowPage({super.key, required this.roomId});
  final String roomId;

  @override
  ConsumerState<ScoreFlowPage> createState() => _ScoreFlowPageState();
}

class _ScoreFlowPageState extends ConsumerState<ScoreFlowPage>
    with DateRangePageMixin {
  List<Map<String, dynamic>> _rows = [];
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
      final data = await ref.read(ownerRepositoryProvider).getCreditRecords(
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

  @override
  Widget build(BuildContext context) {
    return HostSubPageScaffold(
      title: '\u4e0a\u4e0b\u5206\u8bb0\u5f55',
      body: Column(
        children: [
          SizedBox(height: 8.h),
          DateRangeFilter(
            quickIndex: quickIndex,
            start: start,
            end: end,
            onQuickTap: onQuickTap,
            onPickStart: () => pickDate(isStart: true),
            onPickEnd: () => pickDate(isStart: false),
            onQuery: onQuery,
          ),
          SizedBox(height: 12.h),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _rows.isEmpty
                    ? Center(
                        child: Text(
                          '\u6682\u65e0\u6570\u636e',
                          style: TextStyle(fontSize: 14.sp, color: AppColors.textHint),
                        ),
                      )
                    : ListView.separated(
                        padding: EdgeInsets.symmetric(horizontal: 16.w),
                        itemCount: _rows.length,
                        separatorBuilder: (_, _) => SizedBox(height: 8.h),
                        itemBuilder: (_, i) {
                          final r = _rows[i];
                          return HostWhiteCard(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${r['username'] ?? r['displayName'] ?? r['user'] ?? ''}  ${r['type'] ?? r['changeType'] ?? ''}',
                                  style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600),
                                ),
                                SizedBox(height: 4.h),
                                Text(
                                  '${r['amount'] ?? r['points'] ?? ''} · ${r['status'] ?? ''} · ${r['createdAt'] ?? r['createTime'] ?? ''}',
                                  style: TextStyle(fontSize: 12.sp, color: AppColors.textSecondary),
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
