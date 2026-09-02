import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../../config/theme/app_colors.dart';
import '../../../../data/repositories/providers.dart';
import '../../../../shared/widgets/page_app_bar.dart';
import '../../data/host_mock.dart';
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
      final data = await ref.read(ownerRepositoryProvider).getGamesSettings();
      var list = hostRowsOf(data);
      if (list.isEmpty) {
        // Fallback: owner games list
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
        title: '\u5173\u95ed\u5f69\u79cd',
        message: '\u786e\u5b9a\u5173\u95ed\u8be5\u5f69\u79cd\u5417\uff1f',
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
        'games': next
            .map((g) => {
                  'gameType': g['gameType'] ?? g['type'],
                  'enabled': g['enabled'] == true,
                })
            .toList(),
      });
      AppToast.success(value ? '\u5df2\u5f00\u542f' : '\u5df2\u5173\u95ed');
    } catch (e) {
      AppToast.error(e.toString());
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return HostSubPageScaffold(
      title: '\u5f69\u79cd\u7ba1\u7406',
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _games.isEmpty
              ? Center(
                  child: Text(
                    '\u6682\u65e0\u6570\u636e',
                    style: TextStyle(fontSize: 14.sp, color: AppColors.textHint),
                  ),
                )
              : ListView.separated(
                  padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 16.h),
                  itemCount: _games.length,
                  separatorBuilder: (_, _) => SizedBox(height: 8.h),
                  itemBuilder: (_, i) {
                    final g = _games[i];
                    final name = (g['gameName'] ?? g['typeName'] ?? g['gameType'] ?? g['type'] ?? '')
                        .toString();
                    final enabled = g['enabled'] != false;
                    return HostWhiteCard(
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              name,
                              style: TextStyle(fontSize: 15.sp, color: AppColors.textPrimary),
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
