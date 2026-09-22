import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../config/theme/app_colors.dart';
import '../../../shared/widgets/emulator_safe_text_field.dart';
import '../../../shared/widgets/gradient_background.dart';
import '../../../shared/widgets/page_app_bar.dart';
import '../../../shared/widgets/stable_screen_metrics.dart';

/// 房主二级页通用壳（全屏，无底部 Tab）
class HostSubPageScaffold extends StatelessWidget {
  const HostSubPageScaffold({
    super.key,
    required this.title,
    required this.body,
    this.trailing,
    this.bottomBar,
    this.onBack,
  });

  final String title;
  final Widget body;
  final Widget? trailing;
  final Widget? bottomBar;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return AppPageScaffold(
      resizeToAvoidBottomInset: true,
      body: GradientBackground(
        child: SafeArea(
          child: Column(
            children: [
              PageAppBar(
                title: title,
                onBack: onBack ?? () => appSafePop(context),
                trailing: trailing,
              ),
              Expanded(child: body),
              ?bottomBar,
            ],
          ),
        ),
      ),
    );
  }
}

class HostWhiteCard extends StatelessWidget {
  const HostWhiteCard({super.key, required this.child, this.padding, this.onTap});

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final content = Container(
      width: double.infinity,
      padding: padding ?? EdgeInsets.all(14.w),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12.r),
      ),
      child: child,
    );
    if (onTap == null) return content;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12.r),
        child: content,
      ),
    );
  }
}

class HostPrimaryButton extends StatelessWidget {
  const HostPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.enabled = true,
    this.color,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool enabled;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final bg = enabled ? (color ?? AppColors.navBlue) : const Color(0xFFBDBDBD);
    return GestureDetector(
      onTap: enabled ? onPressed : null,
      child: Container(
        height: 44.h,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(22.r),
        ),
        child: Text(label, style: TextStyle(fontSize: 16.sp, color: Colors.white, fontWeight: FontWeight.w600)),
      ),
    );
  }
}

class HostFilterChipBar extends StatelessWidget {
  const HostFilterChipBar({
    super.key,
    required this.labels,
    required this.current,
    required this.onChanged,
  });

  final List<String> labels;
  final int current;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: EdgeInsets.symmetric(horizontal: 12.w),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++) ...[
            if (i > 0) SizedBox(width: 8.w),
            GestureDetector(
              onTap: () => onChanged(i),
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
                decoration: BoxDecoration(
                  color: current == i ? AppColors.navBlue : Colors.white,
                  borderRadius: BorderRadius.circular(16.r),
                ),
                child: Text(
                  labels[i],
                  style: TextStyle(
                    fontSize: 13.sp,
                    color: current == i ? Colors.white : AppColors.navBlue,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

Future<bool> hostConfirm(
  BuildContext context, {
  required String title,
  required String message,
  String confirmText = '确定',
  String cancelText = '取消',
  bool danger = false,
}) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) => _HostKeyboardAware(
      child: _HostSheetShell(
        title: title,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              message,
              style: TextStyle(fontSize: 14.sp, color: AppColors.textSecondary, height: 1.4),
            ),
            SizedBox(height: 20.h),
            _HostSheetActions(
              cancelText: cancelText,
              confirmText: confirmText,
              danger: danger,
              onCancel: () => Navigator.pop(ctx, false),
              onConfirm: () => Navigator.pop(ctx, true),
            ),
          ],
        ),
      ),
    ),
  );
  return result == true;
}

