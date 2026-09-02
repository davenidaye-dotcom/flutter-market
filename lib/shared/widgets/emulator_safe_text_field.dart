import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 模拟器友好的 TextField：关闭联想/纠错，减小 IME 触发的布局抖动。
class EmulatorSafeTextField extends StatelessWidget {
  const EmulatorSafeTextField({
    super.key,
    this.controller,
    this.focusNode,
    this.obscureText = false,
    this.readOnly = false,
    this.enabled = true,
    this.keyboardType,
    this.textInputAction,
    this.onChanged,
    this.onSubmitted,
    this.decoration,
    this.style,
    this.maxLines = 1,
    this.maxLength,
    this.autofocus = false,
    this.textAlign = TextAlign.start,
    this.inputFormatters,
  });

  final TextEditingController? controller;
  final FocusNode? focusNode;
  final bool obscureText;
  final bool readOnly;
  final bool enabled;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final InputDecoration? decoration;
  final TextStyle? style;
  final int? maxLines;
  final int? maxLength;
  final bool autofocus;
  final TextAlign textAlign;
  final List<TextInputFormatter>? inputFormatters;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      obscureText: obscureText,
      readOnly: readOnly,
      enabled: enabled,
      autofocus: autofocus,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      decoration: decoration,
      style: style,
      maxLines: maxLines,
      maxLength: maxLength,
      textAlign: textAlign,
      inputFormatters: inputFormatters,
      enableInteractiveSelection: true,
      enableSuggestions: false,
      autocorrect: false,
      smartDashesType: SmartDashesType.disabled,
      smartQuotesType: SmartQuotesType.disabled,
      scrollPadding: EdgeInsets.zero,
    );
  }
}

/// 页面级 Scaffold：默认不随键盘 resize，避免 ScreenUtil 在模拟器整树重建。
class AppPageScaffold extends Scaffold {
  AppPageScaffold({
    super.key,
    super.appBar,
    super.body,
    super.drawer,
    super.endDrawer,
    super.floatingActionButton,
    super.floatingActionButtonLocation,
    super.bottomNavigationBar,
    super.backgroundColor,
    super.extendBody = false,
    super.extendBodyBehindAppBar = false,
    bool resizeToAvoidBottomInset = false,
  }) : super(resizeToAvoidBottomInset: resizeToAvoidBottomInset);
}
