import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../../config/theme/app_colors.dart';
import '../../../../data/repositories/providers.dart';
import '../../../../shared/widgets/page_app_bar.dart';
import '../../data/host_mock.dart';
import '../../widgets/host_ui.dart';

String _feipanChangeTypeLabel(String? raw) {
  switch (raw?.toUpperCase()) {
    case 'UP':
      return '上分';
    case 'DOWN':
      return '下分';
    case 'FLIGHT_OCCUPY':
      return '飞单占用';
    case 'FLIGHT_RELEASE':
      return '占用释放';
    case 'FLIGHT_SETTLE_WIN':
      return '结算赢';
    case 'FLIGHT_SETTLE_LOSS':
      return '结算输';
    case 'ADJUST':
      return '调整';
    default:
      return raw?.isNotEmpty == true ? raw! : '—';
  }
}

/// Feipan points — GET /owner/feipan/points/changes
class FlyBalancePage extends ConsumerStatefulWidget {
  const FlyBalancePage({super.key, required this.roomId});
  final String roomId;

  @override
  ConsumerState<FlyBalancePage> createState() => _FlyBalancePageState();
}

class _FlyBalancePageState extends ConsumerState<FlyBalancePage> {
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;
  int _typeIndex = 0;

  static const _types = [
    '全部',
    '上分',
    '下分',
    '飞单占用',
    '占用释放',
    '结算赢',
    '结算输',
    '调整',
  ];
  static const _typeKeys = [
    'ALL',
    'UP',
    'DOWN',
    'FLIGHT_OCCUPY',
    'FLIGHT_RELEASE',
    'FLIGHT_SETTLE_WIN',
    'FLIGHT_SETTLE_LOSS',
    'ADJUST',
  ];

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await ref.read(ownerRepositoryProvider).getFeipanPointsChanges(
            changeType: _typeKeys[_typeIndex],
            pageSize: 50,
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

  @override
  Widget build(BuildContext context) {
    return HostSubPageScaffold(
      title: '飞盘额度变更',
      body: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 0),
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () async {
                      final i = await showModalBottomSheet<int>(
                        context: context,
                        backgroundColor: Colors.white,
                        builder: (ctx) {
                          final maxH = MediaQuery.sizeOf(ctx).height * 0.55;
                          return SafeArea(
                            child: ConstrainedBox(
                              constraints: BoxConstraints(maxHeight: maxH),
                              child: ListView.builder(
                                shrinkWrap: true,
                                itemCount: _types.length,
                                itemBuilder: (_, j) => ListTile(
                                  title: Text(_types[j]),
                                  selected: j == _typeIndex,
                                  onTap: () => Navigator.pop(ctx, j),
                                ),
                              ),
                            ),
                          );
                        },
                      );
                      if (i != null) {
                        setState(() => _typeIndex = i);
                        await _load();
                      }
                    },
                    child: Container(
                      height: 36.h,
                      padding: EdgeInsets.symmetric(horizontal: 10.w),
                      decoration: BoxDecoration(
                        border: Border.all(color: const Color(0xFFAAAAAA)),
                        borderRadius: BorderRadius.circular(6.r),
                        color: Colors.white,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(_types[_typeIndex], style: TextStyle(fontSize: 13.sp)),
                          ),
                          Icon(Icons.arrow_drop_down, size: 20.sp),
                        ],
                      ),
                    ),
                  ),
                ),
                SizedBox(width: 8.w),
                TextButton(onPressed: _load, child: const Text('刷新')),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const AppPageLoading()
                : _rows.isEmpty
                    ? Center(
                        child: Text('暂无数据', style: TextStyle(color: AppColors.textHint)),
                      )
                    : ListView.separated(
                        padding: EdgeInsets.all(16.w),
                        itemCount: _rows.length,
                        separatorBuilder: (_, _) => SizedBox(height: 8.h),
                        itemBuilder: (_, i) {
                          final r = _rows[i];
                          final type = '${r['changeType'] ?? ''}';
                          final amount = r['amount'] ?? '';
                          return HostWhiteCard(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${_feipanChangeTypeLabel(type)}  $amount',
                                  style: TextStyle(
                                    fontSize: 14.sp,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                SizedBox(height: 4.h),
                                Text(
                                  '总额后:${r['totalAfter'] ?? '—'}  占用后:${r['occupiedAfter'] ?? '—'}',
                                  style: TextStyle(
                                    fontSize: 12.sp,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                                if ('${r['remark'] ?? ''}'.isNotEmpty) ...[
                                  SizedBox(height: 2.h),
                                  Text(
                                    '${r['remark']}',
                                    style: TextStyle(fontSize: 12.sp, color: AppColors.textHint),
                                  ),
                                ],
                                SizedBox(height: 2.h),
                                Text(
                                  '${r['createdAt'] ?? ''}',
                                  style: TextStyle(fontSize: 12.sp, color: AppColors.textHint),
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
}
