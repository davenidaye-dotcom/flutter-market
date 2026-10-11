import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'emulator_safe_text_field.dart';

/// 方案 A：浅底胶囊 + 6 个圆角方格房间号输入。
class RoomCodeSixInput extends StatefulWidget {
  const RoomCodeSixInput({
    super.key,
    required this.controller,
    this.focusNode,
    this.onSubmitted,
    this.enabled = true,
  });

  final TextEditingController controller;
  final FocusNode? focusNode;
  final ValueChanged<String>? onSubmitted;
  final bool enabled;

  @override
  State<RoomCodeSixInput> createState() => _RoomCodeSixInputState();
}

class _RoomCodeSixInputState extends State<RoomCodeSixInput> {
  late final FocusNode _focus;
  late final bool _ownsFocus;

  static const _shell = Color(0xFFE8EEF5);
  static const _shellBorder = Color(0xFFD5DEE8);
  static const _cell = Color(0xFFC5D0DC);
  static const _digit = Color(0xFF1A1A1A);

  @override
  void initState() {
    super.initState();
    _ownsFocus = widget.focusNode == null;
    _focus = widget.focusNode ?? FocusNode();
    widget.controller.addListener(_onChanged);
    _focus.addListener(_onChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    _focus.removeListener(_onChanged);
    if (_ownsFocus) _focus.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final text = widget.controller.text;
    final active = _focus.hasFocus ? text.length.clamp(0, 5) : -1;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.enabled ? () => _focus.requestFocus() : null,
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
        decoration: BoxDecoration(
          color: _shell,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: _shellBorder, width: 1),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Row(
              children: List.generate(6, (i) {
                final ch = i < text.length ? text[i] : '';
                final focused = i == active;
                return Expanded(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 3.w),
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: _cell,
                          borderRadius: BorderRadius.circular(8.r),
                          border: focused
                              ? Border.all(
                                  color: const Color(0xFF4A89DC),
                                  width: 1.2,
                                )
                              : null,
                        ),
                        child: Center(
                          child: Text(
                            ch,
                            style: TextStyle(
                              fontSize: 18.sp,
                              fontWeight: FontWeight.w600,
                              height: 1,
                              color: _digit,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
            // 透明输入层：承接数字键盘与粘贴
            Positioned.fill(
              child: Opacity(
                opacity: 0,
                child: EmulatorSafeTextField(
                  controller: widget.controller,
                  focusNode: _focus,
                  enabled: widget.enabled,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.done,
                  maxLength: 6,
                  autofocus: false,
                  style: const TextStyle(color: Colors.transparent, height: 0.01),
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(6),
                  ],
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    counterText: '',
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                  onSubmitted: widget.onSubmitted,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
