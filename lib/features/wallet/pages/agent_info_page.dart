import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../config/theme/app_colors.dart';
import '../../../data/repositories/providers.dart';
import '../../../shared/widgets/emulator_safe_text_field.dart';
import '../../../shared/widgets/gradient_background.dart';
import '../../../shared/widgets/page_app_bar.dart';
import '../widgets/date_range_filter.dart';
import '../../../shared/widgets/app_page_loading.dart';

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

  String _n(List<String> keys) {
    for (final k in keys) {
      if (_data[k] != null) return '${_data[k]}';
      final s = _data['summary'];
      if (s is Map && s[k] != null) return '${s[k]}';
    }
    return '0';
  }

  @override
  Widget build(BuildContext context) {
    return AppPageScaffold(
      body: GradientBackground(
        child: SafeArea(
          child: Column(
            children: [
              PageAppBar(title: '\u4ee3\u7406\u4fe1\u606f', onBack: () => appSafePop(context)),
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
                            children: [
                              Padding(
                                padding: EdgeInsets.symmetric(
                                  vertical: 16.h,
                                  horizontal: 8.w,
                                ),
                                child: Row(
                                  children: [
                                    _stat(
                                      '\u65d7\u4e0b\u6d41\u6c34',
                                      _n(['subordinateTurnover', 'turnover']),
                                    ),
                                    _stat(
                                      '\u8fd4\u4f63',
                                      _n(['rebate', 'agentRebate']),
                                    ),
                                    _stat(
                                      '\u4eba\u6570',
                                      _n(['subordinateCount', 'memberCount']),
                                    ),
                                  ],
                                ),
                              ),
                              const Divider(height: 1),
                              Expanded(
                                child: Center(
                                  child: Text(
                                    (_data['agentName'] ??
                                            _data['username'] ??
                                            '\u6682\u65e0\u660e\u7ec6')
                                        .toString(),
                                    style: TextStyle(
                                      fontSize: 14.sp,
                                      color: AppColors.textHint,
                                    ),
                                  ),
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
