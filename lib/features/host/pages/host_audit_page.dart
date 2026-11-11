import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../config/theme/app_colors.dart';
import '../../../data/repositories/providers.dart';
import '../../../shared/widgets/app_pull_refresh.dart';
import '../../../shared/widgets/emulator_safe_text_field.dart';
import '../../../shared/widgets/gradient_background.dart';
import '../../../shared/widgets/app_back.dart';
import '../../../shared/widgets/page_app_bar.dart';
import '../../wallet/widgets/date_range_filter.dart';
import '../data/host_mock.dart';
import '../providers/host_pending_audit_provider.dart';
import '../widgets/host_ui.dart';

/// 审核列表 — 1:1 竞品「申请记录」
class HostAuditPage extends ConsumerStatefulWidget {
  const HostAuditPage({super.key, required this.roomId});

  final String roomId;

  @override
  ConsumerState<HostAuditPage> createState() => _HostAuditPageState();
}

class _HostAuditPageState extends ConsumerState<HostAuditPage> {
  int _day = 0;
  int _status = 1; // 全部 / 未审核 / 已通过 / 已拒绝
  List<HostAuditItem> _items = [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  /// 刷新（替换第 1 页）进行中。挡住滑到底的加载更多，避免它把本次刷新的序号冲掉。
  bool _resetting = false;
  bool _acting = false;
  int _page = 1;
  static const _pageSize = 50;
  List<DateRangeQuickItem> _dayItems = [];
  int _loadGen = 0;
  DateTime? _lastLoadAt;
  final _scroll = ScrollController();

  static const _statusKeys = ['ALL', 'PENDING', 'APPROVED', 'REJECTED'];

  List<DateRangeQuickItem> _buildDayItems() => DateRangeFilter.buildQuickItems()
      .where((e) => e.label == '今日' || e.label == '昨日')
      .toList();

  @override
  void initState() {
    super.initState();
    _dayItems = _buildDayItems();
    _scroll.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  /// 只有列表能滚动、并且滑到接近底部时才翻页。不满一屏时 maxScrollExtent 为 0，不请求下一页。
  void _onScroll() {
    if (!_hasMore || _loadingMore || _loading || _resetting) return;
    if (!_scroll.hasClients) return;
    final pos = _scroll.position;
    if (pos.maxScrollExtent <= 0) return;
    if (pos.pixels >= pos.maxScrollExtent - 80) {
      _load(reset: false);
    }
  }

  Future<void> _load({bool fromPull = false, bool reset = true}) async {
    if (!reset) {
      if (!_hasMore || _loadingMore || _loading || _resetting) return;
    } else {
      final now = DateTime.now();
      // 进 Tab 时 initState + shell tick 可能连打两次，合并
      if (_lastLoadAt != null &&
          now.difference(_lastLoadAt!) < const Duration(milliseconds: 400)) {
        return;
      }
      _lastLoadAt = now;
      // 先挡住加载更多，且不要提前把 _hasMore 设回 true。
      // 否则短列表的底部会立刻请求第 2 页，冲掉这次刷新，再把同一条追加进来。
      _resetting = true;
    }
    final page = reset ? 1 : _page + 1;
    final gen = ++_loadGen;
    _dayItems = _buildDayItems();
    final silent = !reset || fromPull || _items.isNotEmpty;
    if (!reset && mounted) {
      setState(() => _loadingMore = true);
    }
    if (!silent && mounted) setState(() => _loading = true);
    try {
      final repo = ref.read(ownerRepositoryProvider);
      final dayItem = _dayItems[_day.clamp(0, _dayItems.length - 1)];
      final start = DateRangeFilter.format(dayItem.start);
      final end = DateRangeFilter.format(dayItem.end);
      final status = _statusKeys[_status.clamp(0, 3)];
      final results = await Future.wait([
        repo.getApplications('up',
            startDate: start, endDate: end, status: status, pageNum: page, pageSize: _pageSize),
        repo.getApplications('down',
            startDate: start, endDate: end, status: status, pageNum: page, pageSize: _pageSize),
        repo.getApplications('enter',
            startDate: start, endDate: end, status: status, pageNum: page, pageSize: _pageSize),
      ]);
      if (gen != _loadGen || !mounted) return;
      final merged = <HostAuditItem>[
        ...hostRowsOf(results[0]).map((e) => hostAuditFromMap(e, AuditType.up)),
        ...hostRowsOf(results[1]).map((e) => hostAuditFromMap(e, AuditType.down)),
        ...hostRowsOf(results[2]).map((e) => hostAuditFromMap(e, AuditType.join)),
      ];
      merged.sort((a, b) => b.time.compareTo(a.time));
      final more = results.any((raw) {
        final rows = hostRowsOf(raw);
        final total = _pageTotal(raw['total'], rows.length);
        return page * _pageSize < total && rows.isNotEmpty;
      });
      setState(() {
        final next = reset
            ? _dedupeAudits(merged)
            : _dedupeAudits([..._items, ...merged]);
        final grew = next.length > _items.length;
        _items = next;
        _page = page;
        // 追加页若全是已有单号（分页溢出又回到第 1 页），停止再请求。
        _hasMore = more && (reset || grew);
        _loading = false;
        _loadingMore = false;
        _resetting = false;
      });
      // 同步底部 Tab / 标题角标
      await ref.read(hostPendingAuditProvider.notifier).refresh();
    } catch (e) {
      if (gen != _loadGen || !mounted) return;
      setState(() {
        _loading = false;
        _loadingMore = false;
        _resetting = false;
      });
      AppToast.error(e.toString());
    }
  }

  Future<void> _decide(HostAuditItem item, {required bool approve}) async {
    if (_acting || item.id.isEmpty) return;
    setState(() => _acting = true);
    try {
      final repo = ref.read(ownerRepositoryProvider);
      if (approve) {
        await repo.approveApplication(item.id);
        AppToast.success('已通过');
      } else {
        await repo.rejectApplication(item.id);
        AppToast.info('已拒绝');
      }
      // 先减角标 + 本地去掉待审项，再拉列表对齐
      if (item.status.toUpperCase() == 'PENDING') {
        ref.read(hostPendingAuditProvider.notifier).onReviewed(item.type);
      }
      if (mounted && _status == 1) {
        setState(() => _items.removeWhere((e) => e.id == item.id));
      }
      await _load(fromPull: true);
    } catch (e) {
      AppToast.error(e.toString());
      await ref.read(hostPendingAuditProvider.notifier).refresh();
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // 进审核 Tab / 再点 Tab：壳层 tick → 静默重拉
    ref.listen<int>(hostAuditListRefreshTickProvider, (prev, next) {
      if (prev == next) return;
      unawaited(_load(fromPull: true));
    });
    return AppPageScaffold(
      body: GradientBackground(
        child: SafeArea(
          child: Column(
            children: [
              PageAppBar(
                title: '申请记录',
                onBack: () => appHandleBack(context),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(16.w, 4.h, 16.w, 0),
                child: Column(
                  children: [
                    Row(
                      children: [
                        for (var i = 0; i < _dayItems.length; i++) ...[
                          if (i > 0) SizedBox(width: 8.w),
                          _chip(_dayItems[i].label, _day == i, () {
                            setState(() => _day = i);
                            _load();
                          }),
                        ],
                      ],
                    ),
                    SizedBox(height: 8.h),
                    Row(
                      children: [
                        _chip('全部', _status == 0, () {
                          setState(() => _status = 0);
                          _load();
                        }),
                        SizedBox(width: 8.w),
                        _chip('未审核', _status == 1, () {
                          setState(() => _status = 1);
                          _load();
                        }),
                        SizedBox(width: 8.w),
                        _chip('已通过', _status == 2, () {
                          setState(() => _status = 2);
                          _load();
                        }),
                        SizedBox(width: 8.w),
                        _chip('已拒绝', _status == 3, () {
                          setState(() => _status = 3);
                          _load();
                        }),
                      ],
                    ),
                  ],
                ),
              ),
              SizedBox(height: 12.h),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16.w),
                  child: Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16.r),
                    ),
                    child: AppPullRefresh(
                      onRefresh: () => _load(fromPull: true),
                      child: _loading && _items.isEmpty
                          ? ListView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              children: const [
                                SizedBox(height: 120),
                                const AppPageLoading(),
                              ],
                            )
                          : _items.isEmpty
                              ? ListView(
                                  physics: const AlwaysScrollableScrollPhysics(),
                                  children: [
                                    SizedBox(height: 120.h),
                                    Center(
                                      child: Text(
                                        '暂无数据',
                                        style: TextStyle(
                                          fontSize: 14.sp,
                                          color: AppColors.textHint,
                                        ),
                                      ),
                                    ),
                                  ],
                                )
                              : ListView.separated(
                                  controller: _scroll,
                                  physics: const AlwaysScrollableScrollPhysics(),
                                  padding: EdgeInsets.all(12.w),
                                  itemCount: _items.length + 1,
                                  separatorBuilder: (_, i) => i >= _items.length - 1
                                      ? const SizedBox.shrink()
                                      : SizedBox(height: 8.h),
                                  itemBuilder: (_, i) {
                                    if (i == _items.length) {
                                      final hint = _loadingMore
                                          ? '加载中'
                                          : (_hasMore ? '' : '没有更多了');
                                      return Padding(
                                        padding: EdgeInsets.only(top: 8.h),
                                        child: Center(
                                          child: Text(
                                            hint,
                                            style: TextStyle(fontSize: 12.sp, color: AppColors.textHint),
                                          ),
                                        ),
                                      );
                                    }
                                    return _card(_items[i]);
                                  },
                                ),
                    ),
                  ),
                ),
              ),
              SizedBox(height: 12.h),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chip(String label, bool active, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 6.h),
        decoration: BoxDecoration(
          color: active ? AppColors.navBlue : Colors.white,
          borderRadius: BorderRadius.circular(16.r),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13.sp,
            color: active ? Colors.white : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _card(HostAuditItem item) {
    final pending = item.status.toUpperCase() == 'PENDING';
    final down = item.type == AuditType.down;
    final join = item.type == AuditType.join;
    final amtText = join
        ? '进房'
        : '${down ? '-' : '+'}${hostNumStr(item.amount, fraction: 2)}';
    final meta = [
      item.time,
      item.summary,
      if (item.points != null) '可用 ${hostNumStr(item.points, fraction: 2)}',
    ].join(' · ');
    return Container(
      padding: EdgeInsets.all(12.w),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10.r),
        border: Border.all(color: const Color(0xFFE8EEF5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.nickname,
                      style: TextStyle(
                        fontSize: 15.sp,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(height: 4.h),
                    Text(
                      meta,
                      style: TextStyle(
                        fontSize: 11.sp,
                        color: AppColors.textHint,
                      ),
                    ),
                    if (item.remark.isNotEmpty) ...[
                      SizedBox(height: 4.h),
                      Text(
                        item.remark,
                        style: TextStyle(
                          fontSize: 12.sp,
                          height: 1.35,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              SizedBox(width: 8.w),
              Text(
                amtText,
                style: TextStyle(
                  fontSize: 18.sp,
                  fontWeight: FontWeight.w700,
                  color: down ? AppColors.danger : AppColors.textPrimary,
                ),
              ),
            ],
          ),
          if (pending) ...[
            SizedBox(height: 10.h),
            Row(
              children: [
                Expanded(
                  child: HostPrimaryButton(
                    label: '通过',
                    onPressed:
                        _acting ? null : () => _decide(item, approve: true),
                  ),
                ),
                SizedBox(width: 8.w),
                Expanded(
                  child: HostPrimaryButton(
                    label: '拒绝',
                    color: AppColors.danger,
                    onPressed:
                        _acting ? null : () => _decide(item, approve: false),
                  ),
                ),
              ],
            ),
          ] else ...[
            SizedBox(height: 6.h),
            Text(
              item.status.toUpperCase() == 'APPROVED' ? '已通过' : '已拒绝',
              style: TextStyle(
                fontSize: 12.sp,
                color: item.status.toUpperCase() == 'APPROVED'
                    ? AppColors.success
                    : AppColors.textHint,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

int _pageTotal(dynamic raw, int fallback) {
  if (raw is num) return raw.toInt();
  final parsed = int.tryParse('$raw');
  if (parsed != null) return parsed;
  return fallback;
}

/// 同一申请单号只留一行。没有单号的行保留，避免把缺 id 的记录折叠掉。
List<HostAuditItem> _dedupeAudits(List<HostAuditItem> items) {
  final seen = <String>{};
  final out = <HostAuditItem>[];
  for (final item in items) {
    if (item.id.isEmpty || seen.add(item.id)) out.add(item);
  }
  return out;
}
