import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../../config/theme/app_colors.dart';
import '../../../../data/repositories/providers.dart';
import '../../../../shared/widgets/emulator_safe_text_field.dart';
import '../../../../shared/widgets/page_app_bar.dart';
import '../../data/host_mock.dart';
import '../../widgets/host_ui.dart';

/// Feipan bind — status / bind / unbind
class FlyBindPage extends ConsumerStatefulWidget {
  const FlyBindPage({super.key, required this.roomId});
  final String roomId;

  @override
  ConsumerState<FlyBindPage> createState() => _FlyBindPageState();
}

class _FlyBindPageState extends ConsumerState<FlyBindPage> {
  Map<String, dynamic> _status = {};
  bool _loading = true;
  final _accountCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();

  bool get _bound =>
      _status['bound'] == true ||
      (_status['status']?.toString().toUpperCase() == 'BOUND') ||
      (_status['bindingId']?.toString().isNotEmpty == true);

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

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await ref.read(ownerRepositoryProvider).getFeipanStatus();
      if (!mounted) return;
      setState(() {
        _status = data;
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
      AppToast.success('\u7ed1\u5b9a\u6210\u529f');
      await _load();
    } catch (e) {
      AppToast.error(e.toString());
    }
  }

  Future<void> _unbind() async {
    final ok = await hostConfirm(
      context,
      title: '\u89e3\u7ed1',
      message: '\u786e\u8ba4\u89e3\u7ed1\uff1f',
      danger: true,
    );
    if (!ok || !mounted) return;
    try {
      await ref.read(ownerRepositoryProvider).unbindFeipan();
      AppToast.success('\u5df2\u89e3\u7ed1');
      await _load();
    } catch (e) {
      AppToast.error(e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return HostSubPageScaffold(
      title: '\u7ed1\u5b9a\u4ee3\u7406\u4f1a\u5458',
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 24.h),
              children: [
                if (_bound) ...[
                  HostWhiteCard(
                    child: Column(
                      children: [
                        _row('\u8d26\u53f7/\u6635\u79f0', '${_status['account'] ?? _status['username'] ?? _status['displayName'] ?? '-'}'),
                        _divider(),
                        _row('\u72b6\u6001', '${_status['status'] ?? 'BOUND'}', valueColor: AppColors.success),
                        _divider(),
                        _row('\u4e0a\u7ea7\u94fe', '${_status['chain'] ?? _status['parentChain'] ?? '-'}'),
                        _divider(),
                        _row('\u53ef\u7528\u989d\u5ea6', hostNumStr(_status['balance'] ?? _status['credit'], fraction: 2)),
                        _divider(),
                        _row('\u7ed1\u5b9a\u65f6\u95f4', '${_status['bindTime'] ?? _status['boundAt'] ?? '-'}'),
                        _divider(),
                        _row('binding_id', '${_status['bindingId'] ?? _status['id'] ?? '-'}'),
                      ],
                    ),
                  ),
                  SizedBox(height: 16.h),
                  HostPrimaryButton(
                    label: '\u89e3\u7ed1',
                    onPressed: _unbind,
                    color: AppColors.danger,
                  ),
                ] else ...[
                  HostWhiteCard(
                    child: Column(
                      children: [
                        EmulatorSafeTextField(
                          controller: _accountCtrl,
                          decoration: const InputDecoration(labelText: 'username'),
                        ),
                        EmulatorSafeTextField(
                          controller: _passwordCtrl,
                          obscureText: true,
                          decoration: const InputDecoration(labelText: 'password'),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: 16.h),
                  HostPrimaryButton(label: '\u7ed1\u5b9a', onPressed: _bind),
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
