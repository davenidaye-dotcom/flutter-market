import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../../config/theme/app_colors.dart';
import '../../../../data/repositories/providers.dart';
import '../../../../shared/widgets/page_app_bar.dart';
import '../../widgets/host_ui.dart';

/// Batch rebate — /owner/room/rebate/batch-preview + batch-advance
class HostBatchRebatePage extends ConsumerStatefulWidget {
  const HostBatchRebatePage({super.key, required this.roomId});
  final String roomId;

  @override
  ConsumerState<HostBatchRebatePage> createState() => _HostBatchRebatePageState();
}

class _HostBatchRebatePageState extends ConsumerState<HostBatchRebatePage> {
  int _eligibleCount = 0;
  double _pendingTotal = 0;
  List<int> _accountIds = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await ref.read(ownerRepositoryProvider).getRebateBatchPreview();
      final members = data['members'];
      final ids = <int>[];
      var total = 0.0;
      if (members is List) {
        for (final e in members) {
          if (e is! Map) continue;
          final m = Map<String, dynamic>.from(e);
          final pending = double.tryParse('${m['pendingRebate'] ?? 0}') ?? 0;
          if (pending <= 0) continue;
          final id = int.tryParse('${m['accountId'] ?? ''}');
          if (id == null) continue;
          ids.add(id);
          total += pending;
        }
      }
      if (!mounted) return;
      setState(() {
        _accountIds = ids;
        _eligibleCount = ids.length;
        _pendingTotal = total;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      AppToast.error(e.toString());
    }
  }

  Future<void> _execute() async {
    if (_accountIds.isEmpty) {
      AppToast.info('暂无可发放成员');
      return;
    }
    final ok = await hostConfirm(
      context,
      title: '批量反水',
      message:
          '确定向 $_eligibleCount 人发放反水，合计 ¥${_pendingTotal.toStringAsFixed(2)} 吗？',
    );
    if (!ok) return;
    try {
      final res = await ref.read(ownerRepositoryProvider).batchAdvanceRebate(
            accountIds: _accountIds,
            remark: 'batch-advance',
          );
      if (!mounted) return;
      final count = res['successCount'] ?? _eligibleCount;
      AppToast.success('发放成功，成功 $count 人');
      await _load();
    } catch (e) {
      AppToast.error(e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return HostSubPageScaffold(
      title: '批量反水',
      body: _loading
          ? const AppPageLoading()
          : ListView(
              padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 24.h),
              children: [
                HostWhiteCard(
                  child: Column(
                    children: [
                      _statRow('可发放人数', '$_eligibleCount 人'),
                      const Divider(height: 24, color: AppColors.divider),
                      _statRow('待发放总额', '¥${_pendingTotal.toStringAsFixed(2)}'),
                    ],
                  ),
                ),
                SizedBox(height: 12.h),
                Text(
                  '执行后将按当前反水规则一次性发放，请确认数据无误',
                  style: TextStyle(fontSize: 12.sp, color: AppColors.textHint),
                ),
              ],
            ),
      bottomBar: Padding(
        padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 16.h),
        child: HostPrimaryButton(
          label: '立即发放',
          onPressed: _loading ? null : _execute,
        ),
      ),
    );
  }

  Widget _statRow(String k, String v) {
    return Row(
      children: [
        Text(k, style: TextStyle(fontSize: 14.sp, color: AppColors.textSecondary)),
        const Spacer(),
        Text(
          v,
          style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
        ),
      ],
    );
  }
}
