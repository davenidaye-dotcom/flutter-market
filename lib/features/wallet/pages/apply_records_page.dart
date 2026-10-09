import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../data/repositories/providers.dart';
import '../../../shared/widgets/app_empty_hint.dart';
import '../../../shared/widgets/gradient_background.dart';
import '../../../shared/widgets/page_app_bar.dart';
import '../utils/draw_snapshot_utils.dart';
import '../widgets/date_range_filter.dart';
import '../widgets/member_ledger_card.dart';
import '../../../shared/widgets/app_page_loading.dart';
import '../../../shared/widgets/emulator_safe_text_field.dart';

/// 上下分记录（申请记录）
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

  String _applyTypeLabel(String type) {
    switch (type.toUpperCase()) {
      case 'UP':
        return '上分';
      case 'DOWN':
        return '下分';
      case 'ENTER':
        return '进房';
      default:
        return type.isEmpty ? '申请' : type;
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
                title: '上下分记录',
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
                child: _loading
                    ? const AppPageLoading()
                    : _rows.isEmpty
                        ? const Center(child: AppEmptyHint())
                        : ListView.separated(
                            padding: EdgeInsets.fromLTRB(12.w, 0, 12.w, 12.h),
                            itemCount: _rows.length,
                            separatorBuilder: (_, _) => SizedBox(height: 10.h),
                            itemBuilder: (_, i) {
                              final r = _rows[i];
                              final type =
                                  '${r['applyType'] ?? r['type'] ?? ''}';
                              final status = '${r['status'] ?? ''}';
                              return MemberLedgerCard(
                                typeLabel: _applyTypeLabel(type),
                                amount: r['amount'] ?? r['points'],
                                toneKey: type.isNotEmpty ? type : status,
                                fields: [
                                  if (status.isNotEmpty)
                                    ('状态', applyStatusLabel(status)),
                                ],
                                time:
                                    '${r['createdAt'] ?? r['createTime'] ?? ''}',
                                remark: '${r['remark'] ?? ''}',
                              );
                            },
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
