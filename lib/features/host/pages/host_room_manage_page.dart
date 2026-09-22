import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../config/theme/app_colors.dart';
import '../../../data/repositories/providers.dart';
import '../../../shared/widgets/app_pull_refresh.dart';
import '../../../shared/widgets/emulator_safe_text_field.dart';
import '../../../shared/widgets/gradient_background.dart';
import '../../../shared/widgets/page_app_bar.dart';
import '../../profile/pages/change_password_page.dart';
import '../../lottery/providers/lottery_live_provider.dart';
import '../widgets/host_ui.dart';
import 'host_shell_page.dart';
import 'room/host_agents_page.dart';
import 'room/host_announcements_page.dart';
import 'room/host_basic_settings_page.dart';
import 'room/host_games_manage_page.dart';
import 'room/host_members_page.dart';
import 'room/host_odds_limits_page.dart';
import 'room/host_rebate_hub_page.dart';
import 'room/host_operation_logs_page.dart';
import 'room/host_room_settings_page.dart';

/// Room manage — GET /owner/room + games/settings
class HostRoomManagePage extends ConsumerStatefulWidget {
  const HostRoomManagePage({super.key, required this.roomId});

  final String roomId;

  @override
  ConsumerState<HostRoomManagePage> createState() => _HostRoomManagePageState();
}

