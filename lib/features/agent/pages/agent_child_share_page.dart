import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../config/theme/app_colors.dart';
import '../../../data/repositories/providers.dart';
import '../../../shared/widgets/app_page_loading.dart';
import '../../../shared/widgets/page_app_bar.dart';
import '../widgets/agent_ui.dart';

/// 占成：直属上级占这个账号多少。占成上限：分给它、供其再往下分配的最大比例。
/// 两者之和不超过该上级的可分配上限。代理会员只设占成。
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
  List<Map<String, dynamic>> _rows = [];
  bool _member = false;
  /// gameType → 占成（上级占这个账号）
  final Map<String, int> _own = {};
  /// gameType → 占成上限（分给这个账号再往下分）
  final Map<String, int> _child = {};

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

  String _gameName(String gt) => _names[gt] ?? gt;

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final rows = await ref.read(agentRepositoryProvider).getChildShare(widget.accountId);
      if (!mounted) return;
      final live = rows.where((r) => agentLiveGameTypes.contains(_gt(r))).toList();
      final use = live.isEmpty ? rows : live;
      final member = use.isNotEmpty && _isMemberRow(use.first);
      _own.clear();
      _child.clear();
      for (final r in use) {
        final gt = _gt(r);
        final cap = _num(r['parentCap']);
        var occupy = _num(r['selfShare']);
        var child = member ? 0 : _num(r['childMaxShare']);
        if (occupy < 0) occupy = 0;
        if (child < 0) child = 0;
        if (occupy > cap) occupy = cap;
        if (occupy + child > cap) child = cap - occupy;
        _own[gt] = occupy;
        _child[gt] = child;
      }
      setState(() {
        _rows = use;
        _member = member;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      AppToast.error(e.toString());
    }
  }

  bool _isMemberRow(Map<String, dynamic> r) {
    final kind = '${r['scene'] ?? r['relKind'] ?? ''}'.toUpperCase();
    return kind == 'MEMBER';
  }

  int _capOf(Map<String, dynamic> r) => _num(r['parentCap']);

  int _ownOf(Map<String, dynamic> r) => _own[_gt(r)] ?? 0;

  int _childOf(Map<String, dynamic> r) => _member ? 0 : (_child[_gt(r)] ?? 0);

  void _setOwn(Map<String, dynamic> r, int value) {
    final gt = _gt(r);
    final cap = _capOf(r);
    var occupy = value.clamp(0, cap);
    var child = _member ? 0 : _childOf(r);
    if (occupy + child > cap) child = cap - occupy;
    setState(() {
      _own[gt] = occupy;
      _child[gt] = child;
    });
  }

  void _setChild(Map<String, dynamic> r, int value) {
    final gt = _gt(r);
    final cap = _capOf(r);
    final room = (cap - _ownOf(r)).clamp(0, cap);
    setState(() => _child[gt] = value.clamp(0, room));
  }

  List<int> _options(int max) {
    if (max <= 0) return const [0];
    final out = <int>[];
    for (var i = 0; i <= max; i += 5) {
      out.add(i);
    }
    if (out.last != max) out.add(max);
    return out;
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final payload = <Map<String, dynamic>>[];
      for (final r in _rows) {
        final gt = _gt(r);
        final occupy = _own[gt] ?? 0;
        final childMax = _member ? 0 : (_child[gt] ?? 0);
        payload.add({
          'gameType': gt,
          'takeShare': occupy + childMax,
          'selfShare': occupy,
          'childMaxShare': childMax,
        });
      }
      await ref.read(agentRepositoryProvider).saveChildShare(widget.accountId, payload);
      AppToast.success('占成已保存');
      await _load();
    } catch (e) {
      AppToast.error(e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<int?> _pickValue(String title, int current, int max) async {
    final opts = _options(max);
    return showModalBottomSheet<int>(
      context: context,
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12.r)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 8.h),
              child: Text(title, style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w700)),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: opts.length,
                itemBuilder: (_, i) {
                  final v = opts[i];
                  final selected = v == current;
                  return ListTile(
                    title: Text('$v', textAlign: TextAlign.center),
                    selected: selected,
                    trailing: selected ? Icon(Icons.check, color: AppColors.navBlue, size: 18.sp) : null,
                    onTap: () => Navigator.pop(ctx, v),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AgentPageFrame(
      title: '',
      onRefresh: _loading ? null : _load,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AgentBackTitle(title: '账户管理 / ${widget.title} 占成设置'),
          Padding(
            padding: EdgeInsets.fromLTRB(12.w, 4.h, 12.w, 8.h),
            child: Row(
              children: [
                OutlinedButton(
                  onPressed: _loading ? null : _load,
                  style: OutlinedButton.styleFrom(
                    backgroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
                    side: const BorderSide(color: AgentChrome.cardBorder),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6.r)),
                  ),
                  child: Text('刷新', style: TextStyle(fontSize: 13.sp, color: AppColors.textPrimary)),
                ),
                SizedBox(width: 10.w),
                Expanded(
                  child: Text(
                    '开盘之后设置占成，将于下期生效',
                    style: TextStyle(fontSize: 12.sp, color: Colors.red),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const AppPageLoading()
                : ListView(
                    padding: EdgeInsets.fromLTRB(12.w, 0, 12.w, 16.h),
                    children: [
                      Text(
                        '占成设置',
                        style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w700, color: AgentChrome.ink),
                      ),
                      SizedBox(height: 4.h),
                      Text(
                        _member
                            ? '占成是直属上级占这个会员多少，不能超过该上级的可分配上限。'
                            : '占成是直属上级占这个账号多少；占成上限是分给它再往下分配的最大比例。两者之和不能超过该上级的可分配上限。',
                        style: TextStyle(fontSize: 12.sp, color: AppColors.textSecondary, height: 1.4),
                      ),
                      SizedBox(height: 8.h),
                      _table(),
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

  Widget _table() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AgentChrome.cardBorder),
        borderRadius: BorderRadius.circular(4.r),
      ),
      child: Column(
        children: [
          _headerRow(),
          for (var i = 0; i < _rows.length; i++) ...[
            Divider(height: 1, thickness: 1, color: AgentChrome.cardBorder),
            _dataRow(_rows[i]),
          ],
        ],
      ),
    );
  }

  Widget _headerRow() {
    return Container(
      color: const Color(0xFFF5F7FA),
      padding: EdgeInsets.symmetric(vertical: 10.h, horizontal: 6.w),
      child: Row(
        children: [
          _cell('游戏', flex: 3, header: true, align: TextAlign.left),
          _cell('可分配上限', flex: 2, header: true),
          _cell('占成', flex: 2, header: true),
          if (!_member) _cell('占成上限', flex: 2, header: true),
        ],
      ),
    );
  }

  Widget _dataRow(Map<String, dynamic> r) {
    final gt = _gt(r);
    final cap = _capOf(r);
    final own = _ownOf(r);
    final child = _childOf(r);
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 8.h, horizontal: 6.w),
      child: Row(
        children: [
          _cell(_gameName(gt), flex: 3, align: TextAlign.left),
          _cell('$cap', flex: 2),
          Expanded(
            flex: 2,
            child: _dropdownBox(
              '$own',
              onTap: () async {
                final v = await _pickValue('占成', own, cap);
                if (v != null) _setOwn(r, v);
              },
            ),
          ),
          if (!_member)
            Expanded(
              flex: 2,
              child: Padding(
                padding: EdgeInsets.only(left: 4.w),
                child: _dropdownBox(
                  '$child',
                  onTap: () async {
                    final room = (cap - own).clamp(0, cap);
                    final v = await _pickValue('占成上限', child, room);
                    if (v != null) _setChild(r, v);
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _cell(String text, {int flex = 1, bool header = false, TextAlign align = TextAlign.center}) {
    return Expanded(
      flex: flex,
      child: Text(
        text,
        textAlign: align,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: header ? 12.sp : 13.sp,
          fontWeight: header ? FontWeight.w600 : FontWeight.w500,
          color: AgentChrome.ink,
        ),
      ),
    );
  }

  Widget _dropdownBox(String text, {required VoidCallback onTap}) {
    return Material(
      color: const Color(0xFFF0F2F5),
      borderRadius: BorderRadius.circular(4.r),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4.r),
        child: Container(
          height: 32.h,
          padding: EdgeInsets.symmetric(horizontal: 6.w),
          alignment: Alignment.center,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13.sp, color: AgentChrome.ink),
                ),
              ),
              Icon(Icons.arrow_drop_down, size: 18.sp, color: AppColors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}
