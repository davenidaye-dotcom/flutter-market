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
    required this.playType,
    required this.agentOdds,
    required this.hostOdds,
    required this.minOdds,
  });

  final String playCode;
  final String playType;
  final double agentOdds;
  double hostOdds;
  final double minOdds;
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
  String _gameType = 'JS_SC';

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
      final items = hostRowsOf(data.containsKey('items') ? data['items'] : data);
      final rows = items.map((m) {
        final agent = (m['agentOdds'] ?? m['odds'] ?? 0);
        final host = (m['hostOdds'] ?? m['odds'] ?? agent);
        final min = (m['minOdds'] ?? 0);
        return _OddsRow(
          playCode: (m['playCode'] ?? '').toString(),
          playType: (m['playName'] ?? m['playCode'] ?? '').toString(),
          agentOdds: agent is num ? agent.toDouble() : double.tryParse('$agent') ?? 0,
          hostOdds: host is num ? host.toDouble() : double.tryParse('$host') ?? 0,
          minOdds: min is num ? min.toDouble() : double.tryParse('$min') ?? 0,
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
        final next = (row.hostOdds + delta).clamp(row.minOdds, row.agentOdds);
        row.hostOdds = double.parse(next.toStringAsFixed(2));
      }
      _dirty = true;
    });
  }

  Future<void> _save() async {
    try {
      await ref.read(ownerRepositoryProvider).updateFeipanOdds({
        'gameType': _gameType,
        'items': _rows
            .map((r) => {
                  'playCode': r.playCode,
                  'odds': r.hostOdds,
                })
            .toList(),
      });
      setState(() => _dirty = false);
      AppToast.success('\u8d54\u7387\u5df2\u4fdd\u5b58');
    } catch (e) {
      AppToast.error(e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return HostSubPageScaffold(
      title: '\u98de\u5355\u8d54\u7387\u8bbe\u7f6e',
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
                  child: Row(
                    children: [
                      Text(_dirty ? '\u672a\u4fdd\u5b58' : '', style: TextStyle(color: AppColors.danger, fontSize: 12.sp)),
                      const Spacer(),
                      IconButton(onPressed: () => _adjustAll(_step), icon: const Icon(Icons.add)),
                      IconButton(onPressed: () => _adjustAll(-_step), icon: const Icon(Icons.remove)),
                    ],
                  ),
                ),
                Expanded(
                  child: _rows.isEmpty
                      ? Center(child: Text('\u6682\u65e0\u6570\u636e', style: TextStyle(color: AppColors.textHint)))
                      : ListView.separated(
                          padding: EdgeInsets.all(16.w),
                          itemCount: _rows.length,
                          separatorBuilder: (_, _) => SizedBox(height: 8.h),
                          itemBuilder: (_, i) {
                            final r = _rows[i];
                            return HostWhiteCard(
                              child: Row(
                                children: [
                                  Expanded(child: Text(r.playType)),
                                  Text('${r.hostOdds}', style: TextStyle(fontWeight: FontWeight.w700)),
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
        child: HostPrimaryButton(label: '\u4fdd\u5b58', onPressed: _save),
      ),
    );
  }
}
