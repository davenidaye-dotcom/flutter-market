import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../config/theme/app_colors.dart';
import '../../../data/models/user_model.dart';
import '../../../data/repositories/providers.dart';
import '../../../shared/widgets/emulator_safe_dialog.dart';
import '../../../shared/widgets/emulator_safe_text_field.dart';
import '../../../shared/widgets/gradient_background.dart';
import '../../../shared/widgets/page_app_bar.dart';
import '../../auth/providers/auth_session_provider.dart';
import 'change_password_page.dart';

class PersonalSettingsPage extends ConsumerWidget {
  const PersonalSettingsPage({super.key});

  Future<void> _editNickname(BuildContext context, WidgetRef ref, UserModel user) async {
    final ctrl = TextEditingController(text: user.nickname);
    final ok = await showEmulatorSafeDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('\u4fee\u6539\u6635\u79f0', style: TextStyle(fontSize: 16.sp)),
        content: EmulatorSafeTextField(
          controller: ctrl,
          maxLength: 32,
          decoration: const InputDecoration(hintText: 'nickname'),
        ),
        actions: [
          TextButton(onPressed: safeDialogPop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: safeDialogPop(ctx, true), child: const Text('OK')),
        ],
      ),
    );
    if (ok != true) {
      ctrl.dispose();
      return;
    }
    final nick = ctrl.text.trim();
    ctrl.dispose();
    if (nick.isEmpty) return;
    try {
      await ref.read(memberRepositoryProvider).updateNickname(nick);
      ref.read(authSessionProvider.notifier).updateNickname(nick);
      AppToast.success('\u4fee\u6539\u6210\u529f');
    } catch (e) {
      AppToast.error(e.toString());
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authSessionProvider.select((s) => s.user));
    if (user == null) {
      return const Scaffold(body: Center(child: Text('未登录')));
    }
    return AppPageScaffold(
      body: GradientBackground(
        child: SafeArea(
          child: Column(
            children: [
              PageAppBar(title: '\u4e2a\u4eba\u4fe1\u606f', onBack: () => appSafePop(context)),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 20.w),
                child: Material(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16.r),
                  clipBehavior: Clip.antiAlias,
                  elevation: 2,
                  shadowColor: Colors.black26,
                  child: Column(
                    children: [
                      _SettingsTile(
                        label: '\u5934\u50cf',
                        trailing: CircleAvatar(
                          radius: 20.r,
                          child: Icon(Icons.person, size: 20.sp),
                        ),
                        onTap: () => AppToast.info('\u5934\u50cf\u4fee\u6539\u5f85\u5bf9\u63a5'),
                      ),
                      const Divider(indent: 16, endIndent: 16, height: 1),
                      _SettingsTile(
                        label: '\u4fee\u6539\u6635\u79f0',
                        value: user.nickname,
                        onTap: () => _editNickname(context, ref, user),
                      ),
                      const Divider(indent: 16, endIndent: 16, height: 1),
                      _SettingsTile(
                        label: '\u4fee\u6539\u5bc6\u7801',
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const ChangePasswordPage(),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.label,
    this.value,
    this.trailing,
    this.onTap,
  });

  final String label;
  final String? value;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      tileColor: Colors.white,
      title: Text(label, style: TextStyle(fontSize: 15.sp)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (value != null)
            Text(value!, style: TextStyle(fontSize: 14.sp, color: AppColors.textSecondary)),
          if (trailing != null) ...[SizedBox(width: 8.w), trailing!],
          Icon(Icons.chevron_right, color: AppColors.textHint, size: 20.sp),
        ],
      ),
    );
  }
}
