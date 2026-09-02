import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../config/theme/app_colors.dart';
import '../../../data/repositories/providers.dart';
import '../../../shared/widgets/emulator_safe_text_field.dart';
import '../../../shared/widgets/gradient_background.dart';
import '../../../shared/widgets/page_app_bar.dart';
import '../data/host_mock.dart';
import '../widgets/host_ui.dart';
import 'host_shell_page.dart';

/// \u5ba1\u6838\u5217\u8868 \u2014 1:1 \u7ade\u54c1\u300c\u7533\u8bf7\u8bb0\u5f55.jpg\u300d
class HostAuditPage extends ConsumerStatefulWidget {
  const HostAuditPage({super.key, required this.roomId});

  final String roomId;

  @override
  ConsumerState<HostAuditPage> createState() => _HostAuditPageState();
}

class _HostAuditPageState extends ConsumerState<HostAuditPage> {
  int _day = 0; // \u4eca\u5929 / \u6628\u5929
  int _status = 1; // \u5168\u90e8 / \u672a\u5ba1\u6838 / \u5df2\u901a\u8fc7 / \u5df2\u62d2\u7edd
  List<HostAuditItem> _items = [];
  bool _loading = true;
  bool _acting = false;

  static const _statusKeys = ['ALL', 'PENDING', 'APPROVED', 'REJECTED'];
  static const _dayKeys = ['TODAY', 'YESTERDAY'];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final repo = ref.read(ownerRepositoryProvider);
      final day = _dayKeys[_day.clamp(0, 1)];
      final status = _statusKeys[_status.clamp(0, 3)];
      final results = await Future.wait([
        repo.getApplications('up', day: day, status: status, pageSize: 50),
        repo.getApplications('down', day: day, status: status, pageSize: 50),
        repo.getApplications('enter', day: day, status: status, pageSize: 50),
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
        AppToast.success('\u5df2\u901a\u8fc7');
      } else {
        await repo.rejectApplication(item.id);
        AppToast.info('\u5df2\u62d2\u7edd');
      }
      await _load();
    } catch (e) {
      AppToast.error(e.toString());
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
                title: '\u7533\u8bf7\u8bb0\u5f55',
                onBack: () => goHostLottery(context, widget.roomId),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(16.w, 4.h, 16.w, 0),
                child: Column(
                  children: [
                    Row(
                      children: [
                        _chip('\u4eca\u5929', _day == 0, () {
                          setState(() => _day = 0);
                          _load();
                        }),
                        SizedBox(width: 8.w),
                        _chip('\u6628\u5929', _day == 1, () {
                          setState(() => _day = 1);
                          _load();
                        }),
                      ],
                    ),
                    SizedBox(height: 8.h),
                    Row(
                      children: [
                        _chip('\u5168\u90e8', _status == 0, () {
                          setState(() => _status = 0);
                          _load();
                        }),
                        SizedBox(width: 8.w),
                        _chip('\u672a\u5ba1\u6838', _status == 1, () {
                          setState(() => _status = 1);
                          _load();
                        }),
                        SizedBox(width: 8.w),
                        _chip('\u5df2\u901a\u8fc7', _status == 2, () {
                          setState(() => _status = 2);
                          _load();
                        }),
                        SizedBox(width: 8.w),
                        _chip('\u5df2\u62d2\u7edd', _status == 3, () {
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
                    child: RefreshIndicator(
                      onRefresh: _load,
                      child: _loading
                          ? ListView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              children: const [
                                SizedBox(height: 120),
                                Center(child: CircularProgressIndicator()),
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
                                        style: TextStyle(fontSize: 14.sp, color: AppColors.textHint),
                                      ),
                                    ),
                                  ],
                                )
                              : ListView.separated(
                                  physics: const AlwaysScrollableScrollPhysics(),
                                  padding: EdgeInsets.all(12.w),
                                  itemCount: _items.length,
                                  separatorBuilder: (_, _) => SizedBox(height: 8.h),
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
          style: TextStyle(fontSize: 13.sp, color: active ? Colors.white : AppColors.textSecondary),
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
              Text(item.nickname, style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w600)),
              const Spacer(),
              Text(item.time, style: TextStyle(fontSize: 11.sp, color: AppColors.textHint)),
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
                    label: '\u901a\u8fc7',
                    onPressed: _acting ? null : () => _decide(item, approve: true),
                  ),
                ),
                SizedBox(width: 8.w),
                Expanded(
                  child: HostPrimaryButton(
                    label: '\u62d2\u7edd',
                    color: AppColors.danger,
                    onPressed: _acting ? null : () => _decide(item, approve: false),
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