/// 竞品风格：底部弹出、单行输入、取消/保存并排。
/// 真机软键盘弹出时整体上移，输入框与按钮不被挡住。
Future<String?> hostInputSheet(
  BuildContext context, {
  required String title,
  String? initial,
  String? hint,
  String? suffixText,
  TextInputType? keyboardType,
  bool obscureText = false,
  String confirmText = '保存',
  String cancelText = '取消',
}) {
  final ctrl = TextEditingController(text: initial ?? '');
  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) {
      return _HostKeyboardAware(
        child: _HostSheetShell(
          title: title,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              EmulatorSafeTextField(
                controller: ctrl,
                autofocus: true,
                obscureText: obscureText,
                keyboardType: keyboardType,
                textInputAction: TextInputAction.done,
                scrollPadding: EdgeInsets.fromLTRB(20.w, 20.h, 20.w, 160.h),
                onSubmitted: (v) {
                  FocusManager.instance.primaryFocus?.unfocus();
                  Navigator.pop(ctx, v.trim());
                },
                decoration: InputDecoration(
                  hintText: hint,
                  suffixText: suffixText,
                  contentPadding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 14.h),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10.r),
                    borderSide: const BorderSide(color: Color(0xFFDDDDDD)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10.r),
                    borderSide: const BorderSide(color: Color(0xFFDDDDDD)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10.r),
                    borderSide: BorderSide(color: AppColors.navBlue, width: 1.2),
                  ),
                ),
              ),
              SizedBox(height: 16.h),
              _HostSheetActions(
                cancelText: cancelText,
                confirmText: confirmText,
                onCancel: () {
                  FocusManager.instance.primaryFocus?.unfocus();
                  Navigator.pop(ctx);
                },
                onConfirm: () {
                  FocusManager.instance.primaryFocus?.unfocus();
                  Navigator.pop(ctx, ctrl.text.trim());
                },
              ),
            ],
          ),
        ),
      );
    },
  ).whenComplete(ctrl.dispose);
}

/// 底部弹出多字段表单。fields 返回 true 时关闭并回 true。
Future<bool> hostFormSheet(
  BuildContext context, {
  required String title,
  required Widget Function(BuildContext ctx, void Function(VoidCallback) setSheet) buildFields,
  String confirmText = '确定',
  String cancelText = '取消',
  Future<bool> Function()? onConfirm,
}) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setSheet) {
          return _HostKeyboardAware(
            child: _HostSheetShell(
              title: title,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  buildFields(ctx, setSheet),
                  SizedBox(height: 16.h),
                  _HostSheetActions(
                    cancelText: cancelText,
                    confirmText: confirmText,
                    onCancel: () => Navigator.pop(ctx, false),
                    onConfirm: () async {
                      if (onConfirm != null) {
                        final ok = await onConfirm();
                        if (ok && ctx.mounted) Navigator.pop(ctx, true);
                        return;
                      }
                      Navigator.pop(ctx, true);
                    },
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
  return result == true;
}

/// 键盘避让：订阅 MediaQuery.viewInsets，整块顶到键盘上方。
class _HostKeyboardAware extends StatelessWidget {
  const _HostKeyboardAware({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    // MediaQuery 订阅保证键盘弹出/收起时重建；View 兜底防被上层篡改
    final mqInset = MediaQuery.viewInsetsOf(context).bottom;
    final viewInset = realKeyboardInset(context);
    final inset = mqInset >= viewInset ? mqInset : viewInset;
    return AnimatedPadding(
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: inset),
      child: SingleChildScrollView(
        reverse: true,
        physics: const ClampingScrollPhysics(),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        child: child,
      ),
    );
  }
}

class _HostSheetShell extends StatelessWidget {
  const _HostSheetShell({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(16.r)),
        ),
        padding: EdgeInsets.fromLTRB(16.w, 10.h, 16.w, 16.h),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36.w,
                height: 4.h,
                decoration: BoxDecoration(
                  color: const Color(0xFFDDDDDD),
                  borderRadius: BorderRadius.circular(2.r),
                ),
              ),
            ),
            SizedBox(height: 12.h),
            Text(title, style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w700)),
            SizedBox(height: 14.h),
            child,
          ],
        ),
      ),
    );
  }
}

class _HostSheetActions extends StatelessWidget {
  const _HostSheetActions({
    required this.cancelText,
    required this.confirmText,
    required this.onCancel,
    required this.onConfirm,
    this.danger = false,
  });

  final String cancelText;
  final String confirmText;
  final VoidCallback onCancel;
  final VoidCallback onConfirm;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: onCancel,
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF666666),
              side: const BorderSide(color: Color(0xFFDDDDDD)),
              padding: EdgeInsets.symmetric(vertical: 12.h),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.r)),
            ),
            child: Text('✕ $cancelText', style: TextStyle(fontSize: 15.sp)),
          ),
        ),
        SizedBox(width: 12.w),
        Expanded(
          child: FilledButton(
            onPressed: onConfirm,
            style: FilledButton.styleFrom(
              backgroundColor: danger ? AppColors.danger : AppColors.navBlue,
              padding: EdgeInsets.symmetric(vertical: 12.h),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.r)),
            ),
            child: Text('✓ $confirmText', style: TextStyle(fontSize: 15.sp, color: Colors.white)),
          ),
        ),
      ],
    );
  }
}
