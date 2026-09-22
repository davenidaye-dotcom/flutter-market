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

/// Welfare — GET /member/welfare
class WelfareReportPage extends ConsumerStatefulWidget {
  const WelfareReportPage({super.key});

  @override
  ConsumerState<WelfareReportPage> createState() => _WelfareReportPageState();
}

class _WelfareReportPageState extends ConsumerState<WelfareReportPage>
    with DateRangePageMixin {
  Map<String, dynamic> _data = {};
  bool _loading = false;
  String _type = 'SUMMARY';

  static const _typeMap = {
    'SUMMARY': '汇总',
    'COMMISSION': '回水',
    'SPECIAL': '特殊返点',
    'INVITE': '邀请返点',
    'REDPACK': '红包',
    'AGENT_REBATE': '代理返佣',
    'RATIO': '返点比例',
  };

  static const _valueKeys = {
    'SUMMARY': 'total',
    'COMMISSION': 'commissionRebate',
    'SPECIAL': 'specialRebate',
    'INVITE': 'inviteRebate',
    'REDPACK': 'redpack',
    'AGENT_REBATE': 'agentRebate',
    'RATIO': 'rebateRatio',
  };

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
      final data = await ref.read(walletRepositoryProvider).getWelfare(
            type: _type,
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

  String _n(String key) {
    final v = _data[key];
    if (v != null) return '$v';
    final s = _data['summary'];
    if (s is Map && s[key] != null) return '${s[key]}';
    return '0';
  }

  @override
  Widget build(BuildContext context) {
    return AppPageScaffold(
      body: GradientBackground(
        child: SafeArea(
          child: Column(
            children: [
              PageAppBar(title: '\u798f\u5229\u62a5\u8868', onBack: () => appSafePop(context)),
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
                                  horizontal: 16.w,
                                  vertical: 14.h,
                                ),
                                child: Row(
                                  children: [
                                    Text(
                                      '\u603b\u8ba1',
                                      style: TextStyle(fontSize: 15.sp),
                                    ),
                                    const Spacer(),
                                    Text(
                                      _n('total'),
                                      style: TextStyle(fontSize: 15.sp),
                                    ),
                                  ],
                                ),
                              ),
                              const Divider(height: 1, color: AppColors.divider),
                              for (final e in _typeMap.entries)
                                InkWell(
                                  onTap: () {
                                    _type = e.key;
                                    _load();
                                  },
                                  child: Padding(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 16.w,
                                      vertical: 14.h,
                                    ),
                                    child: Row(
                                      children: [
                                        Text(e.value, style: TextStyle(fontSize: 14.sp)),
                                        const Spacer(),
                                        Text(
                                          _n(_valueKeys[e.key] ?? e.key.toLowerCase()),
                                          style: TextStyle(fontSize: 14.sp),
                                        ),
                                        Icon(
                                          Icons.chevron_right,
                                          size: 18.sp,
                                          color: AppColors.textHint,
                                        ),
                                      ],
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
}
