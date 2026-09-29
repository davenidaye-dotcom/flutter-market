import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../config/theme/app_colors.dart';
import '../../../data/repositories/providers.dart';
import '../../../shared/widgets/emulator_safe_text_field.dart';
import '../../../shared/widgets/page_app_bar.dart';
import '../widgets/agent_ui.dart';

/// 下级额度：上分 / 下分胶囊 + 金额。
class AgentChildCreditPage extends ConsumerStatefulWidget {
  const AgentChildCreditPage({
    super.key,
    required this.accountId,
    required this.title,
    this.available,
  });

  final int accountId;
  final String title;
  final dynamic available;

  @override
  ConsumerState<AgentChildCreditPage> createState() => _AgentChildCreditPageState();
}

class _AgentChildCreditPageState extends ConsumerState<AgentChildCreditPage> {
  final _amtCtrl = TextEditingController();
  String _direction = 'UP';
  bool _saving = false;

  @override
  void dispose() {
    _amtCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_saving) return;
    final amount = num.tryParse(_amtCtrl.text.trim());
    if (amount == null || amount <= 0) {
      AppToast.error('请输入金额');
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(agentRepositoryProvider).transferCredit(
            targetAccountId: widget.accountId,
            direction: _direction,
            amount: amount,
          );
      ref.invalidate(agentHeaderProvider);
      AppToast.success('额度已更新');
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      AppToast.error(e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AgentPageFrame(
      title: '',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AgentBackTitle(title: '额度 · ${widget.title}'),
          Expanded(
            child: ListView(
              padding: EdgeInsets.only(top: 8.h, bottom: 16.h),
              children: [
                AgentSurface(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('方向', style: TextStyle(fontSize: 12.sp, color: AppColors.textSecondary)),
                      SizedBox(height: 8.h),
                      Row(
                        children: [
                          _pill('上分', 'UP'),
                          SizedBox(width: 8.w),
                          _pill('下分', 'DOWN'),
                        ],
                      ),
                      SizedBox(height: 14.h),
                      Row(
                        children: [
                          Text('对方可用', style: TextStyle(fontSize: 13.sp, color: AppColors.textSecondary)),
                          const Spacer(),
                          Text(
                            agentBalanceLabel(widget.available),
                            style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w700, color: AgentChrome.ink),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 10.h),
                AgentSurface(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('金额', style: TextStyle(fontSize: 12.sp, color: AppColors.textSecondary)),
                      SizedBox(height: 6.h),
                      Container(
                        height: 44.h,
                        padding: EdgeInsets.symmetric(horizontal: 10.w),
                        decoration: BoxDecoration(
                          color: AgentChrome.fieldBg,
                          borderRadius: BorderRadius.circular(8.r),
                          border: Border.all(color: AgentChrome.cardBorder),
                        ),
                        alignment: Alignment.centerLeft,
                        child: EmulatorSafeTextField(
                          controller: _amtCtrl,
                          enabled: !_saving,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                          ],
                          style: TextStyle(fontSize: 16.sp, color: AgentChrome.ink),
                          decoration: InputDecoration(
                            border: InputBorder.none,
                            isCollapsed: true,
                            hintText: '请输入',
                            hintStyle: TextStyle(fontSize: 14.sp, color: AppColors.textHint),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(12.w, 8.h, 12.w, 16.h),
            child: AgentTealButton(
              label: _saving ? '...' : '确定',
              block: true,
              onTap: _saving ? () {} : _submit,
            ),
          ),
        ],
      ),
    );
  }

  Widget _pill(String label, String value) {
    final on = _direction == value;
    return GestureDetector(
      onTap: _saving ? null : () => setState(() => _direction = value),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
        decoration: BoxDecoration(
          color: on ? AgentChrome.accent : Colors.white,
          borderRadius: BorderRadius.circular(20.r),
          border: Border.all(color: on ? AgentChrome.accent : AgentChrome.cardBorder),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 14.sp,
            fontWeight: FontWeight.w600,
            color: on ? Colors.white : AgentChrome.ink,
          ),
        ),
      ),
    );
  }
}
