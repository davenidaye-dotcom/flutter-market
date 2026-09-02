import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import '../../../config/env/env_config.dart';
import '../../../config/router/route_paths.dart';
import '../../../config/theme/app_colors.dart';
import '../../../data/models/app_role.dart';
import '../../../shared/widgets/app_logo.dart';
import '../../../shared/widgets/auth_card.dart';
import '../../../shared/widgets/glossy_button.dart';
import '../../../shared/widgets/gradient_background.dart';
import '../../../shared/widgets/emulator_safe_text_field.dart';
import '../../../shared/widgets/page_app_bar.dart';
import '../providers/auth_session_provider.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _usernameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _usernameFocus = FocusNode();
  final _passwordFocus = FocusNode();
  bool _remember = false;
  bool _loading = false;

  /// 登录入口模式：玩家 / 房主（同页切换）
  bool _hostMode = false;

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    _usernameFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  void _fillPlayerTest() {
    setState(() => _hostMode = false);
    _usernameCtrl.text = 'player001';
    _passwordCtrl.text = 'Pass1234';
  }

  void _fillHostTest() {
    setState(() => _hostMode = true);
    _usernameCtrl.text = 'abcd658';
    _passwordCtrl.text = 'Pass1234';
  }

  void _fillMemberTest() {
    setState(() => _hostMode = true);
    _usernameCtrl.text = 'member001';
    _passwordCtrl.text = 'Pass1234';
  }

  Future<void> _login() async {
    if (_usernameCtrl.text.trim().isEmpty || _passwordCtrl.text.isEmpty) {
      AppToast.info('请输入用户名和密码');
      return;
    }

    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _loading = true);
    try {
      await ref.read(authSessionProvider.notifier).login(
            username: _usernameCtrl.text.trim(),
            password: _passwordCtrl.text,
            captchaToken: '',
            expectedRole: _hostMode ? AppRole.host : AppRole.player,
          );
      if (!mounted) return;
      final user = ref.read(authSessionProvider).user;
      final dest = user?.isAgentSide == true
          ? RoutePaths.agentPersonalInfo(user?.roomId ?? '1001')
          : user?.isHostSide == true
              ? RoutePaths.hostLottery(user?.roomId ?? '1001')
              : RoutePaths.home;
      FocusManager.instance.primaryFocus?.unfocus();
      await Future<void>.delayed(Duration.zero);
      if (!context.mounted) return;
      context.go(dest);
    } catch (e) {
      AppToast.error(e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppPageScaffold(
      // 键盘盖住底部即可，不要 resize 触发 ScreenUtil 全树重建
      resizeToAvoidBottomInset: false,
      body: GradientBackground(
        child: SafeArea(
          child: Stack(
            children: [
              SingleChildScrollView(
                padding: EdgeInsets.symmetric(horizontal: 28.w),
                child: Column(
                  children: [
                    SizedBox(height: 48.h),
                    const AppLogoHeader(),
                    SizedBox(height: 32.h),
                    AuthCard(
                      tabText: _hostMode ? '房主登录' : '玩家登录',
                      child: Column(
                        children: [
                          _LoginField(
                            icon: Icons.person_outline,
                            hint: '请输入用户名',
                            controller: _usernameCtrl,
                            focusNode: _usernameFocus,
                            textInputAction: TextInputAction.next,
                            onSubmitted: (_) => _passwordFocus.requestFocus(),
                          ),
                          SizedBox(height: 8.h),
                          _LoginField(
                            icon: Icons.lock_outline,
                            hint: '请输入密码',
                            controller: _passwordCtrl,
                            focusNode: _passwordFocus,
                            obscure: true,
                            textInputAction: TextInputAction.done,
                            onSubmitted: (_) => _login(),
                          ),
                          SizedBox(height: 8.h),
                          Align(
                            alignment: Alignment.centerRight,
                            child: GestureDetector(
                              onTap: () => setState(() => _remember = !_remember),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 16.w,
                                    height: 16.w,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      border: Border.all(color: AppColors.primaryLight, width: 1.5),
                                      color: _remember ? AppColors.primaryLight : Colors.transparent,
                                    ),
                                    child: _remember
                                        ? Icon(Icons.check, size: 10.sp, color: Colors.white)
                                        : null,
                                  ),
                                  SizedBox(width: 6.w),
                                  Text(
                                    '记住密码',
                                    style: TextStyle(fontSize: 13.sp, color: AppColors.textPrimary),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          if (EnvConfig.isDebug) ...[
                            SizedBox(height: 12.h),
                            if (!_hostMode)
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton(
                                  onPressed: _loading ? null : _fillPlayerTest,
                                  child: const Text('填入 player001'),
                                ),
                              )
                            else
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton(
                                      onPressed: _loading ? null : _fillHostTest,
                                      child: const Text('填入 abcd658'),
                                    ),
                                  ),
                                  SizedBox(width: 8.w),
                                  Expanded(
                                    child: OutlinedButton(
                                      onPressed: _loading ? null : _fillMemberTest,
                                      child: const Text('填入 member001'),
                                    ),
                                  ),
                                ],
                              ),
                          ],
                          SizedBox(height: 24.h),
                          GlossyButton(text: '立即登录', onPressed: _login, loading: _loading),
                          if (EnvConfig.isDebug) ...[
                            SizedBox(height: 12.h),
                            Text(
                              _hostMode
                                  ? '代理：abcd658 / Pass1234\n代理会员：member001 / Pass1234'
                                  : '玩家：player001 / Pass1234',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 11.sp, color: AppColors.textHint, height: 1.4),
                            ),
                          ],
                          SizedBox(height: 28.h),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              if (_hostMode)
                                _footerAction(Icons.person_outline, '玩家', () {
                                  setState(() => _hostMode = false);
                                })
                              else
                                _footerAction(Icons.person, '房主', () {
                                  setState(() => _hostMode = true);
                                }),
                              if (!_hostMode)
                                _footerAction(
                                  Icons.person_add_alt_1,
                                  '注册',
                                  () => context.push(RoutePaths.register),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: 48.h),
                  ],
                ),
              ),
              Positioned(
                right: 16.w,
                bottom: 12.h,
                child: Text(
                  'v${EnvConfig.appVersion}',
                  style: TextStyle(fontSize: 11.sp, color: AppColors.textHint),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _footerAction(IconData icon, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 4.h),
        child: Column(
          children: [
            Icon(icon, color: AppColors.textSecondary, size: 28.sp),
            SizedBox(height: 4.h),
            Text(label, style: TextStyle(fontSize: 13.sp, color: AppColors.textSecondary)),
          ],
        ),
      ),
    );
  }
}

/// 独立输入框：打字只重建本行，不触发登录页根 setState
class _LoginField extends StatefulWidget {
  const _LoginField({
    required this.icon,
    required this.hint,
    required this.controller,
    required this.focusNode,
    this.obscure = false,
    this.textInputAction,
    this.onSubmitted,
  });

  final IconData icon;
  final String hint;
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool obscure;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;

  @override
  State<_LoginField> createState() => _LoginFieldState();
}

class _LoginFieldState extends State<_LoginField> {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Icon(widget.icon, color: AppColors.textSecondary, size: 20.sp),
            SizedBox(width: 12.w),
            Expanded(
              child: EmulatorSafeTextField(
                controller: widget.controller,
                focusNode: widget.focusNode,
                obscureText: widget.obscure,
                textInputAction: widget.textInputAction,
                onSubmitted: widget.onSubmitted,
                decoration: InputDecoration(hintText: widget.hint),
              ),
            ),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: widget.controller,
              builder: (_, value, _) {
                if (value.text.isEmpty) return const SizedBox.shrink();
                return GestureDetector(
                  onTap: widget.controller.clear,
                  child: Icon(Icons.cancel, color: AppColors.textHint, size: 18.sp),
                );
              },
            ),
          ],
        ),
        SizedBox(height: 12.h),
        const Divider(height: 1),
      ],
    );
  }
}
