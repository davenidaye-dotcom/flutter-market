import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../../config/theme/app_colors.dart';
import '../../../../data/repositories/providers.dart';
import '../../../../shared/widgets/page_app_bar.dart';
import '../../data/host_mock.dart';
import '../../widgets/host_ui.dart';

class _OddsRow {
  _OddsRow({
    required this.playCode,
    required this.playName,
    required this.odds,
  });

  final String playCode;
  final String playName;
  double odds;
}

/// Feipan odds — GET/PUT /owner/feipan/odds
class FlyOddsPage extends ConsumerStatefulWidget {
  const FlyOddsPage({super.key, required this.roomId});
  final String roomId;

  @override
  ConsumerState<FlyOddsPage> createState() => _FlyOddsPageState();
}

class _FlyOddsPageState extends ConsumerState<FlyOddsPage> {
  bool _dirty = false;
  bool _loading = true;
  final _step = 0.01;
  List<_OddsRow> _rows = [];
  final String _gameType = 'JS_SC';

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await ref
          .read(ownerRepositoryProvider)
          .getFeipanOdds(gameType: _gameType);
      // 文档：data.items[] — playCode / playName / odds / periodLimit / minBet
      final items = hostRowsOf(data['items']);
      final rows = items.map((m) {
        final odds = (m['odds'] ?? 0);
        return _OddsRow(
          playCode: (m['playCode'] ?? '').toString(),
          playName: (m['playName'] ?? m['playCode'] ?? '').toString(),
          odds: odds is num ? odds.toDouble() : double.tryParse('$odds') ?? 0,
        );
      }).toList();
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _dirty = false;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      AppToast.error(e.toString());
    }
  }

  void _adjustAll(double delta) {
    setState(() {
      for (final row in _rows) {
        // minBet 是单注最低金额，不是赔率下限
        final next = (row.odds + delta).clamp(0.01, 9999.0);
        row.odds = double.parse(next.toStringAsFixed(3));
      }
      _dirty = true;
    });
  }

  Future<void> _save() async {
    try {
      // 仅覆盖 odds；minBet/periodLimit 不传则后端保留原值
      await ref.read(ownerRepositoryProvider).updateFeipanOdds({
        'gameType': _gameType,
        'items': _rows
            .map((r) => {
                  'playCode': r.playCode,
                  'odds': r.odds,
                })
            .toList(),
      });
      if (!mounted) return;
      setState(() => _dirty = false);
      AppToast.success('赔率已保存');
    } catch (e) {
      AppToast.error(e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return HostSubPageScaffold(
      title: '飞单赔率设置',
      body: _loading
          ? const AppPageLoading()
          : Column(
              children: [
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
                  child: Row(
                    children: [
                      Text(_dirty ? '未保存' : '', style: TextStyle(color: AppColors.danger, fontSize: 12.sp)),
                      const Spacer(),
                      IconButton(onPressed: () => _adjustAll(_step), icon: const Icon(Icons.add)),
                      IconButton(onPressed: () => _adjustAll(-_step), icon: const Icon(Icons.remove)),
                    ],
                  ),
                ),
                Expanded(
                  child: _rows.isEmpty
                      ? Center(child: Text('暂无数据', style: TextStyle(color: AppColors.textHint)))
                      : ListView.separated(
                          padding: EdgeInsets.all(16.w),
                          itemCount: _rows.length,
                          separatorBuilder: (_, _) => SizedBox(height: 8.h),
                          itemBuilder: (_, i) {
                            final r = _rows[i];
                            return HostWhiteCard(
                              child: Row(
                                children: [
                                  Expanded(child: Text(r.playName)),
                                  Text('${r.odds}', style: TextStyle(fontWeight: FontWeight.w700)),
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
      bottomBar: Padding(
        padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 16.h),
        child: HostPrimaryButton(label: '保存', onPressed: _save),
      ),
    );
  }
}
