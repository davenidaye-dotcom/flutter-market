import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../../config/theme/app_colors.dart';
import '../../../../data/repositories/providers.dart';
import '../../../../shared/widgets/page_app_bar.dart';
import '../../data/host_mock.dart';
import '../../widgets/host_ui.dart';

/// Op logs — GET /owner/room/op-logs?action=
/// action/content 接口仍可能是英文码，展示一律走 [hostOpActionLabel] / [hostOpContentLabel]
class HostOperationLogsPage extends ConsumerStatefulWidget {
  const HostOperationLogsPage({super.key, required this.roomId});
  final String roomId;

  @override
  ConsumerState<HostOperationLogsPage> createState() =>
      _HostOperationLogsPageState();
}

class _Filter {
  const _Filter(this.label, {this.action});
  final String label;
  /// 传给接口的 action：单码 / 逗号多码 / 前缀*
  final String? action;
}

class _HostOperationLogsPageState extends ConsumerState<HostOperationLogsPage> {
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  int _page = 1;
  int _total = 0;
  int _filter = 0;
  static const _pageSize = 50;

  static const _filters = <_Filter>[
    _Filter('全部'),
    _Filter(
      '用户管理',
      action:
          'MEMBER_STATUS,MEMBER_REBATE,MEMBER_REMARK,MEMBER_DELETE,MEMBER_ROBOT,MEMBER_TRIAL',
    ),
    _Filter('积分', action: 'MEMBER_CREDIT,APPLICATION*'),
    _Filter('审核', action: 'APPLICATION*'),
    _Filter(
      '代理',
      action: 'MEMBER_AGENT,MEMBER_DOWNLINE',
    ),
    _Filter('赔率与限额', action: 'ODDS'),
    _Filter('回水', action: 'REBATE,MEMBER_REBATE'),
    _Filter('彩种', action: 'GAME_SETTINGS'),
    _Filter('公告', action: 'ANNOUNCEMENT'),
    _Filter('房间设置', action: 'ROOM_NAME,ENTER_PASSWORD,ROOM_FLAGS'),
    _Filter('协管', action: 'ASSISTANT*'),
  ];

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  Future<void> _load({bool reset = true}) async {
    if (!reset) {
      if (!_hasMore || _loadingMore || _loading) return;
      setState(() => _loadingMore = true);
    } else {
      setState(() {
        _loading = true;
        _page = 1;
        _hasMore = true;
      });
    }
    final page = reset ? 1 : _page + 1;
    try {
      final f = _filters[_filter.clamp(0, _filters.length - 1)];
      final data = await ref.read(ownerRepositoryProvider).getOpLogs(
            action: f.action,
            pageNum: page,
            pageSize: _pageSize,
          );
      if (!mounted) return;
      final list = hostRowsOf(data);
      final total = int.tryParse('${data['total'] ?? list.length}') ?? list.length;
      setState(() {
        _rows = reset ? list : [..._rows, ...list];
        _page = page;
        _total = total;
        _hasMore = _rows.length < total && list.isNotEmpty;
        _loading = false;
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadingMore = false;
      });
      AppToast.error(e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return HostSubPageScaffold(
      title: '操作日志',
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
                  onTap: () {
                    if (_filter == i) return;
                    setState(() => _filter = i);
                    _load();
                  },
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 10.w),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: active ? AppColors.navBlue : const Color(0xFFD6EBFA),
                      borderRadius: BorderRadius.circular(14.r),
                    ),
                    child: Text(
                      _filters[i].label,
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
                ? const AppPageLoading()
                : _rows.isEmpty
                    ? Center(
                        child: Text(
                          '暂无数据',
                          style: TextStyle(fontSize: 14.sp, color: AppColors.textHint),
                        ),
                      )
                    : ListView.separated(
                        padding: EdgeInsets.all(16.w),
                        itemCount: _rows.length + 1,
                        separatorBuilder: (_, i) =>
                            i >= _rows.length - 1 ? const SizedBox.shrink() : SizedBox(height: 8.h),
                        itemBuilder: (_, i) {
                          if (i == _rows.length) {
                            if (_hasMore && !_loadingMore) {
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                if (mounted) _load(reset: false);
                              });
                            }
                            return Padding(
                              padding: EdgeInsets.only(top: 8.h),
                              child: Center(
                                child: Text(
                                  _hasMore ? '加载中' : '没有更多了，共 $_total 条',
                                  style: TextStyle(fontSize: 12.sp, color: AppColors.textHint),
                                ),
                              ),
                            );
                          }
                          final r = _rows[i];
                          final action = (r['action'] ?? '').toString();
                          final content = hostOpContentLabel(
                            (r['content'] ?? r['summary'] ?? '').toString(),
                          );
                          return HostWhiteCard(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  content.isEmpty ? '—' : content,
                                  style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600),
                                ),
                                SizedBox(height: 4.h),
                                Text(
                                  '${hostOpActionLabel(action)} · ${r['operatorName'] ?? r['operator'] ?? ''} · ${r['createdAt'] ?? r['time'] ?? ''}',
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
