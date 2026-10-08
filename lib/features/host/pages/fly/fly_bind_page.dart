import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../../config/theme/app_colors.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../data/repositories/providers.dart';
import '../../../../shared/widgets/emulator_safe_dialog.dart';
import '../../../../shared/widgets/emulator_safe_text_field.dart';
import '../../../../shared/widgets/page_app_bar.dart';
import '../../widgets/host_ui.dart';

/// 绑定代理会员。首次绑定或后台/上级改密后须设新密码再绑。
class FlyBindPage extends ConsumerStatefulWidget {
  const FlyBindPage({super.key, required this.roomId});
  final String roomId;

  @override
  ConsumerState<FlyBindPage> createState() => _FlyBindPageState();
}

class _FlyBindPageState extends ConsumerState<FlyBindPage> {
  final _accountCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _obscure = true;
  bool _submitting = false;
  bool? _needChangePassword;

  @override
  void dispose() {
    _accountCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _refreshPrecheck() async {
    final username = _accountCtrl.text.trim();
    if (username.isEmpty) {
      setState(() => _needChangePassword = null);
      return;
    }
    try {
      final data = await ref.read(ownerRepositoryProvider).precheckFeipanBind(username);
      if (!mounted) return;
      setState(() => _needChangePassword = data['needChangePassword'] == true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _needChangePassword = null);
    }
  }

  Future<void> _onPrimary() async {
    final username = _accountCtrl.text.trim();
    final password = _passwordCtrl.text;
    if (username.isEmpty || password.isEmpty) {
      AppToast.info('请填写代理会员账号和密码');
      return;
    }
    if (_submitting) return;

    var need = _needChangePassword;
    if (need == null) {
      setState(() => _submitting = true);
      try {
        final data = await ref.read(ownerRepositoryProvider).precheckFeipanBind(username);
        need = data['needChangePassword'] == true;
        if (mounted) {
          setState(() {
            _needChangePassword = need;
            _submitting = false;
          });
        }
      } on ApiException catch (e) {
        if (mounted) {
          setState(() => _submitting = false);
          AppToast.error(e.message);
        }
        return;
      } catch (e) {
        if (mounted) {
          setState(() => _submitting = false);
          AppToast.error(e.toString());
        }
        return;
      }
    }

    if (need == true) {
      final neu = await _askNewPassword();
      if (neu == null || !mounted) return;
      await _bind(
        username: username,
        password: password,
        newPassword: neu.$1,
        confirmPassword: neu.$2,
      );
      return;
    }

    await _bind(username: username, password: password);
  }

  Future<(String, String)?> _askNewPassword() async {
    final newCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    final ok = await showEmulatorSafeDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('请设置新密码', textAlign: TextAlign.center),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '该代理会员首次绑定或后台/上级刚改过密码，须设置新密码后才能绑定。',
              style: TextStyle(fontSize: 13.sp, color: AppColors.textSecondary),
            ),
            SizedBox(height: 12.h),
            EmulatorSafeTextField(
              controller: newCtrl,
              obscureText: true,
              decoration: const InputDecoration(hintText: '新密码（6–64 位）'),
            ),
            SizedBox(height: 8.h),
            EmulatorSafeTextField(
              controller: confirmCtrl,
              obscureText: true,
              decoration: const InputDecoration(hintText: '确认新密码'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('确定')),
        ],
      ),
    );
    final n = newCtrl.text;
    final c = confirmCtrl.text;
    newCtrl.dispose();
    confirmCtrl.dispose();
    if (ok != true) return null;
    if (n.length < 6 || n.length > 64) {
      AppToast.info('新密码需为6-64位');
      return null;
    }
    if (n != c) {
      AppToast.info('两次新密码不一致');
      return null;
    }
    return (n, c);
  }

  Future<void> _bind({
    required String username,
    required String password,
    String? newPassword,
    String? confirmPassword,
  }) async {
    if (_submitting) return;
    setState(() => _submitting = true);
    try {
      await ref.read(ownerRepositoryProvider).bindFeipan({
        'username': username,
        'password': password,
        if (newPassword != null) 'newPassword': newPassword,
        if (confirmPassword != null) 'confirmPassword': confirmPassword,
      });
      if (!mounted) return;
      AppToast.success('绑定成功');
      appSafePop(context);
    } on ApiException catch (e) {
      AppToast.error(e.message);
    } catch (e) {
      AppToast.error(e.toString());
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final need = _needChangePassword == true;
    final label = _submitting
        ? '处理中…'
        : (need ? '修改密码并绑定' : '登录并绑定');
    return HostSubPageScaffold(
      title: '绑定代理会员',
      body: ListView(
        padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 24.h),
        children: [
          Text(
            '绑定代理会员',
            style: TextStyle(
              fontSize: 15.sp,
              fontWeight: FontWeight.w600,
              color: AppColors.navBlue,
            ),
          ),
          SizedBox(height: 10.h),
          HostWhiteCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('代理会员账号', style: TextStyle(fontSize: 13.sp, color: AppColors.textSecondary)),
                SizedBox(height: 6.h),
                EmulatorSafeTextField(
                  controller: _accountCtrl,
                  textInputAction: TextInputAction.next,
                  onChanged: (_) {
                    if (_needChangePassword != null) {
                      setState(() => _needChangePassword = null);
                    }
                  },
                  onSubmitted: (_) => _refreshPrecheck(),
                  decoration: InputDecoration(
                    hintText: '请输入代理会员账号',
                    filled: true,
                    fillColor: const Color(0xFFF7F9FC),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 12.h),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10.r),
                      borderSide: const BorderSide(color: Color(0xFFE6EAF0)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10.r),
                      borderSide: const BorderSide(color: Color(0xFFE6EAF0)),
                    ),
                  ),
                ),
                SizedBox(height: 14.h),
                Text('代理会员密码', style: TextStyle(fontSize: 13.sp, color: AppColors.textSecondary)),
                SizedBox(height: 6.h),
                EmulatorSafeTextField(
                  controller: _passwordCtrl,
                  obscureText: _obscure,
                  decoration: InputDecoration(
                    hintText: '请输入代理会员密码',
                    filled: true,
                    fillColor: const Color(0xFFF7F9FC),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 12.h),
                    suffixIcon: IconButton(
                      onPressed: () => setState(() => _obscure = !_obscure),
                      icon: Icon(
                        _obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                        size: 18.sp,
                      ),
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10.r),
                      borderSide: const BorderSide(color: Color(0xFFE6EAF0)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10.r),
                      borderSide: const BorderSide(color: Color(0xFFE6EAF0)),
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: 20.h),
          HostPrimaryButton(
            label: label,
            enabled: !_submitting,
            onPressed: _onPrimary,
          ),
        ],
      ),
    );
  }
}
