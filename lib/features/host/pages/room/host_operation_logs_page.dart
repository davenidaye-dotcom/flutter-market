import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../../config/theme/app_colors.dart';
import '../../../../data/repositories/providers.dart';
import '../../../../shared/widgets/page_app_bar.dart';
import '../../data/host_mock.dart';
import '../../widgets/host_ui.dart';

/// Op logs — GET /owner/room/op-logs
class HostOperationLogsPage extends ConsumerStatefulWidget {
  const HostOperationLogsPage({super.key, required this.roomId});
  final String roomId;

  @override
  ConsumerState<HostOperationLogsPage> createState() =>
      _HostOperationLogsPageState();
}

class _HostOperationLogsPageState extends ConsumerState<HostOperationLogsPage> {
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;
  int _filter = 0;

  static const _filters = [
    '\u5168\u90e8',
    '\u7528\u6237\u7ba1\u7406',
    '\u79ef\u5206',
    '\u5ba1\u6838',
    '\u4ee3\u7406',
    '\u8d54\u7387\u4e0e\u9650\u989d',
    '\u53cd\u6c34',
    '\u5f69\u79cd',
    '\u516c\u544a',
    '\u6c14\u6c1b\u53f7',
    '\u623f\u95f4\u8bbe\u7f6e',
    '\u534f\u7ba1',
  ];

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await ref.read(ownerRepositoryProvider).getOpLogs(pageSize: 100);
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

  List<Map<String, dynamic>> get _filtered {
    if (_filter == 0) return _rows;
    final key = _filters[_filter];
    return _rows.where((r) {
      final cat = (r['category'] ?? r['type'] ?? r['module'] ?? '').toString();
      return cat.contains(key) || key.contains(cat);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final list = _filtered;
    return HostSubPageScaffold(
      title: '\u64cd\u4f5c\u65e5\u5fd7',
      body: Column(
        children: [
          SizedBox(
            height: 40.h,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.symmetric(horizontal: 12.w),
              itemCount: _filters.length,
              separatorBuilder: (_, _) => SizedBox(width: 6.w),
              itemBuilder: (_, i) {
                final active = i == _filter;
                return GestureDetector(
                  onTap: () => setState(() => _filter = i),
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 10.w),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: active ? AppColors.navBlue : const Color(0xFFD6EBFA),
                      borderRadius: BorderRadius.circular(14.r),
                    ),
                    child: Text(
                      _filters[i],
                      style: TextStyle(
                        fontSize: 12.sp,
                        color: active ? Colors.white : AppColors.navBlue,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : list.isEmpty
                    ? Center(
                        child: Text(
                          '\u6682\u65e0\u6570\u636e',
                          style: TextStyle(fontSize: 14.sp, color: AppColors.textHint),
                        ),
                      )
                    : ListView.separated(
                        padding: EdgeInsets.all(16.w),
                        itemCount: list.length,
                        separatorBuilder: (_, _) => SizedBox(height: 8.h),
                        itemBuilder: (_, i) {
                          final r = list[i];
                          return HostWhiteCard(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  (r['summary'] ?? r['content'] ?? r['action'] ?? '').toString(),
                                  style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600),
                                ),
                                SizedBox(height: 4.h),
                                Text(
                                  '${r['category'] ?? r['type'] ?? ''} · ${r['operator'] ?? r['operatorName'] ?? ''} · ${r['createdAt'] ?? r['time'] ?? ''}',
                                  style: TextStyle(fontSize: 12.sp, color: AppColors.textSecondary),
                                ),
                                if ((r['detail'] ?? r['remark'] ?? '').toString().isNotEmpty) ...[
                                  SizedBox(height: 4.h),
                                  Text(
                                    '${r['detail'] ?? r['remark']}',
                                    style: TextStyle(fontSize: 12.sp, color: AppColors.textHint),
                                  ),
                                ],
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
