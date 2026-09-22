import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../config/theme/app_colors.dart';
import '../../../data/repositories/providers.dart';
import '../../../shared/widgets/app_empty_hint.dart';
import '../../../shared/widgets/emulator_safe_text_field.dart';
import '../../../shared/widgets/gradient_background.dart';
import '../../../shared/widgets/page_app_bar.dart';
import '../widgets/date_range_filter.dart';
import '../../../shared/widgets/app_page_loading.dart';

/// \u4e0a\u4e0b\u5206\u8bb0\u5f55\uff08\u7533\u8bf7\u8bb0\u5f55\uff09
class ApplyRecordsPage extends ConsumerStatefulWidget {
  const ApplyRecordsPage({super.key});

  @override
  ConsumerState<ApplyRecordsPage> createState() => _ApplyRecordsPageState();
}

class _ApplyRecordsPageState extends ConsumerState<ApplyRecordsPage>
    with DateRangePageMixin {
  List<Map<String, dynamic>> _rows = [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  @override
  void onQuery() {
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await ref.read(walletRepositoryProvider).getApplications(
            startDate: DateRangeFilter.format(start),
            endDate: DateRangeFilter.format(end),
          );
      final raw = data['rows'];
      final list = raw is List
          ? raw
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList()
          : <Map<String, dynamic>>[];
      if (!mounted) return;
      setState(() => _rows = list);
    } catch (e) {
      if (!mounted) return;
      AppToast.error(e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
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
                title: '\u4e0a\u4e0b\u5206\u8bb0\u5f55',
                onBack: () => appSafePop(context),
              ),
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
                    child: Column(
                      children: [
                        SizedBox(
                          height: 42.h,
                          child: Row(
                            children: [
                              _h('\u7c7b\u578b'),
                              _h('\u65f6\u95f4'),
                              _h('\u79ef\u5206'),
                              _h('\u72b6\u6001'),
                            ],
                          ),
                        ),
                        const Divider(height: 1, color: AppColors.divider),
                        Expanded(
                          child: _loading
                              ? const AppPageLoading()
                              : _rows.isEmpty
                                  ? const Center(child: AppEmptyHint())
                                  : ListView.separated(
                                      itemCount: _rows.length,
                                      separatorBuilder: (_, _) =>
                                          const Divider(height: 1, color: AppColors.divider),
                                      itemBuilder: (_, i) {
                                        final r = _rows[i];
                                        return SizedBox(
                                          height: 42.h,
                                          child: Row(
                                            children: [
                                              _c(_applyTypeLabel('${r['applyType'] ?? r['type'] ?? ''}')),
                                              _c('${r['createdAt'] ?? r['createTime'] ?? ''}'),
                                              _c('${r['amount'] ?? r['points'] ?? ''}'),
                                              _c('${r['status'] ?? ''}'),
                                            ],
                                          ),
                                        );
                                      },
                                    ),
                        ),
                      ],
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

  Widget _h(String t) => Expanded(
        child: Text(
          t,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14.sp,
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w500,
          ),
        ),
      );

  Widget _c(String t) => Expanded(
        child: Text(
          t,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 12.sp, color: AppColors.textPrimary),
        ),
      );

  String _applyTypeLabel(String type) {
    switch (type.toUpperCase()) {
      case 'UP':
        return '\u4e0a\u5206';
      case 'DOWN':
        return '\u4e0b\u5206';
      case 'ENTER':
        return '\u8fdb\u623f';
      default:
        return type;
    }
  }
}
