import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../config/theme/app_colors.dart';
import '../../../data/repositories/providers.dart';
import '../../../shared/widgets/app_pull_refresh.dart';
import '../../../shared/widgets/emulator_safe_text_field.dart';
import '../../../shared/widgets/gradient_background.dart';
import '../../../shared/widgets/page_app_bar.dart';
import '../../wallet/widgets/date_range_filter.dart';
import '../data/host_mock.dart';
import '../providers/host_pending_audit_provider.dart';
import '../widgets/host_ui.dart';
import 'host_shell_page.dart';

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
  bool _acting = false;
  List<DateRangeQuickItem> _dayItems = [];

  static const _statusKeys = ['ALL', 'PENDING', 'APPROVED', 'REJECTED'];

  List<DateRangeQuickItem> _buildDayItems() => DateRangeFilter.buildQuickItems()
      .where((e) => e.label == '今日' || e.label == '昨日')
      .toList();

  @override
  void initState() {
    super.initState();
    _dayItems = _buildDayItems();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load({bool fromPull = false}) async {
    if (!fromPull && mounted) setState(() => _loading = true);
    try {
      final repo = ref.read(ownerRepositoryProvider);
      final dayItem = _dayItems[_day.clamp(0, _dayItems.length - 1)];
      final start = DateRangeFilter.format(dayItem.start);
      final end = DateRangeFilter.format(dayItem.end);
      final status = _statusKeys[_status.clamp(0, 3)];
      final results = await Future.wait([
        repo.getApplications('up',
            startDate: start, endDate: end, status: status, pageSize: 50),
        repo.getApplications('down',
            startDate: start, endDate: end, status: status, pageSize: 50),
        repo.getApplications('enter',
            startDate: start, endDate: end, status: status, pageSize: 50),
      ]);
      final merged = <HostAuditItem>[
        ...hostRowsOf(results[0]).map((e) => hostAuditFromMap(e, AuditType.up)),
        ...hostRowsOf(results[1]).map((e) => hostAuditFromMap(e, AuditType.down)),
        ...hostRowsOf(results[2]).map((e) => hostAuditFromMap(e, AuditType.join)),
      ];
      merged.sort((a, b) => b.time.compareTo(a.time));
      if (!mounted) return;
      setState(() {
        _items = merged;
        _loading = false;
      });
      // 同步底部 Tab / 标题角标
      await ref.read(hostPendingAuditProvider.notifier).refresh();
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
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
    return AppPageScaffold(
      body: GradientBackground(
        child: SafeArea(
          child: Column(
            children: [
              PageAppBar(
                title: '申请记录',
                onBack: () => goHostLottery(context, widget.roomId),
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
                                  physics: const AlwaysScrollableScrollPhysics(),
                                  padding: EdgeInsets.all(12.w),
                                  itemCount: _items.length,
                                  separatorBuilder: (_, _) =>
                                      SizedBox(height: 8.h),
                                  itemBuilder: (_, i) => _card(_items[i]),
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
    return Container(
      padding: EdgeInsets.all(12.w),
      decoration: BoxDecoration(
        color: const Color(0xFFF7FBFF),
        borderRadius: BorderRadius.circular(10.r),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                item.nickname,
                style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              Text(
                item.time,
                style: TextStyle(fontSize: 11.sp, color: AppColors.textHint),
              ),
            ],
          ),
          SizedBox(height: 6.h),
          Text(item.summary, style: TextStyle(fontSize: 13.sp)),
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
          ],
        ],
      ),
    );
  }
}
