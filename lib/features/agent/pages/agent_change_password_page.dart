import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../config/theme/app_colors.dart';
import '../../../data/repositories/providers.dart';
import '../../../shared/widgets/emulator_safe_text_field.dart';
import '../../../shared/widgets/page_app_bar.dart';
import '../../auth/providers/auth_session_provider.dart';
import '../widgets/agent_ui.dart';

/// 密码修改 — 竞品「修改密码.png」
class AgentChangePasswordPage extends ConsumerStatefulWidget {
  const AgentChangePasswordPage({super.key, required this.roomId});

  final String roomId;

  @override
  ConsumerState<AgentChangePasswordPage> createState() => _AgentChangePasswordPageState();
}

class _AgentChangePasswordPageState extends ConsumerState<AgentChangePasswordPage> {
  final _oldCtrl = TextEditingController();
  final _newCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();

  @override
  void dispose() {
    _oldCtrl.dispose();
    _newCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_oldCtrl.text.isEmpty || _newCtrl.text.isEmpty || _confirmCtrl.text.isEmpty) {
      AppToast.info('请填写完整');
      return;
    }
    if (_newCtrl.text != _confirmCtrl.text) {
      AppToast.error('两次新密码不一致');
      return;
    }
    try {
      await ref.read(authRepositoryProvider).changePassword(
            oldPassword: _oldCtrl.text,
            newPassword: _newCtrl.text,
          );
      AppToast.success('密码已修改');
      _oldCtrl.clear();
      _newCtrl.clear();
      _confirmCtrl.clear();
    } catch (e) {
      AppToast.error(e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final username = ref.watch(authSessionProvider.select((s) => s.user?.username ?? 'abcd658'));

    return AgentPageFrame(
      title: '',
      child: SingleChildScrollView(
        padding: EdgeInsets.symmetric(horizontal: 20.w),
        child: Column(
          children: [
            SizedBox(height: 24.h),
            Text('请为您账号', style: TextStyle(fontSize: 14.sp, color: AppColors.textSecondary)),
            SizedBox(height: 8.h),
            Text(username, style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.w700)),
            SizedBox(height: 8.h),
            Text('设置一个新的密码', style: TextStyle(fontSize: 14.sp, color: AppColors.textSecondary)),
            SizedBox(height: 32.h),
            _field('旧密码', '请输入旧密码', _oldCtrl),
            _field('新密码', '请输入新密码', _newCtrl, obscure: true),
            _field('确认密码', '请确认密码', _confirmCtrl, obscure: true),
            SizedBox(height: 32.h),
            GestureDetector(
              onTap: _submit,
              child: Container(
                width: double.infinity,
                height: 44.h,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xFF66A3B0),
                  borderRadius: BorderRadius.circular(4.r),
                ),
                child: Text('确定', style: TextStyle(fontSize: 16.sp, color: Colors.white)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(String label, String hint, TextEditingController ctrl, {bool obscure = false}) {
    return Column(
      children: [
        Row(
          children: [
            SizedBox(
              width: 72.w,
              child: Text(label, style: TextStyle(fontSize: 14.sp)),
            ),
            Expanded(
              child: EmulatorSafeTextField(
                controller: ctrl,
                obscureText: obscure,
                decoration: InputDecoration(
                  hintText: hint,
                  hintStyle: TextStyle(fontSize: 14.sp, color: AppColors.textHint),
                  border: InputBorder.none,
                  isDense: true,
                ),
              ),
            ),
          ],
        ),
        const Divider(height: 1, color: AppColors.divider),
        SizedBox(height: 8.h),
      ],
    );
  }
}
