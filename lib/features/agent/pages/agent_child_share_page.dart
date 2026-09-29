import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../config/theme/app_colors.dart';
import '../../../data/repositories/providers.dart';
import '../../../shared/widgets/app_page_loading.dart';
import '../../../shared/widgets/page_app_bar.dart';
import '../widgets/agent_ui.dart';

/// 下级占成：彩种 Tab + 拿/占步进，下级上限只读。
class AgentChildSharePage extends ConsumerStatefulWidget {
  const AgentChildSharePage({
    super.key,
    required this.accountId,
    required this.title,
  });

  final int accountId;
  final String title;

  @override
  ConsumerState<AgentChildSharePage> createState() => _AgentChildSharePageState();
}

class _AgentChildSharePageState extends ConsumerState<AgentChildSharePage> {
  bool _loading = true;
  bool _saving = false;
  int _gameIndex = 0;
  List<Map<String, dynamic>> _rows = [];
  final Map<String, int> _take = {};
  final Map<String, int> _occupy = {};

  static const _names = {'JS_SC': '极速赛车', 'AZXY10': '澳洲幸运10'};

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  String _gt(Map<String, dynamic> r) => '${r['gameType'] ?? ''}';

  int _num(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.round();
    return int.tryParse('$v') ?? 0;
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final rows = await ref.read(agentRepositoryProvider).getChildShare(widget.accountId);
      if (!mounted) return;
      if (rows.isEmpty || rows.first['memberNoShare'] == true) {
        AppToast.success('代理会员不占成');
        Navigator.of(context).pop();
        return;
      }
      _take.clear();
      _occupy.clear();
      for (final r in rows) {
        final gt = _gt(r);
        _take[gt] = _num(r['takeShare']);
        _occupy[gt] = _num(r['selfShare']);
      }
      setState(() {
        _rows = rows;
        _gameIndex = 0;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      AppToast.error(e.toString());
    }
  }

  Map<String, dynamic>? get _current =>
      _rows.isEmpty ? null : _rows[_gameIndex.clamp(0, _rows.length - 1)];

  void _bump(String field, int delta) {
    final row = _current;
    if (row == null) return;
    final gt = _gt(row);
    final cap = _num(row['parentCap']);
    var take = _take[gt] ?? 0;
    var occupy = _occupy[gt] ?? 0;
    if (field == 'take') {
      take = (take + delta).clamp(0, cap);
      if (occupy > take) occupy = take;
    } else {
      occupy = (occupy + delta).clamp(0, take);
    }
    setState(() {
      _take[gt] = take;
      _occupy[gt] = occupy;
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final payload = <Map<String, dynamic>>[];
      for (final r in _rows) {
        final gt = _gt(r);
        final take = _take[gt] ?? 0;
        final occupy = _occupy[gt] ?? 0;
        payload.add({
          'gameType': gt,
          'takeShare': take,
          'selfShare': occupy,
          'childMaxShare': (take - occupy).clamp(0, 100),
        });
      }
      await ref.read(agentRepositoryProvider).saveChildShare(widget.accountId, payload);
      AppToast.success('占成已保存');
    } catch (e) {
      AppToast.error(e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final names = [for (final r in _rows) _names[_gt(r)] ?? _gt(r)];
    final row = _current;
    final gt = row == null ? '' : _gt(row);
    final cap = row == null ? 0 : _num(row['parentCap']);
    final take = _take[gt] ?? 0;
    final occupy = _occupy[gt] ?? 0;
    final childCap = (take - occupy).clamp(0, 100);

    return AgentPageFrame(
      title: '',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AgentBackTitle(title: '占成 · ${widget.title}'),
          if (names.isNotEmpty)
            AgentGameTabs(
              games: names,
              current: _gameIndex,
              onChanged: (i) => setState(() => _gameIndex = i),
            ),
          Expanded(
            child: _loading
                ? const AppPageLoading()
                : ListView(
                    padding: EdgeInsets.only(top: 8.h, bottom: 16.h),
                    children: [
                      AgentSurface(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '获配 $cap%',
                              style: TextStyle(fontSize: 13.sp, color: AppColors.textSecondary),
                            ),
                            SizedBox(height: 14.h),
                            _stepRow('拿', take, () => _bump('take', -5), () => _bump('take', 5)),
                            SizedBox(height: 12.h),
                            _stepRow('占', occupy, () => _bump('occupy', -5), () => _bump('occupy', 5)),
                            SizedBox(height: 14.h),
                            Row(
                              children: [
                                Text('下级上限', style: TextStyle(fontSize: 14.sp, color: AppColors.textSecondary)),
                                const Spacer(),
                                Text(
                                  '$childCap%',
                                  style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w700, color: AgentChrome.ink),
                                ),
                              ],
                            ),
                            SizedBox(height: 4.h),
                            Text(
                              '下级上限 = 拿 − 占',
                              style: TextStyle(fontSize: 12.sp, color: AppColors.textHint),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(12.w, 8.h, 12.w, 16.h),
            child: AgentTealButton(
              label: _saving ? '...' : '保存',
              block: true,
              onTap: _loading || _saving ? () {} : _save,
            ),
          ),
        ],
      ),
    );
  }

  Widget _stepRow(String label, int value, VoidCallback minus, VoidCallback plus) {
    return Row(
      children: [
        SizedBox(
          width: 40.w,
          child: Text(label, style: TextStyle(fontSize: 15.sp, color: AgentChrome.ink)),
        ),
        const Spacer(),
        _roundBtn(Icons.remove, minus),
        SizedBox(
          width: 72.w,
          child: Text(
            '$value%',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.w700, color: AgentChrome.ink),
          ),
        ),
        _roundBtn(Icons.add, plus),
      ],
    );
  }

  Widget _roundBtn(IconData icon, VoidCallback onTap) {
    return Material(
      color: AgentChrome.accent.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(8.r),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8.r),
        child: SizedBox(
          width: 36.w,
          height: 36.w,
          child: Icon(icon, size: 18.sp, color: AgentChrome.accent),
        ),
      ),
    );
  }
}
