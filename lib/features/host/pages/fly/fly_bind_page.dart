import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../../config/theme/app_colors.dart';
import '../../../../data/repositories/providers.dart';
import '../../../../shared/widgets/emulator_safe_text_field.dart';
import '../../../../shared/widgets/page_app_bar.dart';
import '../../widgets/host_ui.dart';

/// 绑定代理会员。账号和密码校验通过后替换本房当前绑定。
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

  @override
  void dispose() {
    _accountCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _bind() async {
    final username = _accountCtrl.text.trim();
    final password = _passwordCtrl.text;
    if (username.isEmpty || password.isEmpty) {
      AppToast.info('请填写代理会员账号和密码');
      return;
    }
    if (_submitting) return;
    setState(() => _submitting = true);
    try {
      await ref.read(ownerRepositoryProvider).bindFeipan({
        'username': username,
        'password': password,
      });
      if (!mounted) return;
      AppToast.success('绑定成功');
      appSafePop(context);
    } catch (e) {
      AppToast.error(e.toString());
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
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
            label: _submitting ? '绑定中…' : '登录并绑定',
            enabled: !_submitting,
            onPressed: _bind,
          ),
        ],
      ),
    );
  }
}
