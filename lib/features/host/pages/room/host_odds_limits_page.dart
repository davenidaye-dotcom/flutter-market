import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../../config/theme/app_colors.dart';
import '../../../../data/repositories/providers.dart';
import '../../../../shared/widgets/app_pull_refresh.dart';
import '../../../../shared/widgets/page_app_bar.dart';
import '../../widgets/host_ui.dart';
import 'host_odds_edit_page.dart';

/// 赔率设置 — 彩种列表入口（竞品：图标 + 名称 + PK10 副标题）
class HostOddsLimitsPage extends ConsumerStatefulWidget {
  const HostOddsLimitsPage({super.key, required this.roomId});
  final String roomId;

  @override
  ConsumerState<HostOddsLimitsPage> createState() => _HostOddsLimitsPageState();
}

class _HostOddsLimitsPageState extends ConsumerState<HostOddsLimitsPage> {
  List<Map<String, dynamic>> _games = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  Future<void> _load({bool fromPull = false}) async {
    if (!fromPull && mounted) setState(() => _loading = true);
    try {
      var list = await ref.read(ownerRepositoryProvider).getGamesSettings();
      if (list.isEmpty) {
        list = await ref.read(ownerRepositoryProvider).getGames();
      }
      final enabled = list.where((g) => g['enabled'] != false).toList();
      if (!mounted) return;
      setState(() {
        _games = enabled.isNotEmpty ? enabled : list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      AppToast.error(e.toString());
    }
  }

  String _typeOf(Map<String, dynamic> g) =>
      (g['gameType'] ?? g['type'] ?? '').toString();

  String _nameOf(Map<String, dynamic> g) {
    final n = (g['gameName'] ?? g['typeName'] ?? g['gameType'] ?? g['type'] ?? '')
        .toString();
    return n.isEmpty ? _typeOf(g) : n;
  }

  /// 副标题：接口有 category 用接口，否则 PK10 类默认 PK10
  String _subtitleOf(Map<String, dynamic> g) {
    final raw = (g['category'] ??
            g['gameCategory'] ??
            g['groupName'] ??
            g['series'] ??
            '')
        .toString()
        .trim();
    if (raw.isNotEmpty) return raw;
    return 'PK10';
  }

  (IconData, Color) _iconOf(String name, String type) {
    final key = '${type}_$name'.toUpperCase();
    if (key.contains('飞艇') || key.contains('FT') || key.contains('AIR')) {
      return (Icons.flight_takeoff, const Color(0xFF5C6BC0));
    }
    if (key.contains('澳洲') || key.contains('AZXY') || key.contains('AUS')) {
      return (Icons.flag, const Color(0xFF43A047));
    }
    if (key.contains('宾果') || key.contains('BINGO')) {
      return (Icons.sports_esports, const Color(0xFFEF6C00));
    }
    if (key.contains('秒速') || key.contains('MS')) {
      return (Icons.speed, const Color(0xFFFB8C00));
    }
    if (key.contains('幸运赛车') || key.contains('XYSC')) {
      return (Icons.directions_car, const Color(0xFF8E24AA));
    }
    return (Icons.sports_motorsports, const Color(0xFFE53935));
  }

  void _open(Map<String, dynamic> g) {
    final type = _typeOf(g);
    if (type.isEmpty) return;
    final catalog = _games
        .map((e) => (type: _typeOf(e), name: _nameOf(e)))
        .where((e) => e.type.isNotEmpty)
        .toList();
    pushHostPage(
      context,
      HostOddsEditPage(
        roomId: widget.roomId,
        gameType: type,
        gameName: _nameOf(g),
        games: catalog,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return HostSubPageScaffold(
      title: '赔率设置',
      body: AppPullRefresh(
        onRefresh: () => _load(fromPull: true),
        child: _loading
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(height: 120),
                  const AppPageLoading(),
                ],
              )
            : _games.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      SizedBox(height: 120.h),
                      Center(
                        child: Text(
                          '暂无彩种',
                          style: TextStyle(fontSize: 14.sp, color: AppColors.textHint),
                        ),
                      ),
                    ],
                  )
                : ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 24.h),
                    itemCount: _games.length,
                    separatorBuilder: (_, _) => SizedBox(height: 10.h),
                    itemBuilder: (_, i) {
                      final g = _games[i];
                      final name = _nameOf(g);
                      final type = _typeOf(g);
                      final sub = _subtitleOf(g);
                      final (icon, color) = _iconOf(name, type);
                      return Material(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12.r),
                        child: InkWell(
                          onTap: () => _open(g),
                          borderRadius: BorderRadius.circular(12.r),
                          child: Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: 14.w,
                              vertical: 12.h,
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 44.w,
                                  height: 44.w,
                                  decoration: BoxDecoration(
                                    color: color.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(10.r),
                                  ),
                                  child: Icon(icon, color: color, size: 24.sp),
                                ),
                                SizedBox(width: 12.w),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        name,
                                        style: TextStyle(
                                          fontSize: 16.sp,
                                          fontWeight: FontWeight.w700,
                                          color: AppColors.textPrimary,
                                        ),
                                      ),
                                      SizedBox(height: 2.h),
                                      Text(
                                        sub,
                                        style: TextStyle(
                                          fontSize: 12.sp,
                                          color: AppColors.textHint,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Icon(
                                  Icons.chevron_right,
                                  size: 20.sp,
                                  color: AppColors.textHint,
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
      ),
    );
  }
}
