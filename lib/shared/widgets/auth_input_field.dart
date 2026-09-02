import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../config/theme/app_colors.dart';
import 'emulator_safe_text_field.dart';

/// 认证输入框
class AuthInputField extends StatelessWidget {
  const AuthInputField({
    super.key,
    required this.controller,
    required this.hint,
    required this.icon,
    this.obscureText = false,
    this.onClear,
  });

  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final bool obscureText;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Icon(icon, color: AppColors.textSecondary, size: 20.sp),
            SizedBox(width: 12.w),
            Expanded(
              child: EmulatorSafeTextField(
                controller: controller,
                obscureText: obscureText,
                decoration: InputDecoration(hintText: hint),
                style: TextStyle(fontSize: 15.sp, color: AppColors.textPrimary),
              ),
            ),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: controller,
              builder: (_, value, __) {
                if (value.text.isEmpty) return const SizedBox.shrink();
                return GestureDetector(
                  onTap: onClear,
                  child: Icon(Icons.cancel, color: AppColors.textHint, size: 18.sp),
                );
              },
            ),
          ],
        ),
        SizedBox(height: 12.h),
        const Divider(height: 1),
      ],
    );
  }
}
