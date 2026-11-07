import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../config/theme/app_colors.dart';
import '../../../core/audio/bgm_prompt.dart';
import '../../../data/models/lottery_game_model.dart';
import '../../../shared/widgets/app_back.dart';
import '../../../shared/widgets/emulator_safe_text_field.dart';
import '../../../shared/format/game_series.dart';
import '../../../shared/widgets/gradient_background.dart';
import '../../../shared/widgets/page_app_bar.dart';
import '../../../shared/widgets/trial_account_tag.dart';
import '../../../shared/widgets/user_avatar.dart';
import '../../../data/repositories/providers.dart';
import '../../auth/providers/auth_session_provider.dart';
import '../../lottery/providers/lottery_live_provider.dart';
import '../../room/cs_pending_share.dart';
import '../../room/cs_rich.dart';
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
  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    Future.microtask(AppRelease.localVersion);
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
                onBack: () => appHandleBack(context),
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
                      _tile('背景音乐', onTap: () {
                        pushShellCover(
                          context,
                          BgmHubPage(roomId: roomId ?? '', host: false),
                        );
                      }),
                      const Divider(indent: 16, endIndent: 16, height: 1),
                      ListTile(
                        tileColor: Colors.transparent,
                        title: Text('检查版本', style: TextStyle(fontSize: 15.sp)),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ListenableBuilder(
                              listenable: AppRelease.builtinVersion,
                              builder: (context, _) => Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text('当前版本', style: TextStyle(fontSize: 11.sp, color: AppColors.textHint)),
                                  Text(
                                    AppRelease.displayVersion(AppRelease.builtinVersion.value),
                                    style: TextStyle(fontSize: 11.sp, color: AppColors.textHint),
                                  ),
                                ],
                              ),
                            ),
                            Icon(Icons.chevron_right, color: AppColors.textHint),
                          ],
                        ),
                        onTap: () => AppRelease.check(context),
                      ),
                      const Divider(indent: 16, endIndent: 16, height: 1),
                      _tile('分享App', onTap: () => AppRelease.share(context)),
                      if (roomId != null && roomId.isNotEmpty) ...[
                        const Divider(indent: 16, endIndent: 16, height: 1),
                        _tile('清空客服聊天记录', onTap: () => _clearCsHistory()),
                      ],
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
                    if (context.mounted) appGoLoginClearingStack(context);
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

  Future<void> _clearCsHistory() async {
    final ok = await confirmCsClearHistory(context);
    if (!ok || !mounted) return;
    try {
      await ref.read(memberRepositoryProvider).clearCsMessages();
      bumpCsHistoryRevision(ref);
      AppToast.info('已删除');
    } catch (e) {
      AppToast.error(e.toString());
    }
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

/// 背景音乐：游戏（按彩种的开奖、封盘）和消息。
class BgmHubPage extends StatelessWidget {
  const BgmHubPage({super.key, required this.roomId, required this.host});

  final String roomId;
  final bool host;

  @override
  Widget build(BuildContext context) {
    return _BgmScaffold(
      title: '背景音乐',
      child: _card(Column(
        children: [
          _row(
            '游戏背景音乐',
            onTap: () => pushShellCover(
              context,
              BgmGamesPage(roomId: roomId, host: host),
            ),
          ),
          const Divider(height: 1, indent: 16, endIndent: 16, color: AppColors.divider),
          _row(
            '消息背景音乐',
            onTap: () => pushShellCover(
              context,
              BgmMessagePage(host: host),
            ),
          ),
        ],
      )),
    );
  }
}

class BgmGamesPage extends ConsumerStatefulWidget {
  const BgmGamesPage({super.key, required this.roomId, required this.host});

  final String roomId;
  final bool host;

  @override
  ConsumerState<BgmGamesPage> createState() => _BgmGamesPageState();
}

class _BgmGamesPageState extends ConsumerState<BgmGamesPage> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      await BgmPrompt.loadLocal();
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final live = widget.roomId.isEmpty
        ? const <LotteryGameModel>[]
        : ref.watch(roomLotteryLiveProvider(widget.roomId).select((s) => s.games));
    final ready = widget.roomId.isEmpty
        ? true
        : ref.watch(roomLotteryLiveProvider(widget.roomId).select((s) => s.ready));
    final rows = _rows(live);

    return _BgmScaffold(
      title: '游戏背景音乐',
      child: !ready && rows.isEmpty
          ? Padding(
              padding: EdgeInsets.only(top: 80.h),
              child: const Center(
                heightFactor: 1,
                child: CircularProgressIndicator(),
              ),
            )
          : rows.isEmpty
              ? Padding(
                  padding: EdgeInsets.only(top: 48.h),
                  child: Text(
                    '当前房间没有开放的彩种',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14.sp, color: AppColors.textHint),
                  ),
                )
              : _card(Column(
                  children: [
                    for (var i = 0; i < rows.length; i++) ...[
                      if (i > 0)
                        const Divider(height: 1, indent: 16, endIndent: 16, color: AppColors.divider),
                      _row(
                        rows[i].name,
                        hint: _hint(rows[i].id),
                        onTap: () async {
                          await pushShellCover(
                            context,
                            BgmGamePage(
                              gameId: rows[i].id,
                              gameName: rows[i].name,
                              host: widget.host,
                            ),
                          );
                          if (mounted) setState(() {});
                        },
                      ),
                    ],
                  ],
                )),
    );
  }

  List<({String id, String name})> _rows(List<LotteryGameModel> live) {
    if (live.isEmpty) {
      if (widget.roomId.isNotEmpty) return const [];
      return [
        for (final entry in GameSeries.gameNames.entries)
          (id: entry.key, name: entry.value),
      ];
    }
    final pending = <String, LotteryGameModel>{
      for (final game in live) game.id.trim().toUpperCase(): game,
    };
    final ordered = <({String id, String name})>[];
    for (final id in GameSeries.gameNames.keys) {
      final game = pending.remove(id);
      if (game == null) continue;
      ordered.add((id: id, name: GameSeries.displayName(id, game.name)));
    }
    for (final game in pending.values) {
      final id = game.id.trim().toUpperCase();
      if (id.isEmpty) continue;
      ordered.add((id: id, name: GameSeries.displayName(id, game.name)));
    }
    return ordered;
  }

  String _hint(String id) {
    final draw = BgmPrompt.drawOn(id) ? '开' : '关';
    final seal = BgmPrompt.sealOn(id) ? '开' : '关';
    return '开奖$draw · 封盘$seal';
  }
}

