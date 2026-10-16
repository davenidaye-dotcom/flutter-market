import 'package:flutter/material.dart';
import '../../../config/theme/app_colors.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../core/network/session_store.dart';
import '../../../data/models/wallet_model.dart';
import '../../../data/repositories/providers.dart';
import '../../../shared/format/display_number.dart';
import '../../../shared/widgets/app_empty_hint.dart';
import '../../../shared/widgets/app_page_loading.dart';
import '../../../shared/widgets/emulator_safe_text_field.dart';
import '../../../shared/widgets/gradient_background.dart';
import '../../../shared/widgets/page_app_bar.dart';
import '../../room/cs_share_helper.dart';
import '../utils/draw_snapshot_utils.dart';
import '../widgets/date_range_filter.dart';
import '../widgets/member_ledger_card.dart';

/// 上下分记录（申请记录）— 顶栏总资产与钱包中心一致，用 totalAssets
class ApplyRecordsPage extends ConsumerStatefulWidget {
  const ApplyRecordsPage({super.key});

  @override
  ConsumerState<ApplyRecordsPage> createState() => _ApplyRecordsPageState();
}

class _ApplyRecordsPageState extends ConsumerState<ApplyRecordsPage>
    with DateRangePageMixin {
  List<Map<String, dynamic>> _rows = [];
  double? _totalAssets;
  bool _loading = false;
  bool _loadingMore = false;
  bool _hasMore = true;
  int _page = 1;
  int _total = 0;
  static const _pageSize = 20;

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  @override
  void onQuery() {
    _load();
  }

  Future<void> _load({bool reset = true}) async {
    if (!reset) {
      if (!_hasMore || _loadingMore || _loading) return;
      setState(() => _loadingMore = true);
    } else {
      setState(() {
        _loading = true;
        _page = 1;
        _hasMore = true;
      });
    }
    final page = reset ? 1 : _page + 1;
    try {
      final roomId = SessionStore.instance.roomId ?? '';
      final appsFuture = ref.read(walletRepositoryProvider).getApplications(
            startDate: DateRangeFilter.format(start),
            endDate: DateRangeFilter.format(end),
            pageNum: page,
            pageSize: _pageSize,
          );
      final summaryFuture =
          ref.read(walletRepositoryProvider).getSummary(roomId);
      final data = await appsFuture;
      WalletSummaryModel? summary;
      try {
        summary = await summaryFuture;
      } catch (_) {
        summary = null;
      }
      final raw = data['rows'];
      final list = raw is List
          ? raw
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList()
          : <Map<String, dynamic>>[];
      if (!mounted) return;
      final total = int.tryParse('${data['total'] ?? list.length}') ?? list.length;
      setState(() {
        _rows = reset ? list : [..._rows, ...list];
        _page = page;
        _total = total;
        _hasMore = _rows.length < total && list.isNotEmpty;
        if (reset) _totalAssets = summary?.totalAssets;
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      AppToast.error(e.toString());
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadingMore = false;
        });
      }
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
    const brown = Color(0xFF7B4C38);
    return AppPageScaffold(
      body: GradientBackground(
        child: SafeArea(
          child: Column(
            children: [
              PageAppBar(
                title: '上下分记录',
                onBack: () => appSafePop(context),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 0),
                child: Row(
                  children: [
                    Text('总资产', style: TextStyle(fontSize: 14.sp, color: brown)),
                    const Spacer(),
                    Text(
                      _totalAssets == null ? '--' : displayNumber(_totalAssets),
                      style: TextStyle(
                        fontSize: 18.sp,
                        fontWeight: FontWeight.w600,
                        color: brown,
                      ),
                    ),
                  ],
                ),
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
                            itemCount: _rows.length + 1,
                            separatorBuilder: (_, i) =>
                                i >= _rows.length - 1 ? const SizedBox.shrink() : SizedBox(height: 10.h),
                            itemBuilder: (_, i) {
                              if (i == _rows.length) {
                                if (_hasMore && !_loadingMore) {
                                  WidgetsBinding.instance.addPostFrameCallback((_) {
                                    if (mounted) _load(reset: false);
                                  });
                                }
                                return Padding(
                                  padding: EdgeInsets.only(top: 8.h),
                                  child: Center(
                                    child: Text(
                                      _hasMore ? '加载中' : '没有更多了，共 $_total 条',
                                      style: TextStyle(fontSize: 12.sp, color: AppColors.textHint),
                                    ),
                                  ),
                                );
                              }
                              final r = _rows[i];
                              final type =
                                  '${r['applyType'] ?? r['type'] ?? ''}';
                              final status = '${r['status'] ?? ''}';
                              final appId =
                                  '${r['applicationId'] ?? r['id'] ?? ''}';
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
                                remark: ledgerRemarkLabel('${r['remark'] ?? ''}'),
                                onShareToCs: appId.isEmpty
                                    ? null
                                    : () => shareToCustomerService(
                                          context,
                                          ref,
                                          refType: 'SCORE_APP',
                                          refId: appId,
                                          preview:
                                              '${_applyTypeLabel(type)} $appId',
                                        ),
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
