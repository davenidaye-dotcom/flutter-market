import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../../config/theme/app_colors.dart';
import '../../../../data/repositories/providers.dart';
import '../../../../shared/widgets/page_app_bar.dart';
import '../../data/host_mock.dart';
import '../../widgets/host_ui.dart';
import 'host_rebate_lines_page.dart';

/// 代理未返佣队列。
/// 查询 GET /owner/room/commission/batch-preview
/// 单笔返佣、一键返佣 POST /owner/room/commission/batch-advance
class HostPendingCommissionPage extends ConsumerStatefulWidget {
  const HostPendingCommissionPage({super.key, required this.roomId});

  final String roomId;

  @override
  ConsumerState<HostPendingCommissionPage> createState() =>
      _HostPendingCommissionPageState();
}

class _HostPendingCommissionPageState
    extends ConsumerState<HostPendingCommissionPage> {
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data =
          await ref.read(ownerRepositoryProvider).getCommissionBatchPreview();
      final members = data['members'];
      final rows = <Map<String, dynamic>>[];
      if (members is List) {
        for (final e in members) {
          if (e is! Map) continue;
          final m = Map<String, dynamic>.from(e);
          final pending = double.tryParse('${m['pendingRebate'] ?? 0}') ?? 0;
          if (pending <= 0) continue;
          rows.add(m);
        }
      }
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      AppToast.error(e.toString());
    }
  }

  Future<void> _pay(List<int> ids, {required String title}) async {
    if (_busy || ids.isEmpty) {
      if (ids.isEmpty) AppToast.info('暂无待处理返佣');
      return;
    }
    final ok = await hostConfirm(
      context,
      title: title,
      message: '确认发放 ${ids.length} 人的待领返佣？',
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      final res = await ref.read(ownerRepositoryProvider).batchAdvanceCommission(
            accountIds: ids,
            remark: title == '一键返佣' ? '一键返佣' : '房主手动代理返佣',
          );
      if (!mounted) return;
      final okCount = int.tryParse('${res['successCount'] ?? 0}') ?? 0;
      final fail = int.tryParse('${res['failCount'] ?? 0}') ?? 0;
      final amount = hostNumStr(res['totalRebateAmount'], fraction: 2);
      AppToast.success(
        '已返佣 $okCount 人，金额 $amount${fail > 0 ? '，失败 $fail' : ''}',
      );
      await _load();
    } catch (e) {
      AppToast.error(e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  List<int> get _ids => _rows
      .map((m) => int.tryParse('${m['accountId'] ?? ''}'))
      .whereType<int>()
      .toList();

  @override
  Widget build(BuildContext context) {
    final ids = _ids;
    return HostSubPageScaffold(
      title: '代理未返佣',
      trailing: TextButton(
        onPressed: _busy || ids.isEmpty ? null : () => _pay(ids, title: '一键返佣'),
        style: TextButton.styleFrom(
          backgroundColor: const Color(0xFFFCE4EC),
          foregroundColor: const Color(0xFFC2185B),
          padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.r)),
        ),
        child: Text(
          '一键返佣',
          maxLines: 1,
          softWrap: false,
          style: TextStyle(
            fontSize: 13.sp,
            fontWeight: FontWeight.w600,
            height: 1.2,
          ),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 8.h),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '待处理返佣队列',
                style: TextStyle(fontSize: 14.sp, color: const Color(0xFF666666)),
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const AppPageLoading()
                : _rows.isEmpty
                    ? Center(
                        child: Text(
                          '暂无待处理返佣',
                          style: TextStyle(fontSize: 14.sp, color: AppColors.textHint),
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
                                  '没有更多了，共 ${_rows.length} 条',
                                  style: TextStyle(
                                    fontSize: 12.sp,
                                    color: AppColors.textHint,
                                  ),
                                ),
                              ),
                            );
                          }
                          final m = _rows[i];
                          final id = int.tryParse('${m['accountId'] ?? ''}');
                          final accountIdStr = '${m['accountId'] ?? ''}'.trim();
                          final nick =
                              '${m['nickname'] ?? m['username'] ?? ''}'.trim();
                          final user =
                              '${m['username'] ?? m['accountId'] ?? ''}'.trim();
                          final titleName = nick.isEmpty ? user : nick;
                          void openLines() {
                            if (accountIdStr.isEmpty) return;
                            pushHostPage(
                              context,
                              HostRebateLinesPage(
                                roomId: widget.roomId,
                                accountId: accountIdStr,
                                displayName: titleName,
                                commission: true,
                              ),
                            );
                          }

                          return HostWhiteCard(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                InkWell(
                                  onTap: accountIdStr.isEmpty ? null : openLines,
                                  borderRadius: BorderRadius.circular(8.r),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              titleName,
                                              style: TextStyle(
                                                fontSize: 16.sp,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                            SizedBox(height: 2.h),
                                            Text(
                                              '用户ID: $user',
                                              style: TextStyle(
                                                fontSize: 12.sp,
                                                color: AppColors.textSecondary,
                                              ),
                                            ),
                                            SizedBox(height: 2.h),
                                            Text(
                                              '点击查看未返明细 ›',
                                              style: TextStyle(
                                                fontSize: 11.sp,
                                                color: AppColors.navBlue,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Container(
                                        padding: EdgeInsets.symmetric(
                                          horizontal: 8.w,
                                          vertical: 2.h,
                                        ),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFFFF3E0),
                                          borderRadius:
                                              BorderRadius.circular(10.r),
                                        ),
                                        child: Text(
                                          '待处理',
                                          style: TextStyle(
                                            fontSize: 11.sp,
                                            color: const Color(0xFFEF6C00),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                SizedBox(height: 12.h),
                                _grid(m),
                                SizedBox(height: 12.h),
                                SizedBox(
                                  width: double.infinity,
                                  child: TextButton(
                                    onPressed: _busy || id == null
                                        ? null
                                        : () => _pay([id], title: '返佣'),
                                    style: TextButton.styleFrom(
                                      backgroundColor: const Color(0xFFFCE4EC),
                                      foregroundColor: const Color(0xFFC2185B),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8.r),
                                      ),
                                    ),
                                    child: Text(
                                      '返佣',
                                      style: TextStyle(
                                        fontSize: 15.sp,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
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

  Widget _grid(Map<String, dynamic> m) {
    final ratio = m['commissionRatio'] ?? m['rebateRatio'];
    final cells = [
      (
        '返佣金额',
        hostNumStr(m['pendingRebate'], fraction: 2),
        const Color(0xFF2E7D32),
      ),
      ('比例', '${hostNumStr(ratio)}%', const Color(0xFF222222)),
      ('未返笔数', hostNumStr(m['pendingCount']), const Color(0xFF222222)),
      ('未返流水', hostNumStr(m['turnover'], fraction: 2), const Color(0xFF222222)),
      ('类型', '代理', const Color(0xFF222222)),
    ];
    return Wrap(
      spacing: 16.w,
      runSpacing: 8.h,
      children: [
        for (final c in cells)
          SizedBox(
            width: 140.w,
            child: Row(
              children: [
                Text(
                  '${c.$1} ',
                  style: TextStyle(fontSize: 12.sp, color: AppColors.textSecondary),
                ),
                Flexible(
                  child: Text(
                    c.$2,
                    style: TextStyle(
                      fontSize: 14.sp,
                      fontWeight: FontWeight.w700,
                      color: c.$3,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
