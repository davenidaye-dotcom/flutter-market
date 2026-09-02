import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../config/theme/app_colors.dart';
import '../../../data/repositories/providers.dart';
import '../../../shared/widgets/glossy_button.dart';
import '../../../shared/widgets/emulator_safe_text_field.dart';
import '../../../shared/widgets/gradient_background.dart';
import '../../../shared/widgets/page_app_bar.dart';
import '../../auth/providers/auth_session_provider.dart';

class ChangePasswordPage extends ConsumerStatefulWidget {
  const ChangePasswordPage({super.key});

  @override
  ConsumerState<ChangePasswordPage> createState() => _ChangePasswordPageState();
}

class _ChangePasswordPageState extends ConsumerState<ChangePasswordPage> {
  final _oldCtrl = TextEditingController();
  final _newCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _oldCtrl.dispose();
    _newCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_oldCtrl.text.isEmpty || _newCtrl.text.isEmpty || _confirmCtrl.text.isEmpty) {
      AppToast.info('请完整填写密码信息');
      return;
    }
    if (_newCtrl.text.length < 6 || _newCtrl.text.length > 16) {
      AppToast.info('新密码需为6-16位');
      return;
    }
    if (_newCtrl.text != _confirmCtrl.text) {
      AppToast.info('两次新密码不一致');
      return;
    }

    // TODO: 后期可在此接入顶象二次验证
    setState(() => _loading = true);
    try {
      await ref.read(authRepositoryProvider).changePassword(
            oldPassword: _oldCtrl.text,
            newPassword: _newCtrl.text,
          );
      if (!mounted) return;
      AppToast.success('修改成功');
      appSafePop(context);
    } catch (e) {
      AppToast.error(e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authSessionProvider.select((s) => s.user));
    if (user == null) {
      return const Scaffold(body: Center(child: Text('未登录')));
    }
    return AppPageScaffold(
      body: GradientBackground(
        child: SafeArea(
          child: Column(
            children: [
              PageAppBar(title: '修改密码', onBack: () => appSafePop(context)),
              SizedBox(height: 16.h),
              Text('请为您的账号', style: TextStyle(fontSize: 14.sp, color: AppColors.textSecondary)),
              Text(user.username, style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w600)),
              Text('设置一个新的密码', style: TextStyle(fontSize: 14.sp, color: AppColors.textSecondary)),
              SizedBox(height: 24.h),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 24.w),
                child: Container(
                  padding: EdgeInsets.all(16.w),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(16.r),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 12),
                    ],
                  ),
                  child: Column(
                    children: [
                      _row('旧密码', '请输入旧密码', _oldCtrl),
                      _row('新密码', '请输入新密码', _newCtrl),
                      _row('确认密码', '请确认密码', _confirmCtrl, showDivider: false),
                    ],
                  ),
                ),
              ),
              SizedBox(height: 32.h),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 24.w),
                child: GlossyButton(
                  text: '确定',
                  onPressed: _submit,
                  loading: _loading,
                  colors: [AppColors.primaryLight, const Color(0xFF74B9FF)],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(String label, String hint, TextEditingController ctrl, {bool showDivider = true}) {
    return Column(
      children: [
        Row(
          children: [
            SizedBox(width: 72.w, child: Text(label, style: TextStyle(fontSize: 14.sp))),
            Expanded(
              child: EmulatorSafeTextField(
                controller: ctrl,
                obscureText: true,
                decoration: InputDecoration(hintText: hint),
              ),
            ),
          ],
        ),
        if (showDivider) ...[
          SizedBox(height: 12.h),
          const Divider(height: 1),
          SizedBox(height: 12.h),
        ],
      ],
    );
  }
}
