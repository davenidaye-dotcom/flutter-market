import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../../data/repositories/providers.dart';
import '../../../../shared/widgets/emulator_safe_text_field.dart';
import '../../../../shared/widgets/page_app_bar.dart';
import '../../widgets/host_ui.dart';

/// Advance rebate — POST /owner/room/rebate/advance
class HostAdvanceRebatePage extends ConsumerStatefulWidget {
  const HostAdvanceRebatePage({super.key, required this.roomId});
  final String roomId;

  @override
  ConsumerState<HostAdvanceRebatePage> createState() =>
      _HostAdvanceRebatePageState();
}

class _HostAdvanceRebatePageState extends ConsumerState<HostAdvanceRebatePage> {
  final _ctrl = TextEditingController(text: '0');
  bool _saving = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ref.read(ownerRepositoryProvider).advanceRebate({
        'ratio': num.tryParse(_ctrl.text) ?? 0,
      });
      AppToast.success('\u5df2\u4fdd\u5b58');
    } catch (e) {
      AppToast.error(e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return HostSubPageScaffold(
      title: '\u63d0\u524d\u8fd4\u70b9',
      body: ListView(
        padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 24.h),
        children: [
          HostWhiteCard(
            child: Row(
              children: [
                Text('\u63d0\u524d\u8fd4\u70b9\u6bd4\u4f8b%', style: TextStyle(fontSize: 14.sp)),
                const Spacer(),
                SizedBox(
                  width: 80.w,
                  child: EmulatorSafeTextField(
                    controller: _ctrl,
                    textAlign: TextAlign.center,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      bottomBar: Padding(
        padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 16.h),
        child: HostPrimaryButton(
          label: _saving ? '...' : '\u4fdd\u5b58',
          onPressed: _saving ? null : _save,
        ),
      ),
    );
  }
}
