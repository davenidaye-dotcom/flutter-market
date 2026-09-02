import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../../config/theme/app_colors.dart';
import '../../../../data/repositories/providers.dart';
import '../../../../shared/widgets/emulator_safe_text_field.dart';
import '../../../../shared/widgets/page_app_bar.dart';
import '../../data/host_mock.dart';
import '../../widgets/host_ui.dart';

/// Member detail — load from members API; status/rebate via PUT
class HostMemberDetailPage extends ConsumerStatefulWidget {
  const HostMemberDetailPage({super.key, required this.roomId, required this.memberId});
  final String roomId;
  final String memberId;

  @override
  ConsumerState<HostMemberDetailPage> createState() => _HostMemberDetailPageState();
}

class _HostMemberDetailPageState extends ConsumerState<HostMemberDetailPage> {
  HostMember? _member;
  final _remark = TextEditingController();
  final _rebateCtrl = TextEditingController();
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  @override
  void dispose() {
    _remark.dispose();
    _rebateCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await ref.read(ownerRepositoryProvider).getMembers(
            keyword: widget.memberId,
            pageSize: 50,
          );
      final rows = hostRowsOf(data);
      HostMember? found;
      for (final r in rows) {
        final m = hostMemberFromMap(r);
        if (m.id == widget.memberId || m.userId == widget.memberId) {
          found = m;
          _rebateCtrl.text = '${r['rebate'] ?? r['rebateRatio'] ?? ''}';
          break;
        }
      }
      found ??= rows.isNotEmpty
          ? hostMemberFromMap(rows.first)
          : HostMember(widget.memberId, '\u672a\u77e5', '-', widget.memberId, '-', 0);
      if (!mounted) return;
      setState(() {
        _member = found;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _member = HostMember(widget.memberId, '\u672a\u77e5', '-', widget.memberId, '-', 0);
        _loading = false;
      });
      AppToast.error(e.toString());
    }
  }

  Future<void> _setStatus(String status, String tip) async {
    final ok = await hostConfirm(context, title: tip, message: tip, danger: true);
    if (!ok || !mounted) return;
    try {
      await ref.read(ownerRepositoryProvider).updateMemberStatus(widget.memberId, status);
      AppToast.success('\u5df2\u63d0\u4ea4');
      await _load();
    } catch (e) {
      AppToast.error(e.toString());
    }
  }

  Future<void> _saveRebate() async {
    final v = num.tryParse(_rebateCtrl.text.trim());
    if (v == null) {
      AppToast.info('\u8bf7\u8f93\u5165\u53cd\u6c34\u6bd4\u4f8b');
      return;
    }
    try {
      await ref.read(ownerRepositoryProvider).updateMemberRebate(widget.memberId, v);
      AppToast.success('\u5df2\u4fdd\u5b58');
    } catch (e) {
      AppToast.error(e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final member = _member;
    return HostSubPageScaffold(
      title: '\u6210\u5458\u8be6\u60c5',
      body: _loading || member == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 24.h),
              children: [
                HostWhiteCard(
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 28.r,
                        backgroundColor: const Color(0xFFBDE0FE),
                        child: Text(
                          member.nickname.isNotEmpty ? member.nickname.characters.first : '?',
                          style: TextStyle(fontSize: 18.sp, color: AppColors.navBlue),
                        ),
                      ),
                      SizedBox(width: 12.w),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(member.nickname, style: TextStyle(fontSize: 17.sp, fontWeight: FontWeight.w600)),
                            Text(
                              '${member.username} \u00b7 ${member.userId}',
                              style: TextStyle(fontSize: 12.sp, color: AppColors.textSecondary),
                            ),
                            Text(member.roleLabel, style: TextStyle(fontSize: 12.sp, color: AppColors.navBlue)),
                          ],
                        ),
                      ),
                      Text('${member.points}', style: TextStyle(fontSize: 20.sp, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
                SizedBox(height: 10.h),
                HostWhiteCard(
                  child: EmulatorSafeTextField(
                    controller: _remark,
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      hintText: '\u623f\u95f4\u5907\u6ce8\uff08\u4ec5\u672c\u623f\u95f4\u53ef\u89c1\uff09',
                      hintStyle: TextStyle(fontSize: 13.sp, color: AppColors.textHint),
                    ),
                  ),
                ),
                SizedBox(height: 10.h),
                HostWhiteCard(
                  child: Row(
                    children: [
                      Text('\u7279\u6b8a\u53cd\u6c34%', style: TextStyle(fontSize: 14.sp)),
                      SizedBox(width: 12.w),
                      Expanded(
                        child: EmulatorSafeTextField(
                          controller: _rebateCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
                        ),
                      ),
                      TextButton(onPressed: _saveRebate, child: const Text('\u4fdd\u5b58')),
                    ],
                  ),
                ),
                SizedBox(height: 10.h),
                _action('\u7981\u7528', () => _setStatus('DISABLED', '\u7981\u7528\u6210\u5458'), danger: true),
                _action('\u51bb\u7ed3', () => _setStatus('FROZEN', '\u51bb\u7ed3\u6210\u5458'), danger: true),
                _action('\u6062\u590d\u6b63\u5e38', () => _setStatus('NORMAL', '\u6062\u590d\u6b63\u5e38')),
                _action('\u7981\u6b62\u8fdb\u623f', () => _setStatus('BAN_ENTER', '\u52a0\u5165\u9ed1\u540d\u5355'), danger: true),
              ],
            ),
    );
  }

  Widget _action(String label, VoidCallback onTap, {bool danger = false}) {
    return Padding(
      padding: EdgeInsets.only(bottom: 8.h),
      child: HostWhiteCard(
        onTap: onTap,
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 15.sp,
                  color: danger ? AppColors.danger : AppColors.textPrimary,
                ),
              ),
            ),
            Icon(Icons.chevron_right, color: AppColors.textHint, size: 18.sp),
          ],
        ),
      ),
    );
  }
}
