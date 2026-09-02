import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'emulator_safe_text_field.dart';

Future<String?> showTextInputDialog({
  required BuildContext context,
  required String title,
  required String hint,
  bool obscure = false,
  TextInputType? keyboardType,
  bool digitsOnly = false,
}) {
  return showDialog<String?>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: true,
    builder: (ctx) => _TextInputDialog(
      title: title,
      hint: hint,
      obscure: obscure,
      keyboardType: keyboardType,
      digitsOnly: digitsOnly,
    ),
  );
}

class _TextInputDialog extends StatefulWidget {
  const _TextInputDialog({
    required this.title,
    required this.hint,
    this.obscure = false,
    this.keyboardType,
    this.digitsOnly = false,
  });

  final String title;
  final String hint;
  final bool obscure;
  final TextInputType? keyboardType;
  final bool digitsOnly;

  @override
  State<_TextInputDialog> createState() => _TextInputDialogState();
}

class _TextInputDialogState extends State<_TextInputDialog> {
  final _ctrl = TextEditingController();
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _ctrl.text.trim();
    Navigator.pop(context, text.isEmpty ? null : text);
  }

  List<TextInputFormatter>? get _formatters {
    if (!widget.digitsOnly) return null;
    return [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))];
  }

  @override
  Widget build(BuildContext context) {
    // 弹窗内用真实 viewInsets，绕过 StableScreenMetrics 对键盘的屏蔽
    final mq = MediaQueryData.fromView(View.of(context));
    return MediaQuery(
      data: mq,
      child: AlertDialog(
        title: Text(widget.title),
        content: EmulatorSafeTextField(
          controller: _ctrl,
          focusNode: _focusNode,
          obscureText: widget.obscure,
          keyboardType: widget.keyboardType,
          textInputAction: TextInputAction.done,
          inputFormatters: _formatters,
          onSubmitted: (_) => _submit(),
          decoration: InputDecoration(hintText: widget.hint),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          TextButton(onPressed: _submit, child: const Text('确定')),
        ],
      ),
    );
  }
}
