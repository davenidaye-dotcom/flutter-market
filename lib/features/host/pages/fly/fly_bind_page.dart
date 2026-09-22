import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../../config/theme/app_colors.dart';
import '../../../../data/repositories/providers.dart';
import '../../../../shared/widgets/emulator_safe_text_field.dart';
import '../../../../shared/widgets/page_app_bar.dart';
import '../../data/host_mock.dart';
import '../../widgets/host_ui.dart';

/// 绑定代理会员 — status / bind / unbind / flight-switch / credit
class FlyBindPage extends ConsumerStatefulWidget {
  const FlyBindPage({super.key, required this.roomId});
  final String roomId;

  @override
  ConsumerState<FlyBindPage> createState() => _FlyBindPageState();
}

class _FlyBindPageState extends ConsumerState<FlyBindPage> {
  Map<String, dynamic> _status = {};
  Map<String, dynamic> _credit = {};
  bool _loading = true;
  bool _switching = false;
  final _accountCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();

  bool get _bound => _status['bound'] == true;

  bool get _flightEnabled => _status['flightEnabled'] == true;

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  @override
  void dispose() {
    _accountCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent && mounted) setState(() => _loading = true);
    try {
      final repo = ref.read(ownerRepositoryProvider);
      final status = await repo.getFeipanStatus();
      Map<String, dynamic> credit = {};
      if (status['bound'] == true) {
        try {
          credit = await repo.getFeipanCredit();
        } catch (e) {
          // 绑定状态仍可展示；额度单独提示
          if (mounted) AppToast.error(e.toString());
        }
      }
      if (!mounted) return;
      setState(() {
        _status = status;
        _credit = credit;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      AppToast.error(e.toString());
    }
  }

  Future<void> _bind() async {
    try {
      await ref.read(ownerRepositoryProvider).bindFeipan({
        'username': _accountCtrl.text.trim(),
        'password': _passwordCtrl.text,
      });
      AppToast.success('绑定成功');
      await _load(silent: true);
    } catch (e) {
      AppToast.error(e.toString());
    }
  }

  Future<void> _unbind() async {
    final ok = await hostConfirm(
      context,
      title: '解绑',
      message: '确认解绑？解绑后房间下注将不再成功飞出。',
      danger: true,
    );
    if (!ok || !mounted) return;
    try {
      await ref.read(ownerRepositoryProvider).unbindFeipan();
      AppToast.success('已解绑');
      await _load(silent: true);
    } catch (e) {
      AppToast.error(e.toString());
    }
  }

  Future<void> _toggleFlight(bool enabled) async {
    if (_switching) return;
    setState(() => _switching = true);
    try {
      await ref.read(ownerRepositoryProvider).updateFeipanFlightSwitch(
            flightEnabled: enabled,
          );
      if (!mounted) return;
      setState(() {
        _status = {..._status, 'flightEnabled': enabled};
      });
      AppToast.success(enabled ? '飞单已开启' : '飞单已关闭');
    } catch (e) {
      AppToast.error(e.toString());
    } finally {
      if (mounted) setState(() => _switching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return HostSubPageScaffold(
      title: '绑定代理会员',
      body: _loading
          ? const AppPageLoading()
          : ListView(
              padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 24.h),
              children: [
                if (_bound) ...[
                  HostWhiteCard(
                    child: Column(
                      children: [
                        _row('代理会员', '${_status['username'] ?? '-'}'),
                        _divider(),
                        _row('状态', '已绑定', valueColor: AppColors.success),
                        _divider(),
                        _row('bindingId', '${_status['bindingId'] ?? '-'}'),
                        _divider(),
                        _row('agentAccountId', '${_status['agentAccountId'] ?? '-'}'),
                        _divider(),
                        _row('agentMemberId', '${_status['agentMemberId'] ?? '-'}'),
                        _divider(),
                        _row('可用额度', hostNumStr(_credit['available'], fraction: 2)),
                        _divider(),
                        _row('总额度', hostNumStr(_credit['totalCredit'], fraction: 2)),
                        _divider(),
                        _row('已占用', hostNumStr(_credit['occupied'], fraction: 2)),
                        _divider(),
                        _row('绑定时间', '${_status['boundAt'] ?? '-'}'),
                        _divider(),
                        Padding(
                          padding: EdgeInsets.symmetric(vertical: 4.h),
                          child: Row(
                            children: [
                              Text(
                                '飞单开关',
                                style: TextStyle(
                                  fontSize: 13.sp,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                              const Spacer(),
                              if (_switching)
                                SizedBox(
                                  width: 20.w,
                                  height: 20.w,
                                  child: const CircularProgressIndicator(strokeWidth: 2),
                                )
                              else
                                Switch(
                                  value: _flightEnabled,
                                  onChanged: _toggleFlight,
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: 16.h),
                  HostPrimaryButton(
                    label: '解绑',
                    onPressed: _unbind,
                    color: AppColors.danger,
                  ),
                ] else ...[
                  HostWhiteCard(
                    child: Column(
                      children: [
                        EmulatorSafeTextField(
                          controller: _accountCtrl,
                          decoration: const InputDecoration(
                            labelText: '代理会员账号',
                            hintText: '如 member001',
                          ),
                        ),
                        EmulatorSafeTextField(
                          controller: _passwordCtrl,
                          obscureText: true,
                          decoration: const InputDecoration(labelText: '密码'),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: 16.h),
                  HostPrimaryButton(label: '绑定', onPressed: _bind),
                ],
              ],
            ),
    );
  }

  Widget _row(String k, String v, {Color? valueColor}) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 10.h),
      child: Row(
        children: [
          Text(k, style: TextStyle(fontSize: 13.sp, color: AppColors.textSecondary)),
          const Spacer(),
          Flexible(
            child: Text(
              v,
              textAlign: TextAlign.right,
              style: TextStyle(fontSize: 13.sp, color: valueColor ?? AppColors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _divider() => const Divider(height: 1, color: AppColors.divider);
}
