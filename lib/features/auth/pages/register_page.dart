import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import '../../../config/router/route_paths.dart';
import '../../../config/theme/app_colors.dart';
import '../../../data/repositories/providers.dart';
import '../../../shared/widgets/auth_card.dart';
import '../../../shared/widgets/glossy_button.dart';
import '../../../shared/widgets/emulator_safe_text_field.dart';
import '../../../shared/widgets/gradient_background.dart';
import '../../../shared/widgets/page_app_bar.dart';

class RegisterPage extends ConsumerStatefulWidget {
  const RegisterPage({super.key});

  @override
  ConsumerState<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends ConsumerState<RegisterPage> {
  final _usernameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    final username = _usernameCtrl.text.trim();
    final password = _passwordCtrl.text;
    final confirm = _confirmCtrl.text;
    if (username.isEmpty || password.isEmpty || confirm.isEmpty) {
      AppToast.info('请完整填写注册信息');
      return;
    }
    if (password.length < 6 || password.length > 16) {
      AppToast.info('密码需为6-16位');
      return;
    }
    if (password != confirm) {
      AppToast.info('两次密码不一致');
      return;
    }

    setState(() => _loading = true);
    try {
      await ref
          .read(authRepositoryProvider)
          .register(username: username, password: password);
      if (!mounted) return;
      AppToast.success('注册成功');
      final account = (username: username, password: password);
      if (context.canPop()) {
        context.pop(account);
      } else {
        context.go(RoutePaths.login, extra: account);
      }
    } catch (e) {
      AppToast.error(e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppPageScaffold(
      // 和登录页一致：不让 Scaffold 缩高度，键盘高度用来把白框上移
      resizeToAvoidBottomInset: false,
      body: GradientBackground(
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final keyboard = MediaQuery.viewInsetsOf(context).bottom;
              final cardHeight = (constraints.maxHeight - keyboard).clamp(
                0.0,
                constraints.maxHeight,
              );
              return SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(28.w, 0, 28.w, keyboard),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: cardHeight),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      AuthCard(
                        tabText: '玩家注册',
                        child: Column(
                          children: [
                            _input(
                              Icons.person_outline,
                              '请输入用户名',
                              _usernameCtrl,
                            ),
                            _input(
                              Icons.lock_outline,
                              '6-16位字母和…',
                              _passwordCtrl,
                              obscure: true,
                            ),
                            _input(
                              Icons.lock_outline,
                              '6-16位字母和…',
                              _confirmCtrl,
                              obscure: true,
                            ),
                            SizedBox(height: 24.h),
                            GlossyButton(
                              text: '立即注册',
                              colors: const [
                                Color(0xFFC9A07A),
                                AppColors.accentBrown,
                              ],
                              onPressed: _register,
                              loading: _loading,
                            ),
                            SizedBox(height: 16.h),
                            GlossyButton(
                              text: '返回登录',
                              onPressed: () => appSafePop(context),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _input(
    IconData icon,
    String hint,
    TextEditingController ctrl, {
    bool obscure = false,
  }) {
    return Padding(
      padding: EdgeInsets.only(bottom: 8.h),
      child: Column(
        children: [
          Row(
            children: [
              Icon(icon, color: AppColors.textSecondary, size: 20.sp),
              SizedBox(width: 12.w),
              Expanded(
                child: EmulatorSafeTextField(
                  controller: ctrl,
                  obscureText: obscure,
                  secureKeyboard: obscure,
                  asciiKeyboard: true,
                  decoration: InputDecoration(hintText: hint),
                ),
              ),
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: ctrl,
                builder: (_, value, _) {
                  if (value.text.isEmpty) return const SizedBox.shrink();
                  return GestureDetector(
                    onTap: ctrl.clear,
                    child: Icon(
                      Icons.cancel,
                      color: AppColors.textHint,
                      size: 18.sp,
                    ),
                  );
                },
              ),
            ],
          ),
          SizedBox(height: 12.h),
          const Divider(height: 1),
        ],
      ),
    );
  }
}
