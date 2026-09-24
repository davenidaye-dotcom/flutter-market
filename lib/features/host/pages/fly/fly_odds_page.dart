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

/// 某个彩种的飞单赔率。统一 ±0.01，只改赔率。
class FlyOddsPage extends ConsumerStatefulWidget {
  const FlyOddsPage({
    super.key,
    required this.roomId,
    this.gameType = 'JS_SC',
    this.gameName,
  });

  final String roomId;
  final String gameType;
  final String? gameName;

  @override
  ConsumerState<FlyOddsPage> createState() => _FlyOddsPageState();
}

class _FlyOddsPageState extends ConsumerState<FlyOddsPage> {
  bool _dirty = false;
  bool _loading = true;
  bool _unbound = false;
  final _step = 0.01;
  List<_OddsRow> _rows = [];

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _unbound = false;
    });
    try {
      final repo = ref.read(ownerRepositoryProvider);
      final status = await repo.getFeipanStatus();
      if (status['bound'] != true) {
        if (!mounted) return;
        setState(() {
          _unbound = true;
          _loading = false;
        });
        return;
      }
      final data = await repo.getFeipanOdds(gameType: widget.gameType);
      final items = hostRowsOf(data['items']);
      final rows = items.map((m) {
        final odds = m['odds'] ?? 0;
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
        final next = (row.odds + delta).clamp(0.01, 9999.0);
        row.odds = double.parse(next.toStringAsFixed(3));
      }
      _dirty = true;
    });
  }

  Future<void> _save() async {
    try {
      await ref.read(ownerRepositoryProvider).updateFeipanOdds({
        'gameType': widget.gameType,
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
    final title = (widget.gameName ?? '').trim().isEmpty
        ? '飞单赔率'
        : widget.gameName!.trim();
    return HostSubPageScaffold(
      title: title,
      body: _loading
          ? const AppPageLoading()
          : _unbound
              ? _unboundBody()
              : Column(
                  children: [
                    Padding(
                      padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 0),
                      child: HostWhiteCard(
                        padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                '统一调节飞单赔率',
                                style: TextStyle(fontSize: 14.sp),
                              ),
                            ),
                            _stepBtn(Icons.add, () => _adjustAll(_step)),
                            Container(
                              width: 64.w,
                              alignment: Alignment.center,
                              padding: EdgeInsets.symmetric(vertical: 6.h),
                              decoration: BoxDecoration(
                                border: Border.all(color: const Color(0xFFE6EAF0)),
                                borderRadius: BorderRadius.circular(8.r),
                              ),
                              child: Text(
                                _step.toStringAsFixed(2),
                                style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600),
                              ),
                            ),
                            _stepBtn(Icons.remove, () => _adjustAll(-_step)),
                          ],
                        ),
                      ),
                    ),
                    if (_dirty)
                      Padding(
                        padding: EdgeInsets.only(top: 6.h, right: 20.w),
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: Text(
                            '未保存',
                            style: TextStyle(fontSize: 12.sp, color: AppColors.danger),
                          ),
                        ),
                      ),
                    Expanded(
                      child: _rows.isEmpty
                          ? Center(
                              child: Text('暂无数据', style: TextStyle(color: AppColors.textHint)),
                            )
                          : ListView(
                              padding: EdgeInsets.fromLTRB(16.w, 10.h, 16.w, 16.h),
                              children: [
                                HostWhiteCard(
                                  padding: EdgeInsets.zero,
                                  child: Column(
                                    children: [
                                      _head(),
                                      for (var i = 0; i < _rows.length; i++) ...[
                                        const Divider(height: 1, color: AppColors.divider),
                                        _line(_rows[i]),
                                      ],
                                    ],
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ],
                ),
      bottomBar: _loading || _unbound
          ? null
          : Padding(
              padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 16.h),
              child: HostPrimaryButton(label: '保存', onPressed: _save),
            ),
    );
  }

  Widget _unboundBody() {
    return Center(
      child: Text(
        '请先绑定代理会员',
        style: TextStyle(fontSize: 14.sp, color: AppColors.textHint),
      ),
    );
  }

  Widget _stepBtn(IconData icon, VoidCallback onTap) {
    return IconButton(onPressed: onTap, icon: Icon(icon, size: 20.sp));
  }

  Widget _head() {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 12.h),
      child: Row(
        children: [
          Expanded(
            child: Text('玩法', style: TextStyle(fontSize: 13.sp, color: AppColors.textSecondary)),
          ),
          SizedBox(
            width: 110.w,
            child: Text(
              '飞单赔率',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13.sp, color: AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _line(_OddsRow row) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 12.h),
      child: Row(
        children: [
          Expanded(
            child: Text(row.playName, style: TextStyle(fontSize: 14.sp)),
          ),
          Container(
            width: 110.w,
            alignment: Alignment.center,
            padding: EdgeInsets.symmetric(vertical: 8.h),
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFFE6EAF0)),
              borderRadius: BorderRadius.circular(20.r),
            ),
            child: Text(
              row.odds.toStringAsFixed(3),
              style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}
