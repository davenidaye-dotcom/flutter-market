import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 输入框。
///
/// 非密码：系统输入法（可切手机里的中文键盘）。iOS 上关掉联想或纠错会落到
/// 不能输入中文的安全键盘，所以这里强制打开，并把数字小键盘换成文本输入法。
/// 登录、注册、修改密码传 [secureKeyboard] 或 [obscureText]，继续用安全键盘。
class EmulatorSafeTextField extends StatelessWidget {
  const EmulatorSafeTextField({
    super.key,
    this.controller,
    this.focusNode,
    this.obscureText = false,
    this.secureKeyboard = false,
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
    /// 保证聚焦时 Scrollable 能滚到键盘上方；勿用 zero
    this.scrollPadding = const EdgeInsets.fromLTRB(20, 20, 20, 120),
  });

  final TextEditingController? controller;
  final FocusNode? focusNode;
  final bool obscureText;

  /// 安全键盘。登录密码、注册密码、修改密码使用。
  final bool secureKeyboard;
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
  final EdgeInsets scrollPadding;

  bool get _secure => secureKeyboard || obscureText;

  /// 多行用换行键盘，其余用可切中文的系统输入法。数字小键盘在 iOS 上切不了输入法。
  TextInputType get _imeKeyboard {
    if (maxLines == null || maxLines! > 1) return TextInputType.multiline;
    return TextInputType.text;
  }

  @override
  Widget build(BuildContext context) {
    final secure = _secure;
    return TextField(
      controller: controller,
      focusNode: focusNode,
      obscureText: secure,
      readOnly: readOnly,
      enabled: enabled,
      autofocus: autofocus,
      keyboardType: secure ? (keyboardType ?? TextInputType.text) : _imeKeyboard,
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
      enableSuggestions: secure ? false : true,
      autocorrect: secure ? false : true,
      enableIMEPersonalizedLearning: !secure,
      smartDashesType: secure ? SmartDashesType.disabled : SmartDashesType.enabled,
      smartQuotesType: secure ? SmartQuotesType.disabled : SmartQuotesType.enabled,
      scrollPadding: scrollPadding,
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