class _HostRoomManagePageState extends ConsumerState<HostRoomManagePage>
    with AutomaticKeepAliveClientMixin {
  bool _joinAudit = false;
  bool _betConfirm = false;
  bool _showQuick = true;
  List<(String, String, bool)> _games = [];
  Map<String, dynamic> _room = {};
  bool _loading = true;

  @override
  bool get wantKeepAlive => true;

  static const _navMenus = [
    ('\u623f\u95f4\u540d\u79f0\u4fee\u6539', 'name'),
    ('\u5bc6\u7801\u4fee\u6539', 'password'),
    ('\u623f\u95f4\u516c\u544a', 'announce'),
    ('\u623f\u95f4\u6210\u5458', 'members'),
    ('\u4ee3\u7406\u5217\u8868', 'agents'),
    ('\u8d54\u7387\u8bbe\u7f6e', 'odds'),
    ('\u56de\u6c34\u8bbe\u7f6e', 'rebate'),
    ('\u64cd\u4f5c\u65e5\u5fd7', 'logs'),
  ];

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  /// [fromPull] 为 true 时不要把 ListView 换成转圈，否则 RefreshIndicator 会卡死
  Future<void> _load({bool fromPull = false}) async {
    if (!fromPull && mounted) setState(() => _loading = true);
    try {
      final repo = ref.read(ownerRepositoryProvider);
      final room = await repo.getRoom();
      var list = await repo.getGamesSettings();
      if (list.isEmpty) list = await repo.getGames();
      if (!mounted) return;
      setState(() {
        _room = room;
        _betConfirm = room['betConfirm'] == true || room['betConfirm'] == 1;
        _games = list
            .map((g) => (
                  (g['gameType'] ?? g['type'] ?? '').toString(),
                  (g['gameName'] ?? g['typeName'] ?? g['gameType'] ?? g['type'] ?? '')
                      .toString(),
                  g['enabled'] != false,
                ))
            .where((e) => e.$1.isNotEmpty || e.$2.isNotEmpty)
            .toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      AppToast.error(e.toString());
    }
  }

  Future<void> _toggleGame(int i, bool v) async {
    if (!v) {
      final ok = await hostConfirm(
        context,
        title: '关闭彩种',
        message: '确定关闭该彩种吗？',
        danger: true,
      );
      if (!ok || !mounted) return;
    }
    final next = [..._games];
    next[i] = (next[i].$1, next[i].$2, v);
    setState(() => _games = next);
    try {
      await ref.read(ownerRepositoryProvider).updateGamesSettings({
        'items': next
            .map((g) => {
                  'gameType': g.$1.isEmpty ? g.$2 : g.$1,
                  'enabled': g.$3,
                })
            .toList(),
      });
      // 本端立刻刷新目录；会员端靠 WS afterCommit 推送
      unawaited(
        ref
            .read(roomLotteryLiveProvider(widget.roomId).notifier)
            .reloadGamesCatalog(),
      );
    } catch (e) {
      AppToast.error(e.toString());
      await _load();
    }
  }

  Future<void> _toggleBetConfirm(bool v) async {
    final prev = _betConfirm;
    setState(() => _betConfirm = v);
    try {
      await ref.read(ownerRepositoryProvider).updateRoomFlags(betConfirm: v);
      AppToast.success(v ? '已开启下注确认' : '已关闭下注确认');
    } catch (e) {
      if (mounted) setState(() => _betConfirm = prev);
      AppToast.error(e.toString());
    }
  }

  void _open(String key) {
    final id = widget.roomId;
    final Widget? page = switch (key) {
      'name' => HostBasicSettingsPage(roomId: id),
      'password' => const ChangePasswordPage(),
      'announce' => HostAnnouncementsPage(roomId: id),
      'members' => HostMembersPage(roomId: id),
      'agents' => HostAgentsPage(roomId: id),
      'odds' => HostOddsLimitsPage(roomId: id),
      'rebate' => HostRebateHubPage(roomId: id),
      'logs' => HostOperationLogsPage(roomId: id),
      _ => null,
    };
    if (page != null) pushHostPage(context, page);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final roomCode = (_room['roomCode'] ?? widget.roomId).toString();
    final roomId = roomCode.isEmpty ? '--' : roomCode;
    final expire =
        (_room['authExpire'] ?? _room['expireAt'] ?? _room['expireTime'] ?? '-')
            .toString();
    return AppPageScaffold(
      body: GradientBackground(
        child: SafeArea(
          child: Column(
            children: [
              PageAppBar(
                title: '\u623f\u95f4\u7ba1\u7406',
                onBack: () => goHostLottery(context, widget.roomId),
              ),
              Expanded(
                child: AppPullRefresh(
                  onRefresh: () => _load(fromPull: true),
                  child: _loading && _room.isEmpty
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: const [
                            SizedBox(height: 120),
                            Center(child: CircularProgressIndicator()),
                          ],
                        )
                      : ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: EdgeInsets.fromLTRB(16.w, 4.h, 16.w, 16.h),
                        children: [
                          GestureDetector(
                            onTap: () => pushHostPage(
                              context,
                              HostRoomSettingsPage(roomId: roomId),
                            ),
                            child: Padding(
                              padding: EdgeInsets.symmetric(vertical: 8.h),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    radius: 28.r,
                                    backgroundColor: const Color(0xFFFFCDD2),
                                    child: Icon(
                                      Icons.local_florist,
                                      color: Colors.pink.shade300,
                                      size: 28.sp,
                                    ),
                                  ),
                                  SizedBox(width: 12.w),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '\u623f\u95f4\u53f7\uff1a$roomId',
                                          style: TextStyle(fontSize: 15.sp),
                                        ),
                                        SizedBox(height: 4.h),
                                        Text(
                                          '\u5230\u671f\u65f6\u95f4:$expire',
                                          style: TextStyle(
                                            fontSize: 12.sp,
                                            color: AppColors.textSecondary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Icon(Icons.chevron_right,
                                      color: AppColors.textHint),
                                ],
                              ),
                            ),
                          ),
                          SizedBox(height: 8.h),
                          _card(
                            children: [
                              for (var i = 0; i < _navMenus.length; i++) ...[
                                if (i > 0)
                                  const Divider(
                                      height: 1, color: AppColors.divider),
                                _navTile(
                                  _navMenus[i].$1,
                                  () => _open(_navMenus[i].$2),
                                ),
                              ],
                              const Divider(
                                  height: 1, color: AppColors.divider),
                              _switchTile(
                                '\u8fdb\u623f\u5ba1\u6838',
                                _joinAudit,
                                (v) => setState(() => _joinAudit = v),
                              ),
                              const Divider(
                                  height: 1, color: AppColors.divider),
                              _switchTile(
                                '\u4e0b\u6ce8\u786e\u8ba4',
                                _betConfirm,
                                _toggleBetConfirm,
                              ),
                              const Divider(
                                  height: 1, color: AppColors.divider),
                              _switchTile(
                                '\u663e\u793a\u5feb\u6377',
                                _showQuick,
                                (v) => setState(() => _showQuick = v),
                              ),
                              Padding(
                                padding:
                                    EdgeInsets.fromLTRB(16.w, 14.h, 16.w, 6.h),
                                child: Row(
                                  children: [
                                    Text(
                                      '\u623f\u95f4\u6e38\u620f\u7ba1\u7406:\u5f00\u542f/\u5173\u95ed',
                                      style: TextStyle(
                                        fontSize: 12.sp,
                                        color: AppColors.textSecondary,
                                      ),
                                    ),
                                    const Spacer(),
                                    TextButton(
                                      onPressed: () => pushHostPage(
                                        context,
                                        HostGamesManagePage(roomId: roomId),
                                      ),
                                      child: const Text('\u5168\u90e8'),
                                    ),
                                  ],
                                ),
                              ),
                              for (var i = 0; i < _games.length; i++) ...[
                                if (i > 0)
                                  const Divider(
                                      height: 1, color: AppColors.divider),
                                _switchTile(
                                  _games[i].$2,
                                  _games[i].$3,
                                  (v) => _toggleGame(i, v),
                                ),
                              ],
                            ],
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

  Widget _card({required List<Widget> children}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16.r),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }

  Widget _navTile(String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
        child: Row(
          children: [
            Expanded(child: Text(label, style: TextStyle(fontSize: 15.sp))),
            Icon(Icons.chevron_right, size: 18.sp, color: AppColors.textHint),
          ],
        ),
      ),
    );
  }

  Widget _switchTile(String label, bool value, ValueChanged<bool> onChanged) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 4.h),
      child: Row(
        children: [
          Expanded(child: Text(label, style: TextStyle(fontSize: 15.sp))),
          Switch(
            value: value,
            activeThumbColor: Colors.white,
            activeTrackColor: AppColors.navBlue,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}
