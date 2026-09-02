import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../../config/theme/app_colors.dart';
import '../../../../data/repositories/providers.dart';
import '../../../../shared/widgets/emulator_safe_text_field.dart';
import '../../../../shared/widgets/page_app_bar.dart';
import '../../widgets/host_ui.dart';

/// Default rebate — GET/PUT /owner/room/rebate
class HostDefaultRebatePage extends ConsumerStatefulWidget {
  const HostDefaultRebatePage({super.key, required this.roomId});
  final String roomId;

  @override
  ConsumerState<HostDefaultRebatePage> createState() =>
      _HostDefaultRebatePageState();
}

class _HostDefaultRebatePageState extends ConsumerState<HostDefaultRebatePage> {
  final _ratio = TextEditingController(text: '0');
  final _minTurnover = TextEditingController(text: '0');
  bool _enabled = true;
  String _settleMode = 'DAILY';
  bool _loading = true;
  bool _saving = false;
  Map<String, dynamic> _raw = {};

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  @override
  void dispose() {
    _ratio.dispose();
    _minTurnover.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await ref.read(ownerRepositoryProvider).getRebate();
      if (!mounted) return;
      _raw = data;
      _enabled = data['enabled'] != false;
      _settleMode = (data['settleMode'] ?? 'DAILY').toString();
      _ratio.text = '${data['ratio'] ?? data['defaultRatio'] ?? 0}';
      _minTurnover.text = '${data['minTurnover'] ?? data['turnover'] ?? 0}';
      setState(() => _loading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      AppToast.error(e.toString());
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ref.read(ownerRepositoryProvider).updateRebate({
        ..._raw,
        'enabled': _enabled,
        'ratio': num.tryParse(_ratio.text) ?? 0,
        'minTurnover': num.tryParse(_minTurnover.text) ?? 0,
        'settleMode': _settleMode,
      });
      AppToast.success('\u4fdd\u5b58\u6210\u529f');
    } catch (e) {
      AppToast.error(e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return HostSubPageScaffold(
      title: '\u56de\u6c34\u8bbe\u7f6e',
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 24.h),
              children: [
                HostWhiteCard(
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Text('\u542f\u7528\u56de\u6c34', style: TextStyle(fontSize: 14.sp)),
                          const Spacer(),
                          Switch(
                            value: _enabled,
                            activeThumbColor: AppColors.navBlue,
                            onChanged: (v) => setState(() => _enabled = v),
                          ),
                        ],
                      ),
                      const Divider(height: 1),
                      _field('\u9ed8\u8ba4\u6bd4\u4f8b%', _ratio),
                      const Divider(height: 1),
                      _field('\u6253\u7801\u91cf\u95e8\u69db', _minTurnover),
                      const Divider(height: 1),
                      Row(
                        children: [
                          Text('\u7ed3\u7b97\u65b9\u5f0f', style: TextStyle(fontSize: 14.sp)),
                          const Spacer(),
                          DropdownButton<String>(
                            value: _settleMode,
                            items: const [
                              DropdownMenuItem(value: 'DAILY', child: Text('DAILY')),
                              DropdownMenuItem(value: 'WEEKLY', child: Text('WEEKLY')),
                              DropdownMenuItem(value: 'MANUAL', child: Text('MANUAL')),
                            ],
                            onChanged: (v) => setState(() => _settleMode = v ?? _settleMode),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 16.h),
                HostPrimaryButton(
                  label: _saving ? '...' : '\u4fdd\u5b58',
                  onPressed: _saving ? null : _save,
                ),
              ],
            ),
    );
  }

  Widget _field(String label, TextEditingController ctrl) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 8.h),
      child: Row(
        children: [
          Text(label, style: TextStyle(fontSize: 14.sp)),
          const Spacer(),
          SizedBox(
            width: 100.w,
            child: EmulatorSafeTextField(
              controller: ctrl,
              textAlign: TextAlign.right,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(isDense: true, border: InputBorder.none),
            ),
          ),
        ],
      ),
    );
  }
}
