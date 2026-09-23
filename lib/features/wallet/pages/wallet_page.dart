import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../config/theme/app_colors.dart';
import '../../../core/utils/submit_guard.dart';
import '../../../data/models/wallet_model.dart';
import '../../../data/repositories/providers.dart';
import '../../../shared/widgets/app_pull_refresh.dart';
import '../../../shared/widgets/emulator_safe_text_field.dart';
import '../../../shared/widgets/gradient_background.dart';
import '../../../shared/widgets/input_dialog.dart';
import '../../../shared/widgets/page_app_bar.dart';
import '../../room/pages/room_shell_page.dart';
import 'agent_info_page.dart';
import 'apply_records_page.dart';
import 'bet_records_page.dart';
import 'points_change_page.dart';
import 'welfare_report_page.dart';
import '../../../shared/widgets/app_page_loading.dart';

class WalletPage extends ConsumerStatefulWidget {
  const WalletPage({super.key, required this.roomId});

  final String roomId;

  @override
  ConsumerState<WalletPage> createState() => _WalletPageState();
}

class _WalletPageState extends ConsumerState<WalletPage>
    with AutomaticKeepAliveClientMixin {
  WalletSummaryModel? _summary;
  bool _loading = true;
  String? _error;
  final _applyGuard = SubmitGuard();
  final _applyBusy = ValueNotifier(false);
  bool _applyDialogOpen = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  @override
  void dispose() {
    _applyBusy.dispose();
    super.dispose();
  }

  Future<void> _load({bool fromPull = false}) async {
    if (!fromPull && mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    } else if (mounted) {
      setState(() => _error = null);
    }
    try {
      final s = await ref.read(walletRepositoryProvider).getSummary(widget.roomId);
      if (!mounted) return;
      setState(() => _summary = s);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _submitApply(String applyType) async {
    if (_summary?.isTrial == true) {
      AppToast.info(applyType == 'UP' ? '试玩账号不可上分' : '试玩账号不可下分');
      return;
    }
    if (_applyGuard.isBusy || _applyDialogOpen || _applyBusy.value) return;
    _applyDialogOpen = true;
    final label = applyType == 'UP' ? '上分' : '下分';
    try {
      final amountText = await showTextInputDialog(
        context: context,
        title: '申请$label',
        hint: '请输入$label金额',
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        digitsOnly: true,
      );
      if (amountText == null) return;
      final amount = double.tryParse(amountText);
      if (amount == null || amount <= 0) {
        AppToast.info('请输入有效金额');
        return;
      }
      _applyBusy.value = true;
      final done = await _applyGuard.run((requestId) async {
        await ref.read(walletRepositoryProvider).submitApplication(
              applyType: applyType,
              amount: amount,
              remark: 'wallet-$label',
              requestId: requestId,
            );
        return true;
      });
      if (done != true || !mounted) return;
      AppToast.success('$label申请已提交');
      pushShellCover(context, const ApplyRecordsPage());
      await _load();
    } catch (e) {
      AppToast.error(e.toString());
    } finally {
      _applyDialogOpen = false;
      _applyBusy.value = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    const brown = Color(0xFF7B4C38);
    final s = _summary;

    return AppPageScaffold(
      body: GradientBackground(
        child: SafeArea(
          child: Column(
            children: [
              PageAppBar(
                title: '钱包中心',
                onBack: () => goRoomLottery(context, widget.roomId),
              ),
              SizedBox(height: 12.h),
              Expanded(
                child: AppPullRefresh(
                  onRefresh: () => _load(fromPull: true),
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: EdgeInsets.symmetric(horizontal: 20.w),
                    children: [
                      Container(
                        width: double.infinity,
                        padding: EdgeInsets.fromLTRB(20.w, 28.h, 20.w, 24.h),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.75),
                          borderRadius: BorderRadius.circular(24.r),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.05),
                              blurRadius: 16,
                            ),
                          ],
                        ),
                        child: _loading
                            ? SizedBox(
                                height: 160.h,
                                child: const AppPageLoading(),
                              )
                            : _error != null
                                ? SizedBox(
                                    height: 160.h,
                                    child: Center(
                                      child: GestureDetector(
                                        onTap: _load,
                                        child: Text(
                                          '加载失败，点击重试',
                                          style: TextStyle(
                                            fontSize: 14.sp,
                                            color: AppColors.danger,
                                          ),
                                        ),
                                      ),
                                    ),
                                  )
                                : Column(
                                    children: [
                                      Text('总资产', style: TextStyle(fontSize: 15.sp, color: brown)),
                                      SizedBox(height: 8.h),
                                      Text(
                                        s == null ? '--' : '${s.availablePoints.toInt()}',
                                        style: TextStyle(
                                          fontSize: 34.sp,
                                          fontWeight: FontWeight.bold,
                                          color: brown,
                                        ),
                                      ),
                                      SizedBox(height: 22.h),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: _metric(
                                              '流水',
                                              s == null ? '--' : '${s.todayTurnover.toInt()}',
                                              brown,
                                            ),
                                          ),
                                          Expanded(
                                            child: _metric(
                                              '回水',
                                              s == null ? '--' : '${s.paidRebate.toInt()}',
                                              brown,
                                              valueColor: AppColors.success,
                                            ),
                                          ),
                                          Expanded(
                                            child: _metric(
                                              '盈亏',
                                              s == null ? '--' : '${s.todayWinLoss.toInt()}',
                                              brown,
                                              valueColor: AppColors.danger,
                                            ),
                                          ),
                                        ],
                                      ),
                                      SizedBox(height: 20.h),
                                      ValueListenableBuilder<bool>(
                                        valueListenable: _applyBusy,
                                        builder: (_, busy, __) {
                                          final trial = s?.isTrial == true;
                                          return Row(
                                            children: [
                                              Expanded(
                                                child: OutlinedButton(
                                                  onPressed: (busy || trial)
                                                      ? null
                                                      : () => _submitApply('UP'),
                                                  child: busy
                                                      ? SizedBox(
                                                          width: 18.w,
                                                          height: 18.w,
                                                          child: const CircularProgressIndicator(strokeWidth: 2),
                                                        )
                                                      : const Text('上分'),
                                                ),
                                              ),
                                              SizedBox(width: 12.w),
                                              Expanded(
                                                child: OutlinedButton(
                                                  onPressed: (busy || trial)
                                                      ? null
                                                      : () => _submitApply('DOWN'),
                                                  child: const Text('下分'),
                                                ),
                                              ),
                                            ],
                                          );
                                        },
                                      ),
                                      SizedBox(height: 20.h),
                                      _MenuGrid(roomId: widget.roomId),
                                    ],
                                  ),
                      ),
                      SizedBox(height: 24.h),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _metric(String label, String value, Color labelColor, {Color? valueColor}) {
    return Column(
      children: [
        Text(label, style: TextStyle(fontSize: 13.sp, color: labelColor)),
        SizedBox(height: 6.h),
        Text(
          value,
          style: TextStyle(
            fontSize: 18.sp,
            fontWeight: FontWeight.w600,
            color: valueColor ?? labelColor,
          ),
        ),
      ],
    );
  }
}

class _MenuGrid extends StatelessWidget {
  const _MenuGrid({required this.roomId});

  final String roomId;

  static const _items = [
    ('申请记录', Icons.confirmation_number_outlined),
    ('福利报表', Icons.card_giftcard),
    ('竞猜报表', Icons.show_chart),
    ('积分账变', Icons.monetization_on_outlined),
    ('代理信息', Icons.business_center),
  ];

  void _open(BuildContext context, String label) {
    final Widget? page = switch (label) {
      '申请记录' => const ApplyRecordsPage(),
      '福利报表' => const WelfareReportPage(),
      '竞猜报表' => const BetRecordsPage(),
      '积分账变' => const PointsChangePage(),
      '代理信息' => const AgentInfoPage(),
      _ => null,
    };
    if (page == null) return;
    pushShellCover(context, page);
  }

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 18.h,
        crossAxisSpacing: 8.w,
        childAspectRatio: 0.9,
      ),
      itemCount: _items.length,
      itemBuilder: (_, i) {
        final (label, icon) = _items[i];
        return GestureDetector(
          onTap: () => _open(context, label),
          child: Column(
            children: [
              Container(
                width: 52.w,
                height: 52.w,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFFBDE0FE),
                ),
                child: Icon(icon, color: Colors.white, size: 26.sp),
              ),
              SizedBox(height: 6.h),
              Text(label, style: TextStyle(fontSize: 12.sp, color: AppColors.textPrimary)),
            ],
          ),
        );
      },
    );
  }
}
