import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../../config/theme/app_colors.dart';
import '../../../../data/repositories/providers.dart';
import '../../../../shared/widgets/emulator_safe_text_field.dart';
import '../../../../shared/widgets/page_app_bar.dart';
import '../../data/host_mock.dart';
import '../../widgets/host_ui.dart';

/// 回水设置 — GET/PUT /owner/room/rebate（进房会员默认比例）
class HostDefaultRebatePage extends ConsumerStatefulWidget {
  const HostDefaultRebatePage({super.key, required this.roomId});
  final String roomId;

  @override
  ConsumerState<HostDefaultRebatePage> createState() =>
      _HostDefaultRebatePageState();
}

class _RebateRow {
  _RebateRow({
    required this.gameType,
    required this.gameName,
    required this.controller,
  });

  final String gameType;
  final String gameName;
  final TextEditingController controller;
}

class _HostDefaultRebatePageState extends ConsumerState<HostDefaultRebatePage> {
  final _batchCtrl = TextEditingController();
  final List<_RebateRow> _rows = [];
  bool _loading = true;
  bool _saving = false;
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  @override
  void dispose() {
    _batchCtrl.dispose();
    for (final r in _rows) {
      r.controller.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await ref.read(ownerRepositoryProvider).getRebate();
      if (!mounted) return;
      final ratio = hostNumStr(data['ratio'] ?? data['defaultRatio'] ?? 0, fraction: 2);
      final items = hostRowsOf(data['items']);
      for (final r in _rows) {
        r.controller.dispose();
      }
      _rows.clear();
      if (items.isEmpty) {
        _rows.add(
          _RebateRow(
            gameType: '',
            gameName: '默认',
            controller: TextEditingController(text: ratio),
          ),
        );
      } else {
        for (final m in items) {
          final gt = (m['gameType'] ?? m['type'] ?? '').toString();
          final gn = (m['gameName'] ?? m['typeName'] ?? gt).toString();
          final r = hostNumStr(m['ratio'] ?? ratio, fraction: 2);
          _rows.add(
            _RebateRow(
              gameType: gt,
              gameName: gn.isEmpty ? gt : gn,
              controller: TextEditingController(text: r),
            ),
          );
        }
      }
      _batchCtrl.clear();
      setState(() => _loading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      AppToast.error(e.toString());
    }
  }

  void _applyAll(String text, {TextEditingController? except}) {
    if (_syncing) return;
    _syncing = true;
    for (final r in _rows) {
      if (except != null && identical(r.controller, except)) continue;
      if (r.controller.text != text) r.controller.text = text;
    }
    _syncing = false;
  }

  void _onBatchChanged(String v) {
    final t = v.trim();
    if (t.isEmpty) return;
    _applyAll(t);
  }

  void _onRowChanged(TextEditingController source, String v) {
    if (_syncing) return;
    _applyAll(v.trim(), except: source);
  }

  Future<void> _save() async {
    final raw = _rows.isNotEmpty
        ? _rows.first.controller.text.trim()
        : _batchCtrl.text.trim();
    final ratio = num.tryParse(raw);
    if (ratio == null) {
      AppToast.error('请输入有效回水比例');
      return;
    }
    if (ratio < 0 || ratio > 100) {
      AppToast.error('回水比例范围 0～100');
      return;
    }
    setState(() => _saving = true);
    try {
      final body = <String, dynamic>{
        'ratio': ratio,
        if (_rows.any((r) => r.gameType.isNotEmpty))
          'items': _rows
              .where((r) => r.gameType.isNotEmpty)
              .map((r) => {'gameType': r.gameType, 'ratio': ratio})
              .toList(),
      };
      await ref.read(ownerRepositoryProvider).updateRebate(body);
      _applyAll(hostNumStr(ratio, fraction: 2));
      AppToast.success('保存成功');
    } catch (e) {
      AppToast.error(e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return HostSubPageScaffold(
      title: '回水设置',
      trailing: TextButton(
        onPressed: _saving || _loading ? null : _save,
        child: Text(
          _saving ? '...' : '保存',
          style: TextStyle(
            fontSize: 15.sp,
            color: AppColors.navBlue,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: _loading
          ? const AppPageLoading()
          : ListView(
              padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 24.h),
              children: [
                _card(
                  child: Row(
                    children: [
                      Text('批量修改', style: TextStyle(fontSize: 15.sp)),
                      SizedBox(width: 16.w),
                      const Spacer(),
                      _ratioWithPercent(
                        controller: _batchCtrl,
                        hint: '请输入',
                        onChanged: _onBatchChanged,
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 10.h),
                for (final row in _rows) ...[
                  _card(
                    child: Row(
                      children: [
                        _gameIcon(row.gameType, row.gameName),
                        SizedBox(width: 10.w),
                        Expanded(
                          child: Text(
                            row.gameName,
                            style: TextStyle(fontSize: 15.sp),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        SizedBox(width: 12.w),
                        _ratioWithPercent(
                          controller: row.controller,
                          onChanged: (v) => _onRowChanged(row.controller, v),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: 10.h),
                ],
              ],
            ),
    );
  }

  /// 固定宽度输入框 + 右侧 %，批量与彩种行对齐
  Widget _ratioWithPercent({
    required TextEditingController controller,
    String? hint,
    ValueChanged<String>? onChanged,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 88.w,
          child: _ratioField(
            controller: controller,
            hint: hint,
            onChanged: onChanged,
          ),
        ),
        SizedBox(width: 6.w),
        Text(
          '%',
          style: TextStyle(
            fontSize: 15.sp,
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 12.h),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12.r),
      ),
      child: child,
    );
  }

  Widget _ratioField({
    required TextEditingController controller,
    String? hint,
    ValueChanged<String>? onChanged,
  }) {
    return EmulatorSafeTextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      textAlign: TextAlign.center,
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
      ],
      onChanged: onChanged,
      decoration: InputDecoration(
        hintText: hint,
        isDense: true,
        contentPadding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 10.h),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8.r),
          borderSide: const BorderSide(color: Color(0xFFDDDDDD)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8.r),
          borderSide: const BorderSide(color: Color(0xFFDDDDDD)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8.r),
          borderSide: BorderSide(color: AppColors.navBlue, width: 1.2),
        ),
      ),
    );
  }

  Widget _gameIcon(String gameType, String gameName) {
    final (icon, bg) = _iconFor(gameType, gameName);
    return Container(
      width: 36.w,
      height: 36.w,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8.r),
      ),
      child: Icon(icon, size: 20.sp, color: Colors.white),
    );
  }

  (IconData, Color) _iconFor(String gameType, String gameName) {
    final key = '${gameType}_$gameName'.toUpperCase();
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
}
