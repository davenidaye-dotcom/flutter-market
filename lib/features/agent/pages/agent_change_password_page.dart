import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import '../../../config/router/route_paths.dart';
import '../../../config/theme/app_colors.dart';
import '../../../data/repositories/providers.dart';
import '../../../shared/widgets/emulator_safe_text_field.dart';
import '../../../shared/widgets/page_app_bar.dart';
import '../../auth/providers/auth_session_provider.dart';
import '../widgets/agent_ui.dart';

/// 密码修改 — POST /auth/password/change（代理/代理会员）
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
  bool _loading = false;

  @override
  void dispose() {
    _oldCtrl.dispose();
    _newCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_loading) return;
    if (_oldCtrl.text.isEmpty || _newCtrl.text.isEmpty || _confirmCtrl.text.isEmpty) {
      AppToast.info('请填写完整');
      return;
    }
    if (_newCtrl.text.length < 6 || _newCtrl.text.length > 64) {
      AppToast.info('新密码需为6-64位');
      return;
    }
    if (_newCtrl.text != _confirmCtrl.text) {
      AppToast.error('两次新密码不一致');
      return;
    }
    setState(() => _loading = true);
    try {
      await ref.read(authRepositoryProvider).changePassword(
            oldPassword: _oldCtrl.text,
            newPassword: _newCtrl.text,
            confirmPassword: _confirmCtrl.text,
          );
      // 后端改密成功后会使 Token 失效
      await ref.read(authSessionProvider.notifier).logout();
      if (!mounted) return;
      AppToast.success('密码已修改，请重新登录');
      context.go(RoutePaths.login);
    } catch (e) {
      AppToast.error(e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final username = ref.watch(authSessionProvider.select((s) => s.user?.username ?? '—'));

    return AgentPageFrame(
      title: '修改密码',
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(0, 8.h, 0, 24.h),
        child: Column(
          children: [
            AgentSurface(
              child: Column(
                children: [
                  Text('请为您账号', style: TextStyle(fontSize: 13.sp, color: AppColors.textSecondary)),
                  SizedBox(height: 6.h),
                  Text(username, style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.w700, color: AgentChrome.ink)),
                  SizedBox(height: 6.h),
                  Text('设置一个新的密码', style: TextStyle(fontSize: 13.sp, color: AppColors.textSecondary)),
                ],
              ),
            ),
            SizedBox(height: 10.h),
            AgentSurface(
              child: Column(
                children: [
                  _field('旧密码', '请输入旧密码', _oldCtrl),
                  SizedBox(height: 8.h),
                  _field('新密码', '请输入新密码', _newCtrl, obscure: true),
                  SizedBox(height: 8.h),
                  _field('确认密码', '请确认密码', _confirmCtrl, obscure: true),
                ],
              ),
            ),
            SizedBox(height: 16.h),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 12.w),
              child: GestureDetector(
                onTap: _loading ? null : _submit,
                child: Container(
                  width: double.infinity,
                  height: 44.h,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AgentChrome.accent,
                    borderRadius: BorderRadius.circular(8.r),
                  ),
                  child: _loading
                      ? SizedBox(
                          width: 22.w,
                          height: 22.w,
                          child: const CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : Text('确定', style: TextStyle(fontSize: 16.sp, color: Colors.white, fontWeight: FontWeight.w600)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(String label, String hint, TextEditingController ctrl, {bool obscure = false}) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 2.h),
      decoration: BoxDecoration(
        color: AgentChrome.fieldBg,
        borderRadius: BorderRadius.circular(8.r),
        border: Border.all(color: AgentChrome.cardBorder),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 72.w,
            child: Text(label, style: TextStyle(fontSize: 14.sp, color: AgentChrome.ink)),
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
    );
  }
}
