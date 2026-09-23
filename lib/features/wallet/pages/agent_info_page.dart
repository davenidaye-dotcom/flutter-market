import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../config/theme/app_colors.dart';
import '../../../data/repositories/providers.dart';
import '../../../shared/widgets/emulator_safe_text_field.dart';
import '../../../shared/widgets/gradient_background.dart';
import '../../../shared/widgets/page_app_bar.dart';
import '../widgets/date_range_filter.dart';
import '../../../shared/widgets/app_page_loading.dart';
import '../../host/data/host_mock.dart';

/// Agent info for player — GET /member/agent-info
class AgentInfoPage extends ConsumerStatefulWidget {
  const AgentInfoPage({super.key});

  @override
  ConsumerState<AgentInfoPage> createState() => _AgentInfoPageState();
}

class _AgentInfoPageState extends ConsumerState<AgentInfoPage>
    with DateRangePageMixin {
  Map<String, dynamic> _data = {};
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
      final data = await ref.read(memberRepositoryProvider).getAgentInfo(
            startDate: DateRangeFilter.format(start),
            endDate: DateRangeFilter.format(end),
          );
      if (!mounted) return;
      setState(() => _data = data);
    } catch (e) {
      if (!mounted) return;
      AppToast.error(e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _n(List<String> keys, {int fraction = 2}) {
    for (final k in keys) {
      if (_data[k] != null) return hostNumStr(_data[k], fraction: fraction);
      final s = _data['summary'];
      if (s is Map && s[k] != null) return hostNumStr(s[k], fraction: fraction);
    }
    return fraction <= 0 ? '0' : '0.00';
  }

  List<Map<String, dynamic>> get _rows {
    final raw = _data['rows'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  Future<void> _copyId(String id) async {
    if (id.isEmpty) {
      AppToast.info('暂无ID');
      return;
    }
    await Clipboard.setData(ClipboardData(text: id));
    AppToast.success('已复制ID');
  }

  @override
  Widget build(BuildContext context) {
    final blue = AppColors.navBlue;
    return AppPageScaffold(
      body: GradientBackground(
        child: SafeArea(
          child: Column(
            children: [
              PageAppBar(title: '代理信息', onBack: () => appSafePop(context)),
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
              SizedBox(height: 12.h),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12.w),
                  child: ReportCard(
                    child: _loading
                        ? const AppPageLoading()
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Padding(
                                padding: EdgeInsets.fromLTRB(8.w, 16.h, 8.w, 4.h),
                                child: Row(
                                  children: [
                                    _stat('已返佣金', _n(['paidCommission'])),
                                    _stat('待领取佣金', _n(['unpaidCommission'])),
                                  ],
                                ),
                              ),
                              Padding(
                                padding: EdgeInsets.fromLTRB(8.w, 8.h, 8.w, 12.h),
                                child: Row(
                                  children: [
                                    _stat('旗下流水', _n(['subordinateTurnover', 'turnover'])),
                                    _stat(
                                      '下级人数',
                                      _n(['subordinateCount', 'memberCount'], fraction: 0),
                                    ),
                                  ],
                                ),
                              ),
                              const Divider(height: 1),
                              Padding(
                                padding: EdgeInsets.fromLTRB(12.w, 10.h, 12.w, 6.h),
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: Container(
                                    padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 6.h),
                                    decoration: BoxDecoration(
                                      color: blue,
                                      borderRadius: BorderRadius.circular(16.r),
                                    ),
                                    child: Text(
                                      '旗下玩家',
                                      style: TextStyle(
                                        fontSize: 13.sp,
                                        color: Colors.white,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              Expanded(
                                child: _rows.isEmpty
                                    ? Center(
                                        child: Text(
                                          '暂无旗下玩家',
                                          style: TextStyle(
                                            fontSize: 14.sp,
                                            color: AppColors.textHint,
                                          ),
                                        ),
                                      )
                                    : ListView.separated(
                                        padding: EdgeInsets.fromLTRB(12.w, 0, 12.w, 12.h),
                                        itemCount: _rows.length,
                                        separatorBuilder: (_, __) => SizedBox(height: 8.h),
                                        itemBuilder: (context, i) => _playerCard(_rows[i]),
                                      ),
                              ),
                            ],
                          ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _playerCard(Map<String, dynamic> r) {
    final name = (r['nickname'] ?? r['label'] ?? r['username'] ?? '').toString();
    final id = (r['accountId'] ?? r['id'] ?? '').toString();
    final turnover = hostNumStr(r['subordinateTurnover'] ?? r['turnover'], fraction: 2);
    final ratio = hostNumStr(r['commissionRatio'] ?? r['rebateRatio'], fraction: 2);
    final paid = hostNumStr(r['paidCommission'], fraction: 2);
    final unpaid = hostNumStr(r['unpaidCommission'], fraction: 2);
    return Container(
      padding: EdgeInsets.all(12.w),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(10.r),
        border: Border.all(color: const Color(0xFFE8EEF5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            name.isEmpty ? '-' : name,
            style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w600),
          ),
          SizedBox(height: 4.h),
          Row(
            children: [
              Expanded(
                child: Text(
                  'ID: ${id.isEmpty ? '-' : id}',
                  style: TextStyle(fontSize: 12.sp, color: AppColors.textSecondary),
                ),
              ),
              TextButton(
                onPressed: () => _copyId(id),
                style: TextButton.styleFrom(
                  minimumSize: Size(0, 28.h),
                  padding: EdgeInsets.symmetric(horizontal: 8.w),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text('复制', style: TextStyle(fontSize: 12.sp)),
              ),
            ],
          ),
          SizedBox(height: 6.h),
          Row(
            children: [
              _kv('玩家流水', turnover),
              _kv('抽佣比例', '$ratio%'),
            ],
          ),
          SizedBox(height: 6.h),
          Row(
            children: [
              _kv('已返佣', paid),
              _kv('未返佣', unpaid),
            ],
          ),
        ],
      ),
    );
  }

  Widget _kv(String label, String value) {
    return Expanded(
      child: Text.rich(
        TextSpan(
          text: '$label ',
          style: TextStyle(fontSize: 12.sp, color: AppColors.textSecondary),
          children: [
            TextSpan(
              text: value,
              style: TextStyle(
                fontSize: 13.sp,
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stat(String label, String value) {
    return Expanded(
      child: Column(
        children: [
          Text(label, style: TextStyle(fontSize: 12.sp, color: AppColors.textSecondary)),
          SizedBox(height: 6.h),
          Text(value, style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
