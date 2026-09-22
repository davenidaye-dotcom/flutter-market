import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../../config/theme/app_colors.dart';
import '../../../../data/repositories/providers.dart';
import '../../../../shared/widgets/page_app_bar.dart';
import '../../data/host_mock.dart';
import '../../widgets/host_ui.dart';

/// 未回水按单明细 — GET /owner/room/rebate/lines?accountId=&unpaidOnly=true
class HostRebateLinesPage extends ConsumerStatefulWidget {
  const HostRebateLinesPage({
    super.key,
    required this.roomId,
    required this.accountId,
    this.displayName,
  });

  final String roomId;
  final String accountId;
  final String? displayName;

  @override
  ConsumerState<HostRebateLinesPage> createState() =>
      _HostRebateLinesPageState();
}

class _HostRebateLinesPageState extends ConsumerState<HostRebateLinesPage> {
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await ref.read(ownerRepositoryProvider).getRebateLines(
            accountId: widget.accountId,
            unpaidOnly: true,
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

  String get _title {
    final name = (widget.displayName ?? '').trim();
    if (name.isEmpty) return '未回明细';
    return '$name · 未回明细';
  }

  @override
  Widget build(BuildContext context) {
    return HostSubPageScaffold(
      title: _title,
      body: _loading
          ? const AppPageLoading()
          : _rows.isEmpty
              ? Center(
                  child: Text(
                    '暂无未回明细',
                    style: TextStyle(fontSize: 14.sp, color: AppColors.textHint),
                  ),
                )
              : ListView.separated(
                  padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 16.h),
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
                    final r = _rows[i];
                    final game = '${r['gameType'] ?? ''}'.trim();
                    final issue = '${r['issueNo'] ?? ''}'.trim();
                    final status = '${r['status'] ?? 'VALID'}'.toUpperCase();
                    return HostWhiteCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  issue.isEmpty
                                      ? (game.isEmpty ? '注单' : game)
                                      : '${game.isEmpty ? '' : '$game · '}第$issue期',
                                  style: TextStyle(
                                    fontSize: 14.sp,
                                    fontWeight: FontWeight.w700,
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
                          SizedBox(height: 8.h),
                          Wrap(
                            spacing: 14.w,
                            runSpacing: 6.h,
                            children: [
                              _kv('流水', hostNumStr(r['turnover'], fraction: 2)),
                              _kv('比例', '${hostNumStr(r['ratio'])}%'),
                              _kv('状态', status == 'VOID' ? '作废' : '有效'),
                              if ('${r['orderId'] ?? ''}'.trim().isNotEmpty)
                                _kv('注单', '${r['orderId']}'),
                            ],
                          ),
                          if ('${r['createdAt'] ?? ''}'.trim().isNotEmpty) ...[
                            SizedBox(height: 8.h),
                            Text(
                              '${r['createdAt']}',
                              style: TextStyle(
                                fontSize: 12.sp,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ],
                      ),
                    );
                  },
                ),
    );
  }

  Widget _kv(String label, String value) {
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '$label ',
            style: TextStyle(fontSize: 12.sp, color: AppColors.textSecondary),
          ),
          TextSpan(
            text: value,
            style: TextStyle(
              fontSize: 13.sp,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF222222),
            ),
          ),
        ],
      ),
    );
  }
}