class BgmGamePage extends StatefulWidget {
  const BgmGamePage({
    super.key,
    required this.gameId,
    required this.gameName,
    required this.host,
  });

  final String gameId;
  final String gameName;
  final bool host;

  @override
  State<BgmGamePage> createState() => _BgmGamePageState();
}

class _BgmGamePageState extends State<BgmGamePage> {
  late bool _draw;
  late bool _seal;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _draw = BgmPrompt.drawOn(widget.gameId);
    _seal = BgmPrompt.sealOn(widget.gameId);
    Future.microtask(() async {
      await BgmPrompt.loadLocal();
      if (!mounted) return;
      setState(() {
        _draw = BgmPrompt.drawOn(widget.gameId);
        _seal = BgmPrompt.sealOn(widget.gameId);
      });
    });
  }

  Future<void> _set({bool? draw, bool? seal}) async {
    if (_busy) return;
    final prevDraw = _draw;
    final prevSeal = _seal;
    setState(() {
      _busy = true;
      if (draw != null) _draw = draw;
      if (seal != null) _seal = seal;
    });
    try {
      await BgmPrompt.setGame(
        widget.gameId,
        draw: draw,
        seal: seal,
        host: widget.host,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _draw = prevDraw;
        _seal = prevSeal;
      });
      AppToast.error(e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _BgmScaffold(
      title: widget.gameName,
      child: _card(Column(
        children: [
          _switchRow('开奖音乐', _draw, (value) => unawaited(_set(draw: value))),
          const Divider(height: 1, indent: 16, endIndent: 16, color: AppColors.divider),
          _switchRow('封盘音乐', _seal, (value) => unawaited(_set(seal: value))),
        ],
      )),
    );
  }
}

class BgmMessagePage extends StatefulWidget {
  const BgmMessagePage({super.key, required this.host});

  final bool host;

  @override
  State<BgmMessagePage> createState() => _BgmMessagePageState();
}

class _BgmMessagePageState extends State<BgmMessagePage> {
  late bool _on;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _on = BgmPrompt.messageOn;
    Future.microtask(() async {
      await BgmPrompt.loadLocal();
      if (!mounted) return;
      setState(() => _on = BgmPrompt.messageOn);
    });
  }

  Future<void> _set(bool value) async {
    if (_busy) return;
    final prev = _on;
    setState(() {
      _busy = true;
      _on = value;
    });
    try {
      await BgmPrompt.setMessage(value, host: widget.host);
    } catch (e) {
      if (!mounted) return;
      setState(() => _on = prev);
      AppToast.error(e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _BgmScaffold(
      title: '消息背景音乐',
      child: _card(
        _switchRow('消息背景音乐', _on, (value) => unawaited(_set(value))),
      ),
    );
  }
}

class _BgmScaffold extends StatelessWidget {
  const _BgmScaffold({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AppPageScaffold(
      body: GradientBackground(
        child: SafeArea(
          child: Column(
            children: [
              PageAppBar(title: title, onBack: () => appHandleBack(context)),
              Expanded(
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 16.h),
                  child: child,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Widget _card(Widget child) {
  return Align(
    alignment: Alignment.topCenter,
    child: Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16.r),
      clipBehavior: Clip.antiAlias,
      child: child,
    ),
  );
}

Widget _row(String label, {String? hint, required VoidCallback onTap}) {
  return InkWell(
    onTap: onTap,
    child: Padding(
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(fontSize: 15.sp)),
                if (hint != null) ...[
                  SizedBox(height: 2.h),
                  Text(hint, style: TextStyle(fontSize: 12.sp, color: AppColors.textHint)),
                ],
              ],
            ),
          ),
          Icon(Icons.chevron_right, color: AppColors.textHint, size: 18.sp),
        ],
      ),
    ),
  );
}

Widget _switchRow(String label, bool value, ValueChanged<bool> onChanged) {
  return Padding(
    padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 6.h),
    child: Row(
      children: [
        Expanded(child: Text(label, style: TextStyle(fontSize: 15.sp))),
        Switch(
          value: value,
          onChanged: onChanged,
          activeThumbColor: Colors.white,
          activeTrackColor: AppColors.primaryLight,
        ),
      ],
    ),
  );
}
