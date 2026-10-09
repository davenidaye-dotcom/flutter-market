import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import '../../../config/env/env_config.dart';
import '../../profile/app_release.dart';
import '../../../config/router/route_paths.dart';
import '../../../config/theme/app_colors.dart';
import '../../../core/network/api_exception.dart';
import '../../../data/models/app_role.dart';
import '../../../shared/widgets/app_logo.dart';
import '../../../shared/widgets/auth_card.dart';
import '../../../shared/widgets/glossy_button.dart';
import '../../../shared/widgets/gradient_background.dart';
import '../../../shared/widgets/emulator_safe_text_field.dart';
import '../../../shared/widgets/page_app_bar.dart';
import '../login_remember_store.dart';
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
  String _version = EnvConfig.appVersion;

  /// 登录入口模式：玩家 / 经营端（房主+代理 portal）
  bool _hostMode = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      await _loadVersion();
      await _applyRemember();
    });
  }

  Future<void> _loadVersion() async {
    final version = await AppRelease.footerVersion();
    if (!mounted) return;
    setState(() => _version = version);
  }

  Future<void> _applyRemember() async {
    final saved = await LoginRememberStore.load(_hostMode);
    if (!mounted) return;
    setState(() {
      _remember = saved.remember;
      if (saved.remember) {
        _usernameCtrl.text = saved.username;
        _passwordCtrl.text = saved.password;
      } else {
        _usernameCtrl.clear();
        _passwordCtrl.clear();
      }
    });
  }

  Future<void> _switchHostMode(bool hostMode) async {
    if (_hostMode == hostMode) return;
    setState(() => _hostMode = hostMode);
    await _applyRemember();
  }

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    _usernameFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (_usernameCtrl.text.trim().isEmpty || _passwordCtrl.text.isEmpty) {
      AppToast.info('请输入用户名和密码');
      return;
    }

    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _loading = true);
    final username = _usernameCtrl.text.trim();
    final password = _passwordCtrl.text;
    try {
      await ref.read(authSessionProvider.notifier).login(
            username: username,
            password: password,
            captchaToken: '',
            expectedRole: _hostMode ? AppRole.host : AppRole.player,
          );
      if (!mounted) return;
      await LoginRememberStore.save(
        hostMode: _hostMode,
        remember: _remember,
        username: username,
        password: password,
      );
      final user = ref.read(authSessionProvider).user;
      FocusManager.instance.primaryFocus?.unfocus();
      SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
      // 等键盘收起再跳转，避免 IME viewport 风暴把进房页打卡死
      await Future<void>.delayed(const Duration(milliseconds: 80));
      if (!mounted) return;
      // 仅房主首次登录强制改密
      if (user?.isHostSide == true && user?.forceChangePassword == true) {
        context.go('${RoutePaths.changePassword}?force=1');
        return;
      }
      final dest = user?.isAgentSide == true
          ? RoutePaths.agentPersonalInfo(user?.roomId ?? '1001')
          : user?.isHostSide == true
              ? RoutePaths.hostLottery(user?.roomId ?? '1001')
              : RoutePaths.home;
      context.go(dest);
    } catch (e) {
      final msg = e is ApiException ? e.message : e.toString();
      AppToast.error(msg.isEmpty ? '系统维护中' : msg);
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
              LayoutBuilder(
                builder: (context, constraints) {
                  return SingleChildScrollView(
                    padding: EdgeInsets.symmetric(horizontal: 28.w),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minHeight: constraints.maxHeight),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(height: 24.h),
                          const AppLogoHeader(),
                          SizedBox(height: 28.h),
                          AuthCard(
                            tabText: _hostMode ? '房主/代理登录' : '玩家登录',
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
                                  child: Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      onTap: () {
                                        // 先收键盘，避免首点只被 IME 吃掉
                                        FocusManager.instance.primaryFocus?.unfocus();
                                        setState(() => _remember = !_remember);
                                      },
                                      borderRadius: BorderRadius.circular(20.r),
                                      child: Padding(
                                        padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 12.h),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Container(
                                              width: 20.w,
                                              height: 20.w,
                                              alignment: Alignment.center,
                                              decoration: BoxDecoration(
                                                shape: BoxShape.circle,
                                                border: Border.all(color: AppColors.primaryLight, width: 1.5),
                                                color: _remember ? AppColors.primaryLight : Colors.white,
                                              ),
                                              child: _remember
                                                  ? Icon(Icons.check, size: 12.sp, color: Colors.white)
                                                  : null,
                                            ),
                                            SizedBox(width: 8.w),
                                            Text(
                                              '记住密码',
                                              style: TextStyle(fontSize: 13.sp, color: AppColors.textPrimary),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                SizedBox(height: 24.h),
                                GlossyButton(text: '立即登录', onPressed: _login, loading: _loading),
                                SizedBox(height: 28.h),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                  children: [
                                    if (_hostMode)
                                      _footerAction(
                                        Icons.person_outline,
                                        '玩家',
                                        () => _switchHostMode(false),
                                      )
                                    else
                                      _footerAction(
                                        Icons.person,
                                        '房主',
                                        () => _switchHostMode(true),
                                      ),
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
                  );
                },
              ),
              Positioned(
                right: 16.w,
                bottom: 12.h,
                child: GestureDetector(
                  onTap: () => AppRelease.check(context),
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 6.h),
                    child: Text(
                      'v$_version',
                      style: TextStyle(fontSize: 11.sp, color: AppColors.textHint),
                    ),
                  ),
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
