import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../../config/theme/app_colors.dart';
import '../../../../data/repositories/providers.dart';
import '../../../../shared/widgets/emulator_safe_text_field.dart';
import '../../../../shared/widgets/page_app_bar.dart';
import '../../widgets/host_ui.dart';

/// 新增机器人 — POST /owner/room/atmosphere
/// 文档：App房主批量创建气氛号接口_20260922
/// 不传 nickname / avatar / enabled / chatBet（服务端固定生成与关闭态）。
class HostRobotCreatePage extends ConsumerStatefulWidget {
  const HostRobotCreatePage({super.key, required this.roomId});

  final String roomId;

  @override
  ConsumerState<HostRobotCreatePage> createState() =>
      _HostRobotCreatePageState();
}

class _HostRobotCreatePageState extends ConsumerState<HostRobotCreatePage> {
  /// 图2「个数」→ body.count，缺省 1
  final _countCtrl = TextEditingController(text: '1');
  final _minCtrl = TextEditingController(text: '10');
  final _maxCtrl = TextEditingController(text: '200');
  List<_GameOpt> _games = [];
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(_loadGames);
  }

  @override
  void dispose() {
    _countCtrl.dispose();
    _minCtrl.dispose();
    _maxCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadGames() async {
    setState(() => _loading = true);
    try {
      final rows = await ref.read(ownerRepositoryProvider).getGamesSettings();
      if (!mounted) return;
      final games = <_GameOpt>[];
      for (final m in rows) {
        final type = (m['gameType'] ?? m['type'] ?? '').toString().trim();
        if (type.isEmpty) continue;
        final enabled = m['enabled'] != false && m['status'] != 'OFF';
        if (!enabled) continue;
        final name =
            (m['gameName'] ?? m['name'] ?? m['typeName'] ?? type).toString();
        // 默认不勾选：不传 / [] = 不绑定彩种
        games.add(_GameOpt(type: type, name: name, selected: false));
      }
      setState(() {
        _games = games;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      AppToast.error(e.toString());
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    final count = int.tryParse(_countCtrl.text.trim()) ?? 0;
    if (count < 1) {
      AppToast.info('个数至少为 1');
      return;
    }

    final minRaw = _minCtrl.text.trim();
    final maxRaw = _maxCtrl.text.trim();
    num? minBet;
    num? maxBet;
    if (minRaw.isNotEmpty) {
      minBet = num.tryParse(minRaw);
      if (minBet == null) {
        AppToast.info('最小下注额格式不正确');
        return;
      }
    }
    if (maxRaw.isNotEmpty) {
      maxBet = num.tryParse(maxRaw);
      if (maxBet == null) {
        AppToast.info('最大下注额格式不正确');
        return;
      }
    }
    // 空或 ≤0 由服务端回落 10/200；若都填了则校验区间
    if (minBet != null && maxBet != null && minBet > 0 && maxBet > 0) {
      if (minBet > maxBet) {
        AppToast.info('最小下注额不能大于最大下注额');
        return;
      }
    }

    final types = _games.where((g) => g.selected).map((g) => g.type).toList();

    setState(() => _saving = true);
    try {
      final body = <String, dynamic>{
        'count': count,
      };
      if (minBet != null && minBet > 0) body['minBet'] = minBet;
      if (maxBet != null && maxBet > 0) body['maxBet'] = maxBet;
      if (types.isNotEmpty) body['gameTypes'] = types;

      final res = await ref.read(ownerRepositoryProvider).createAtmosphere(body);
      if (!mounted) return;
      final created = int.tryParse('${res['count'] ?? count}') ?? count;
      AppToast.success(created > 1 ? '已创建 $created 个机器人' : '已创建');
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
      title: '新增机器人',
      trailing: TextButton(
        onPressed: _saving || _loading ? null : _save,
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
                  padding:
                      EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
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
                          '填写后点右上角保存。昵称与头像由系统生成，新建默认关闭启用与注单',
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
                      CircleAvatar(
                        radius: 36.r,
                        backgroundColor: const Color(0xFFE8E8E8),
                        child: Icon(
                          Icons.add_photo_alternate_outlined,
                          size: 28.sp,
                          color: const Color(0xFF9E9E9E),
                        ),
                      ),
                      SizedBox(height: 6.h),
                      Text(
                        '头像由系统自动生成（av01～av42）',
                        style: TextStyle(
                          fontSize: 12.sp,
                          color: AppColors.textHint,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 12.h),
                HostWhiteCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '基础配置',
                        style: TextStyle(
                          fontSize: 15.sp,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      SizedBox(height: 12.h),
                      _LabeledField(
                        label: '个数',
                        controller: _countCtrl,
                        keyboardType: TextInputType.number,
                        hint: '一次创建几个（本房最多 20 个）',
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                      ),
                      SizedBox(height: 10.h),
                      _LabeledField(
                        label: '最小下注额',
                        controller: _minCtrl,
                        keyboardType: TextInputType.number,
                        hint: '空或 ≤0 默认 10',
                      ),
                      SizedBox(height: 10.h),
                      _LabeledField(
                        label: '最大下注额',
                        controller: _maxCtrl,
                        keyboardType: TextInputType.number,
                        hint: '空或 ≤0 默认 200',
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 12.h),
                HostWhiteCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '下注游戏',
                        style: TextStyle(
                          fontSize: 15.sp,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      SizedBox(height: 4.h),
                      Text(
                        '可不选；不选则不绑定彩种',
                        style: TextStyle(
                          fontSize: 12.sp,
                          color: AppColors.textHint,
                        ),
                      ),
                      SizedBox(height: 12.h),
                      if (_games.isEmpty)
                        Text(
                          '本房暂无可用彩种',
                          style: TextStyle(
                            fontSize: 13.sp,
                            color: AppColors.textHint,
                          ),
                        )
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
    this.hint,
    this.inputFormatters,
  });
  final String label;
  final TextEditingController controller;
  final TextInputType? keyboardType;
  final String? hint;
  final List<TextInputFormatter>? inputFormatters;

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
          inputFormatters: inputFormatters,
          decoration: InputDecoration(
            isDense: true,
            hintText: hint,
            hintStyle: TextStyle(fontSize: 13.sp, color: AppColors.textHint),
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
