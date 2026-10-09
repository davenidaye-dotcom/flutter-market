import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../../config/theme/app_colors.dart';
import '../../../../data/repositories/providers.dart';
import '../../../../shared/widgets/emulator_safe_text_field.dart';
import '../../../../shared/widgets/page_app_bar.dart';
import '../../../wallet/utils/draw_snapshot_utils.dart';
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
  final _oldPwdCtrl = TextEditingController();
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
    _oldPwdCtrl.dispose();
    super.dispose();
  }

  String _fmtExpire(dynamic raw) {
    if (raw == null) return '-';
    var s = '$raw'.trim();
    if (s.isEmpty || s == 'null' || s == '-') return '-';
    s = s.replaceFirst('T', ' ');
    final dot = s.indexOf('.');
    if (dot > 0) s = s.substring(0, dot);
    return s;
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent && mounted) setState(() => _loading = true);
    try {
      final data = await ref.read(ownerRepositoryProvider).getRoom();
      if (!mounted) return;
      _room = data;
      _nameCtrl.text =
          (data['roomName'] ?? data['name'] ?? '').toString();
      // 不把哈希写入输入框；是否已设置看 hasEnterPassword
      _pwdCtrl.clear();
      _oldPwdCtrl.clear();
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
        await ref.read(ownerRepositoryProvider).updateRoomPassword(
              _pwdCtrl.text,
              oldPassword: _hasPassword ? _oldPwdCtrl.text : null,
            );
      }
      AppToast.success('保存成功');
      await _load(silent: true);
    } catch (e) {
      AppToast.error(e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  bool get _hasPassword {
    final v = _room['hasEnterPassword'];
    if (v == true) return true;
    if (v == false) return false;
    return '$v'.toLowerCase() == 'true';
  }

  @override
  Widget build(BuildContext context) {
    final code = (_room['roomCode'] ?? widget.roomId).toString();
    final expire = _fmtExpire(
      _room['authExpire'] ?? _room['expireAt'] ?? _room['expireTime'],
    );
    final statusRaw =
        (_room['status'] ?? _room['roomStatus'] ?? '-').toString();
    final status =
        statusRaw == '-' ? '-' : roomStatusLabel(statusRaw);
    return HostSubPageScaffold(
      title: '基础设置',
      body: _loading
          ? const AppPageLoading()
          : ListView(
              padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 24.h),
              children: [
                HostWhiteCard(
                  child: Column(
                    children: [
                      _editRow('房间名称', _nameCtrl),
                      _divider(),
                      _row('房间号', code, readonly: true),
                      _divider(),
                      _row('授权到期日', expire, readonly: true),
                      _divider(),
                      _row('房间状态', status, readonly: true),
                      _divider(),
                      _passwordBlock(),
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
                      _saving ? '...' : '保存',
                      style: TextStyle(fontSize: 16.sp, color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _passwordBlock() {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text('进房密码', style: TextStyle(fontSize: 14.sp)),
              const Spacer(),
              Text(
                _hasPassword ? '已设置' : '未设置',
                style: TextStyle(
                  fontSize: 14.sp,
                  color: AppColors.textHint,
                ),
              ),
            ],
          ),
          if (_hasPassword) ...[
            SizedBox(height: 4.h),
            EmulatorSafeTextField(
              controller: _oldPwdCtrl,
              obscureText: false,
              textAlign: TextAlign.right,
              decoration: InputDecoration(
                border: InputBorder.none,
                isDense: true,
                hintText: '原进房密码',
                hintStyle: TextStyle(
                  fontSize: 13.sp,
                  color: AppColors.textHint,
                ),
              ),
            ),
          ],
          SizedBox(height: 4.h),
          EmulatorSafeTextField(
            controller: _pwdCtrl,
            obscureText: false,
            textAlign: TextAlign.right,
            decoration: InputDecoration(
              border: InputBorder.none,
              isDense: true,
              hintText: '新密码，留空则不修改',
              hintStyle: TextStyle(
                fontSize: 13.sp,
                color: AppColors.textHint,
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

  Widget _editRow(String label, TextEditingController ctrl) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4.h),
      child: Row(
        children: [
          Text(label, style: TextStyle(fontSize: 14.sp)),
          SizedBox(width: 12.w),
          Expanded(
            child: EmulatorSafeTextField(
              controller: ctrl,
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
