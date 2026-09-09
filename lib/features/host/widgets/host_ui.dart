import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../config/theme/app_colors.dart';
import '../../../shared/widgets/emulator_safe_dialog.dart';
import '../../../shared/widgets/emulator_safe_text_field.dart';
import '../../../shared/widgets/gradient_background.dart';
import '../../../shared/widgets/page_app_bar.dart';

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
  final result = await showEmulatorSafeDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title, style: TextStyle(fontSize: 16.sp)),
      content: Text(message, style: TextStyle(fontSize: 14.sp, color: AppColors.textSecondary)),
      actions: [
        TextButton(onPressed: safeDialogPop(ctx, false), child: Text(cancelText)),
        TextButton(
          onPressed: safeDialogPop(ctx, true),
          child: Text(confirmText, style: TextStyle(color: danger ? AppColors.danger : AppColors.navBlue)),
        ),
      ],
    ),
  );
  return result == true;
}
