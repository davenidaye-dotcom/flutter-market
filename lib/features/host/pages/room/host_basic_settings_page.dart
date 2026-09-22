import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../../config/theme/app_colors.dart';
import '../../../../data/repositories/providers.dart';
import '../../../../shared/widgets/emulator_safe_text_field.dart';
import '../../../../shared/widgets/page_app_bar.dart';
import '../../widgets/host_ui.dart';

/// Basic room settings from owner/room
class HostBasicSettingsPage extends ConsumerStatefulWidget {
  const HostBasicSettingsPage({super.key, required this.roomId});
  final String roomId;

  @override
  ConsumerState<HostBasicSettingsPage> createState() =>
      _HostBasicSettingsPageState();
}

class _HostBasicSettingsPageState extends ConsumerState<HostBasicSettingsPage> {
  final _nameCtrl = TextEditingController();
  final _pwdCtrl = TextEditingController();
  Map<String, dynamic> _room = {};
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _pwdCtrl.dispose();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent && mounted) setState(() => _loading = true);
    try {
      final data = await ref.read(ownerRepositoryProvider).getRoom();
      if (!mounted) return;
      _room = data;
      _nameCtrl.text =
          (data['roomName'] ?? data['name'] ?? '').toString();
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
      final name = _nameCtrl.text.trim();
      if (name.isNotEmpty) {
        await ref.read(ownerRepositoryProvider).updateRoomName(name);
      }
      if (_pwdCtrl.text.isNotEmpty) {
        await ref
            .read(ownerRepositoryProvider)
            .updateRoomPassword(_pwdCtrl.text);
      }
      AppToast.success('\u4fdd\u5b58\u6210\u529f');
      await _load(silent: true);
    } catch (e) {
      AppToast.error(e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final code = (_room['roomCode'] ?? widget.roomId).toString();
    final expire = (_room['authExpire'] ?? _room['expireAt'] ?? '-').toString();
    final status = (_room['status'] ?? _room['roomStatus'] ?? '-').toString();
    return HostSubPageScaffold(
      title: '\u57fa\u7840\u8bbe\u7f6e',
      body: _loading
          ? const AppPageLoading()
          : ListView(
              padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 24.h),
              children: [
                HostWhiteCard(
                  child: Column(
                    children: [
                      _editRow('\u623f\u95f4\u540d\u79f0', _nameCtrl),
                      _divider(),
                      _row('\u623f\u95f4\u53f7', code, readonly: true),
                      _divider(),
                      _row('\u6388\u6743\u5230\u671f\u65e5', expire, readonly: true),
                      _divider(),
                      _row('\u623f\u95f4\u72b6\u6001', status, readonly: true),
                      _divider(),
                      _editRow('\u8fdb\u623f\u5bc6\u7801', _pwdCtrl, obscure: true),
                    ],
                  ),
                ),
                SizedBox(height: 16.h),
                GestureDetector(
                  onTap: _saving ? null : _save,
                  child: Container(
                    height: 44.h,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.navBlue,
                      borderRadius: BorderRadius.circular(22.r),
                    ),
                    child: Text(
                      _saving ? '...' : '\u4fdd\u5b58',
                      style: TextStyle(fontSize: 16.sp, color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _row(String label, String value, {bool readonly = false}) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 10.h),
      child: Row(
        children: [
          Text(label, style: TextStyle(fontSize: 14.sp)),
          const Spacer(),
          Text(
            value,
            style: TextStyle(
              fontSize: 14.sp,
              color: readonly ? AppColors.textHint : AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _editRow(String label, TextEditingController ctrl,
      {bool obscure = false}) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4.h),
      child: Row(
        children: [
          Text(label, style: TextStyle(fontSize: 14.sp)),
          SizedBox(width: 12.w),
          Expanded(
            child: EmulatorSafeTextField(
              controller: ctrl,
              obscureText: obscure,
              textAlign: TextAlign.right,
              decoration: const InputDecoration(
                border: InputBorder.none,
                isDense: true,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _divider() => const Divider(height: 1, color: AppColors.divider);
}
