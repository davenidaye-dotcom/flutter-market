import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import '../../../core/audio/bgm_prompt.dart';
import '../../../config/env/env_config.dart';
import '../../../config/router/route_paths.dart';
import '../../../config/theme/app_colors.dart';
import '../../../shared/widgets/emulator_safe_text_field.dart';
import '../../../shared/widgets/gradient_background.dart';
import '../../../shared/widgets/page_app_bar.dart';
import '../../../shared/widgets/trial_account_tag.dart';
import '../../../shared/widgets/user_avatar.dart';
import '../../../data/repositories/providers.dart';
import '../../auth/providers/auth_session_provider.dart';
import '../../lottery/providers/lottery_live_provider.dart';
import '../../room/pages/room_shell_page.dart';
import '../app_release.dart';
import '../widgets/avatar_picker_sheet.dart';
import 'personal_settings_page.dart';

class ProfilePage extends ConsumerStatefulWidget {
  const ProfilePage({super.key, this.roomId});

  final String? roomId;

  @override
  ConsumerState<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends ConsumerState<ProfilePage>
    with AutomaticKeepAliveClientMixin {
  bool _bgMusic = true;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    Future.microtask(_loadBgm);
  }

  Future<void> _loadBgm() async {
    await BgmPrompt.loadLocal();
    if (!mounted) return;
    setState(() => _bgMusic = BgmPrompt.enabled);
    try {
      final on = await ref.read(memberRepositoryProvider).getBgmEnabled();
      await BgmPrompt.setEnabled(on);
      if (!mounted) return;
      setState(() => _bgMusic = on);
    } catch (_) {}
  }

  Future<void> _setBgm(bool value) async {
    final prev = _bgMusic;
    setState(() => _bgMusic = value);
    await BgmPrompt.setEnabled(value);
    try {
      await ref.read(memberRepositoryProvider).updateBgm(value);
    } catch (e) {
      if (!mounted) return;
      setState(() => _bgMusic = prev);
      await BgmPrompt.setEnabled(prev);
      AppToast.error(e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final user = ref.watch(authSessionProvider.select((s) => s.user));
    if (user == null) {
      return const Scaffold(body: Center(child: Text('未登录')));
    }
    final roomId = widget.roomId;
    final trial = roomId != null &&
        roomId.isNotEmpty &&
        ref.watch(roomLotteryLiveProvider(roomId).select((s) => s.isTrialAccount));

    return AppPageScaffold(
      body: GradientBackground(
        child: SafeArea(
          child: Column(
            children: [
              PageAppBar(
                title: '个人中心',
                onBack: roomId == null
                    ? () => appSafePop(context)
                    : () => goRoomLottery(context, roomId),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: EdgeInsets.symmetric(horizontal: 20.w),
                  child: Column(
                    children: [
                SizedBox(height: 12.h),
                GestureDetector(
                  onTap: () async {
                    final code = await showAvatarPickerSheet(
                      context,
                      currentCode: user.avatarUrl,
                    );
                    if (code == null || code.isEmpty) return;
                    try {
                      await ref.read(memberRepositoryProvider).updateAvatar(code);
                      ref.read(authSessionProvider.notifier).updateAvatar(code);
                      AppToast.success('头像已更新');
                    } catch (e) {
                      AppToast.error(e.toString());
                    }
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: UserAvatar(
                      codeOrUrl: user.avatarUrl,
                      radius: 40.r,
                    ),
                  ),
                ),
                SizedBox(height: 12.h),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Flexible(
                      child: Text(
                        user.nickname,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.w600),
                      ),
                    ),
                    if (trial) ...[
                      SizedBox(width: 6.w),
                      const TrialAccountTag(),
                    ],
                  ],
                ),
                SizedBox(height: 4.h),
                Text('(${user.username})', style: TextStyle(fontSize: 14.sp, color: AppColors.textSecondary)),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('ID:${user.id}', style: TextStyle(fontSize: 12.sp, color: AppColors.textHint)),
                    SizedBox(width: 4.w),
                    InkWell(
                      onTap: () => _copyId(user.id),
                      borderRadius: BorderRadius.circular(12.r),
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 2.h),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.copy_outlined, size: 13.sp, color: AppColors.primary),
                            SizedBox(width: 2.w),
                            Text('复制', style: TextStyle(fontSize: 12.sp, color: AppColors.primary)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 24.h),
                Material(
                  color: Colors.white.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(18.r),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      _tile('账号管理', onTap: () {
                        pushShellCover(context, const PersonalSettingsPage());
                      }),
                      const Divider(indent: 16, endIndent: 16, height: 1),
                      ListTile(
                        tileColor: Colors.transparent,
                        title: Text('背景音乐', style: TextStyle(fontSize: 15.sp)),
                        trailing: Switch(
                          value: _bgMusic,
                          onChanged: (v) => unawaited(_setBgm(v)),
                          activeThumbColor: Colors.white,
                          activeTrackColor: AppColors.primaryLight,
                        ),
                      ),
                      const Divider(indent: 16, endIndent: 16, height: 1),
                      ListTile(
                        tileColor: Colors.transparent,
                        title: Text('检查版本', style: TextStyle(fontSize: 15.sp)),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text('当前版本', style: TextStyle(fontSize: 11.sp, color: AppColors.textHint)),
                                Text(EnvConfig.appVersion, style: TextStyle(fontSize: 11.sp, color: AppColors.textHint)),
                              ],
                            ),
                            Icon(Icons.chevron_right, color: AppColors.textHint),
                          ],
                        ),
                        onTap: () => AppRelease.check(context),
                      ),
                      const Divider(indent: 16, endIndent: 16, height: 1),
                      _tile('分享App', onTap: () => AppRelease.share(context)),
                    ],
                  ),
                ),
                SizedBox(height: 28.h),
                GestureDetector(
                  onTap: () async {
                    dismissAllShellCovers();
                    final rid = roomId ?? user.roomId;
                    if (rid != null && rid.isNotEmpty) {
                      ref.invalidate(roomLotteryLiveProvider(rid));
                    }
                    await ref.read(authSessionProvider.notifier).logout();
                    if (context.mounted) context.go(RoutePaths.login);
                  },
                  child: Container(
                    width: double.infinity,
                    height: 48.h,
                    decoration: BoxDecoration(
                      color: const Color(0xFF70B6E8),
                      borderRadius: BorderRadius.circular(24.r),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.logout, color: Colors.white, size: 18.sp),
                        SizedBox(width: 8.w),
                        Text('退出登录', style: TextStyle(color: Colors.white, fontSize: 15.sp)),
                      ],
                    ),
                  ),
                ),
                SizedBox(height: 24.h),
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

  Future<void> _copyId(String id) async {
    if (id.isEmpty) {
      AppToast.info('暂无ID');
      return;
    }
    await Clipboard.setData(ClipboardData(text: id));
    AppToast.success('已复制ID');
  }

  Widget _tile(String label, {VoidCallback? onTap}) {
    return ListTile(
      onTap: onTap,
      tileColor: Colors.transparent,
      title: Text(label, style: TextStyle(fontSize: 15.sp)),
      trailing: Icon(Icons.chevron_right, color: AppColors.textHint),
    );
  }
}
