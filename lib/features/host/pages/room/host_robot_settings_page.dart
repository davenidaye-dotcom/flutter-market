import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../../config/theme/app_colors.dart';
import '../../../../data/repositories/providers.dart';
import '../../../../shared/widgets/emulator_safe_text_field.dart';
import '../../../../shared/widgets/page_app_bar.dart';
import '../../../../shared/widgets/user_avatar.dart';
import '../../../profile/widgets/avatar_picker_sheet.dart';
import '../../widgets/host_ui.dart';

/// 机器人设置 — GET/PUT /owner/room/atmosphere/{accountId}
class HostRobotSettingsPage extends ConsumerStatefulWidget {
  const HostRobotSettingsPage({
    super.key,
    required this.roomId,
    required this.accountId,
  });

  final String roomId;
  final String accountId;

  @override
  ConsumerState<HostRobotSettingsPage> createState() =>
      _HostRobotSettingsPageState();
}

class _HostRobotSettingsPageState extends ConsumerState<HostRobotSettingsPage> {
  final _nickCtrl = TextEditingController();
  final _minCtrl = TextEditingController(text: '10');
  final _maxCtrl = TextEditingController(text: '200');
  String _avatar = '';
  bool _enabled = true;
  bool _chatBet = false;
  List<_GameOpt> _games = [];
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  @override
  void dispose() {
    _nickCtrl.dispose();
    _minCtrl.dispose();
    _maxCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await ref
          .read(ownerRepositoryProvider)
          .getAtmosphere(widget.accountId);
      if (!mounted) return;
      final gamesRaw = data['games'];
      final selectedTypes = <String>{};
      final gt = data['gameTypes'];
      if (gt is List) {
        for (final e in gt) {
          final s = e.toString().trim();
          if (s.isNotEmpty) selectedTypes.add(s);
        }
      }
      final games = <_GameOpt>[];
      if (gamesRaw is List) {
        for (final raw in gamesRaw) {
          if (raw is! Map) continue;
          final m = Map<String, dynamic>.from(raw);
          final type = (m['gameType'] ?? '').toString();
          if (type.isEmpty) continue;
          final selected = m['selected'] == true || selectedTypes.contains(type);
          games.add(
            _GameOpt(
              type: type,
              name: (m['gameName'] ?? type).toString(),
              selected: selected,
            ),
          );
        }
      }
      setState(() {
        _nickCtrl.text = (data['nickname'] ?? '').toString();
        _avatar = (data['avatar'] ?? '').toString();
        _minCtrl.text = _numText(data['minBet'], fallback: '10');
        _maxCtrl.text = _numText(data['maxBet'], fallback: '200');
        _enabled = data['enabled'] != false;
        _chatBet = data['chatBet'] == true;
        _games = games;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      AppToast.error(e.toString());
    }
  }

  String _numText(dynamic v, {required String fallback}) {
    if (v is num) return v == v.roundToDouble() ? '${v.toInt()}' : '$v';
    final s = (v ?? '').toString().trim();
    return s.isEmpty ? fallback : s;
  }

  Future<void> _pickAvatar() async {
    final code = await showAvatarPickerSheet(context, currentCode: _avatar);
    if (code == null || !mounted) return;
    setState(() => _avatar = code);
  }

  Future<void> _save() async {
    if (_saving) return;
    final nick = _nickCtrl.text.trim();
    if (nick.isEmpty) {
      AppToast.info('请输入昵称');
      return;
    }
    final minBet = num.tryParse(_minCtrl.text.trim());
    final maxBet = num.tryParse(_maxCtrl.text.trim());
    if (minBet == null || maxBet == null || minBet < 1 || maxBet > 10000) {
      AppToast.info('下注额须在 1～10000');
      return;
    }
    if (minBet > maxBet) {
      AppToast.info('最小下注额不能大于最大下注额');
      return;
    }
    final types = _games.where((g) => g.selected).map((g) => g.type).toList();
    setState(() => _saving = true);
    try {
      await ref.read(ownerRepositoryProvider).updateAtmosphere(
        widget.accountId,
        {
          'nickname': nick,
          'avatar': _avatar,
          'minBet': minBet,
          'maxBet': maxBet,
          'enabled': _enabled,
          'chatBet': _chatBet,
          'gameTypes': types,
        },
      );
      if (!mounted) return;
      AppToast.success('已保存');
      Navigator.of(context).pop(true);
    } catch (e) {
      AppToast.error(e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final blue = AppColors.navBlue;
    return HostSubPageScaffold(
      title: '机器人设置',
      trailing: TextButton(
        onPressed: _saving ? null : _save,
        child: Text(
          '保存',
          style: TextStyle(
            fontSize: 15.sp,
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: _loading
          ? const AppPageLoading()
          : ListView(
              padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 24.h),
              children: [
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F4FF),
                    borderRadius: BorderRadius.circular(10.r),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.smart_toy_outlined, size: 18.sp, color: blue),
                      SizedBox(width: 8.w),
                      Expanded(
                        child: Text(
                          '修改机器人资料后点击右上角保存',
                          style: TextStyle(fontSize: 13.sp, color: blue),
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 12.h),
                HostWhiteCard(
                  child: Column(
                    children: [
                      Text('头像', style: TextStyle(fontSize: 14.sp)),
                      SizedBox(height: 10.h),
                      GestureDetector(
                        onTap: _pickAvatar,
                        child: UserAvatar(codeOrUrl: _avatar, radius: 36.r),
                      ),
                      SizedBox(height: 6.h),
                      Text(
                        '点击头像选择图片',
                        style: TextStyle(fontSize: 12.sp, color: AppColors.textHint),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 12.h),
                HostWhiteCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('基础配置',
                          style: TextStyle(
                              fontSize: 15.sp, fontWeight: FontWeight.w600)),
                      SizedBox(height: 12.h),
                      _LabeledField(label: '昵称', controller: _nickCtrl),
                      SizedBox(height: 10.h),
                      _LabeledField(
                        label: '最小下注额',
                        controller: _minCtrl,
                        keyboardType: TextInputType.number,
                      ),
                      SizedBox(height: 10.h),
                      _LabeledField(
                        label: '最大下注额',
                        controller: _maxCtrl,
                        keyboardType: TextInputType.number,
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 12.h),
                HostWhiteCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('下注游戏',
                          style: TextStyle(
                              fontSize: 15.sp, fontWeight: FontWeight.w600)),
                      SizedBox(height: 12.h),
                      if (_games.isEmpty)
                        Text('本房暂无可用彩种',
                            style: TextStyle(
                                fontSize: 13.sp, color: AppColors.textHint))
                      else
                        Wrap(
                          spacing: 8.w,
                          runSpacing: 8.h,
                          children: [
                            for (var i = 0; i < _games.length; i++)
                              _GameChip(
                                label: _games[i].name,
                                selected: _games[i].selected,
                                onTap: () => setState(() {
                                  _games[i] = _games[i]
                                      .copyWith(selected: !_games[i].selected);
                                }),
                              ),
                          ],
                        ),
                    ],
                  ),
                ),
                SizedBox(height: 12.h),
                HostWhiteCard(
                  child: _EnableTile(
                    icon: Icons.smart_toy_outlined,
                    title: '启用机器人',
                    statusText: _enabled ? '当前状态：已启用' : '当前状态：已停用',
                    value: _enabled,
                    onChanged: (v) => setState(() => _enabled = v),
                  ),
                ),
                SizedBox(height: 12.h),
                HostWhiteCard(
                  child: _EnableTile(
                    icon: Icons.chat_bubble_outline,
                    title: '开启注单',
                    statusText: _chatBet ? '当前状态：已开启' : '当前状态：已关闭',
                    value: _chatBet,
                    onChanged: (v) => setState(() => _chatBet = v),
                  ),
                ),
              ],
            ),
    );
  }
}

class _GameOpt {
  const _GameOpt({
    required this.type,
    required this.name,
    required this.selected,
  });
  final String type;
  final String name;
  final bool selected;
  _GameOpt copyWith({bool? selected}) =>
      _GameOpt(type: type, name: name, selected: selected ?? this.selected);
}

class _LabeledField extends StatelessWidget {
  const _LabeledField({
    required this.label,
    required this.controller,
    this.keyboardType,
  });
  final String label;
  final TextEditingController controller;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 13.sp, color: AppColors.textHint)),
        SizedBox(height: 6.h),
        EmulatorSafeTextField(
          controller: controller,
          keyboardType: keyboardType,
          decoration: InputDecoration(
            isDense: true,
            contentPadding:
                EdgeInsets.symmetric(horizontal: 12.w, vertical: 12.h),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10.r),
              borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10.r),
              borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
            ),
          ),
        ),
      ],
    );
  }
}

class _GameChip extends StatelessWidget {
  const _GameChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final blue = AppColors.navBlue;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20.r),
          border: Border.all(
            color: selected ? blue : const Color(0xFFDDDDDD),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (selected) ...[
              Icon(Icons.check, size: 14.sp, color: blue),
              SizedBox(width: 4.w),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 13.sp,
                color: selected ? blue : const Color(0xFF333333),
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EnableTile extends StatelessWidget {
  const _EnableTile({
    required this.icon,
    required this.title,
    required this.statusText,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String statusText;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(8.r),
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 4.h),
        child: Row(
          children: [
            Icon(icon, size: 22.sp, color: AppColors.navBlue),
            SizedBox(width: 10.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 15.sp,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF222222),
                    ),
                  ),
                  SizedBox(height: 4.h),
                  Text(
                    statusText,
                    style: TextStyle(
                      fontSize: 12.sp,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Checkbox(
              value: value,
              activeColor: AppColors.navBlue,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
              onChanged: (v) => onChanged(v == true),
            ),
          ],
        ),
      ),
    );
  }
}
