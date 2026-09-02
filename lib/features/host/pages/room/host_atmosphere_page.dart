import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../../config/theme/app_colors.dart';
import '../../../../data/repositories/providers.dart';
import '../../../../shared/widgets/page_app_bar.dart';
import '../../data/host_mock.dart';
import '../../widgets/host_ui.dart';

/// Atmosphere uses room games settings as game switches (no dedicated atmosphere API in docs).
class HostAtmospherePage extends ConsumerStatefulWidget {
  const HostAtmospherePage({super.key, required this.roomId});
  final String roomId;

  @override
  ConsumerState<HostAtmospherePage> createState() => _HostAtmospherePageState();
}

class _HostAtmospherePageState extends ConsumerState<HostAtmospherePage> {
  bool _roomEnabled = true;
  List<(String, String, bool)> _gameSwitches = [];
  double _joinCount = 3;
  bool _dirty = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      var list = hostRowsOf(
        await ref.read(ownerRepositoryProvider).getGamesSettings(),
      );
      if (list.isEmpty) {
        list = await ref.read(ownerRepositoryProvider).getGames();
      }
      if (!mounted) return;
      setState(() {
        _gameSwitches = list
            .map((g) => (
                  (g['gameType'] ?? g['type'] ?? '').toString(),
                  (g['gameName'] ?? g['typeName'] ?? g['gameType'] ?? '').toString(),
                  g['enabled'] != false,
                ))
            .toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      AppToast.error(e.toString());
    }
  }

  Future<void> _save() async {
    try {
      await ref.read(ownerRepositoryProvider).updateGamesSettings({
        'atmosphereEnabled': _roomEnabled,
        'atmosphereJoinCount': _joinCount.round(),
        'games': _gameSwitches
            .map((g) => {
                  'gameType': g.$1.isEmpty ? g.$2 : g.$1,
                  'enabled': _roomEnabled && g.$3,
                })
            .toList(),
      });
      setState(() => _dirty = false);
      AppToast.success('\u6c14\u6c1b\u53f7\u8bbe\u7f6e\u5df2\u4fdd\u5b58');
    } catch (e) {
      AppToast.error(e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return HostSubPageScaffold(
      title: '\u6c14\u6c1b\u53f7\u8bbe\u7f6e',
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 24.h),
              children: [
                HostWhiteCard(
                  child: Row(
                    children: [
                      Text('\u623f\u95f4\u603b\u5f00\u5173', style: TextStyle(fontSize: 15.sp)),
                      const Spacer(),
                      Switch(
                        value: _roomEnabled,
                        activeThumbColor: AppColors.navBlue,
                        onChanged: (v) => setState(() {
                          _roomEnabled = v;
                          _dirty = true;
                        }),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 10.h),
                Text('\u5f69\u79cd\u5f00\u5173', style: TextStyle(fontSize: 13.sp, color: AppColors.textSecondary)),
                SizedBox(height: 6.h),
                ...List.generate(_gameSwitches.length, (i) {
                  final (code, name, enabled) = _gameSwitches[i];
                  return Padding(
                    padding: EdgeInsets.only(bottom: 8.h),
                    child: HostWhiteCard(
                      child: Row(
                        children: [
                          Expanded(child: Text(name.isEmpty ? code : name, style: TextStyle(fontSize: 14.sp))),
                          Switch(
                            value: enabled,
                            activeThumbColor: AppColors.navBlue,
                            onChanged: _roomEnabled
                                ? (v) => setState(() {
                                      _gameSwitches[i] = (code, name, v);
                                      _dirty = true;
                                    })
                                : null,
                          ),
                        ],
                      ),
                    ),
                  );
                }),
                SizedBox(height: 10.h),
                HostWhiteCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text('\u6bcf\u671f\u53c2\u4e0e\u6570\u91cf', style: TextStyle(fontSize: 14.sp)),
                          const Spacer(),
                          Text(
                            '${_joinCount.round()}',
                            style: TextStyle(
                              fontSize: 16.sp,
                              fontWeight: FontWeight.w600,
                              color: AppColors.navBlue,
                            ),
                          ),
                        ],
                      ),
                      Slider(
                        value: _joinCount,
                        min: 0,
                        max: 6,
                        divisions: 6,
                        activeColor: AppColors.navBlue,
                        onChanged: _roomEnabled
                            ? (v) => setState(() {
                                  _joinCount = v;
                                  _dirty = true;
                                })
                            : null,
                      ),
                    ],
                  ),
                ),
              ],
            ),
      bottomBar: Padding(
        padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 16.h),
        child: HostPrimaryButton(
          label: '\u4fdd\u5b58',
          enabled: _dirty,
          onPressed: _save,
        ),
      ),
    );
  }
}
