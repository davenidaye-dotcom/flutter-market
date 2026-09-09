import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../../config/theme/app_colors.dart';
import '../../../../data/repositories/providers.dart';
import '../../../../shared/widgets/page_app_bar.dart';
import '../../../lottery/providers/lottery_live_provider.dart';
import '../../widgets/host_ui.dart';

/// Game on/off — GET/PUT /owner/room/games/settings
class HostGamesManagePage extends ConsumerStatefulWidget {
  const HostGamesManagePage({super.key, required this.roomId});
  final String roomId;

  @override
  ConsumerState<HostGamesManagePage> createState() => _HostGamesManagePageState();
}

class _HostGamesManagePageState extends ConsumerState<HostGamesManagePage> {
  List<Map<String, dynamic>> _games = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      var list = await ref.read(ownerRepositoryProvider).getGamesSettings();
      if (list.isEmpty) {
        list = await ref.read(ownerRepositoryProvider).getGames();
      }
      if (!mounted) return;
      setState(() {
        _games = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      AppToast.error(e.toString());
    }
  }

  Future<void> _toggle(int index, bool value) async {
    if (!value) {
      final ok = await hostConfirm(
        context,
        title: '关闭彩种',
        message: '确定关闭该彩种吗？',
        danger: true,
      );
      if (!ok || !mounted) return;
    }
    final next = List<Map<String, dynamic>>.from(_games);
    next[index] = Map<String, dynamic>.from(next[index])
      ..['enabled'] = value;
    setState(() => _games = next);
    try {
      await ref.read(ownerRepositoryProvider).updateGamesSettings({
        'items': next
            .map((g) => {
                  'gameType': g['gameType'] ?? g['type'],
                  'enabled': _asEnabledFlag(g['enabled']),
                })
            .toList(),
      });
      // 本端立刻刷新大厅（开/关都走这里）；会员端靠 WS ROOM_GAMES_CHANGED
      unawaited(
        ref
            .read(roomLotteryLiveProvider(widget.roomId).notifier)
            .reloadGamesCatalog(),
      );
      AppToast.success(value ? '已开启' : '已关闭');
    } catch (e) {
      AppToast.error(e.toString());
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return HostSubPageScaffold(
      title: '彩种管理',
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _games.isEmpty
              ? Center(
                  child: Text(
                    '暂无数据',
                    style: TextStyle(fontSize: 14.sp, color: AppColors.textHint),
                  ),
                )
              : ListView.separated(
                  padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 16.h),
                  itemCount: _games.length,
                  separatorBuilder: (_, _) => SizedBox(height: 8.h),
                  itemBuilder: (_, i) {
                    final g = _games[i];
                    final name = (g['gameName'] ??
                            g['typeName'] ??
                            g['gameType'] ??
                            g['type'] ??
                            '')
                        .toString();
                    final enabled = _asEnabledFlag(g['enabled']);
                    return HostWhiteCard(
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              name,
                              style: TextStyle(
                                fontSize: 15.sp,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ),
                          Switch(
                            value: enabled,
                            activeThumbColor: AppColors.navBlue,
                            onChanged: (v) => _toggle(i, v),
                          ),
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}

bool _asEnabledFlag(dynamic v) {
  // 缺省视为开启（与历史 `!= false` 一致）；显式 0/false 才关闭
  if (v == null) return true;
  if (v == true || v == 1) return true;
  if (v == false || v == 0) return false;
  final s = '$v'.trim().toLowerCase();
  return s == 'true' || s == '1';
}
