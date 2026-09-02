import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../config/theme/app_colors.dart';

/// 下注输入栏（纯展示 + 点击回调，不用 TextField，避免模拟器弹系统键盘卡死）
class BetInputBar extends StatelessWidget {
  const BetInputBar({
    super.key,
    required this.controller,
    required this.onTapInput,
    required this.onToggleMenu,
    required this.onSend,
    this.menuOpen = false,
    this.keypadOpen = false,
    this.enabled = true,
    this.submitting = false,
  });

  final TextEditingController controller;
  final VoidCallback onTapInput;
  final VoidCallback onToggleMenu;
  final VoidCallback onSend;
  final bool menuOpen;
  final bool keypadOpen;
  final bool enabled;
  /// 仅发送按钮 loading；键盘区域保持可点
  final bool submitting;

  @override
  Widget build(BuildContext context) {
    final bg = !enabled
        ? const Color(0xFFE8E8E8)
        : (keypadOpen || menuOpen ? Colors.white : const Color(0xFFEEEEEE));
    final hint = enabled ? '请输入投注金额' : '房主不可下注';
    final fieldBg = enabled ? const Color(0xFFF5F5F5) : const Color(0xFFDDDDDD);
    final textColor = enabled ? AppColors.textPrimary : AppColors.textHint;
    final iconColor = !enabled
        ? AppColors.textHint
        : (menuOpen ? AppColors.navBlue : const Color(0xFF333333));

    return Material(
      color: bg,
      child: Padding(
        padding: EdgeInsets.fromLTRB(12.w, 10.h, 12.w, 10.h),
        child: ValueListenableBuilder<TextEditingValue>(
          valueListenable: controller,
          builder: (_, value, _) {
            final empty = value.text.isEmpty;
            final canSend = enabled && !submitting && value.text.trim().isNotEmpty;
            return Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: enabled ? onTapInput : null,
                    behavior: HitTestBehavior.opaque,
                    child: Container(
                      height: 44.h,
                      alignment: Alignment.centerLeft,
                      padding: EdgeInsets.symmetric(horizontal: 12.w),
                      decoration: BoxDecoration(
                        color: fieldBg,
                        borderRadius: BorderRadius.circular(4.r),
                        border: Border.all(
                          color: keypadOpen && enabled
                              ? AppColors.navBlue
                              : (enabled ? const Color(0xFFDDDDDD) : const Color(0xFFCCCCCC)),
                          width: keypadOpen && enabled ? 1.5 : 1,
                        ),
                      ),
                      child: Text(
                        empty ? hint : value.text,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14.sp,
                          color: empty ? AppColors.textHint : textColor,
                        ),
                      ),
                    ),
                  ),
                ),
                SizedBox(width: 10.w),
                GestureDetector(
                  onTap: canSend ? onSend : null,
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4.w, vertical: 6.h),
                    child: submitting
                        ? SizedBox(
                            width: 18.w,
                            height: 18.w,
                            child: const CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(
                            '发送',
                            style: TextStyle(
                              fontSize: 15.sp,
                              fontWeight: FontWeight.w600,
                              color: canSend ? AppColors.navBlue : AppColors.textHint,
                            ),
                          ),
                  ),
                ),
                SizedBox(width: 4.w),
                GestureDetector(
                  onTap: enabled ? onToggleMenu : null,
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: EdgeInsets.all(6.w),
                    child: Icon(Icons.apps, size: 26.sp, color: iconColor),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
