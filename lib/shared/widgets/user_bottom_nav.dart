import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../config/theme/app_colors.dart';
import 'race_car_icon.dart';
import 'red_count_badge.dart';

class UserBottomNavItem {
  const UserBottomNavItem({
    required this.label,
    this.icon,
    this.raceCar = false,
  });

  final IconData? icon;
  final String label;
  final bool raceCar;
}

/// 在线客服、钱包中心、游戏、房间介绍、个人中心。游戏在正中，壳分支仍是大厅为 0。
class UserBottomNavBar extends StatelessWidget {
  const UserBottomNavBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
    this.csBadge = 0,
  });

  /// 底栏视觉下标：0 客服 … 2 游戏 … 4 个人
  final int currentIndex;
  final ValueChanged<int> onTap;
  /// 在线客服未读
  final int csBadge;

  static const items = [
    UserBottomNavItem(icon: Icons.support_agent, label: '在线客服'),
    UserBottomNavItem(icon: Icons.verified_user_outlined, label: '钱包中心'),
    UserBottomNavItem(label: '游戏', raceCar: true),
    UserBottomNavItem(icon: Icons.account_balance_wallet_outlined, label: '房间介绍'),
    UserBottomNavItem(icon: Icons.people_alt_outlined, label: '个人中心'),
  ];

  /// 视觉下标 → 壳分支。游戏在中间，对应分支 0。
  static const branches = [1, 2, 0, 3, 4];

  static int visualIndex(int branch) {
    final i = branches.indexOf(branch);
    return i < 0 ? 0 : i;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.primaryLight.withValues(alpha: 0.3))),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 56.h,
          child: Row(
            children: List.generate(items.length, (i) {
              final item = items[i];
              final active = currentIndex == i;
              // 图标保持蓝色；文字加深，更易读
              final iconColor = active ? const Color(0xFF2F7FD1) : const Color(0xFF3A8AD8);
              final textColor = active ? const Color(0xFF1A1A1A) : const Color(0xFF333333);
              return Expanded(
                child: InkWell(
                  onTap: () => onTap(i),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      BadgedIcon(
                        count: i == 0 ? csBadge : 0,
                        child: item.raceCar
                            ? RaceCarIcon(color: iconColor, size: 24.sp)
                            : Icon(item.icon!, color: iconColor, size: 24.sp),
                      ),
                      SizedBox(height: 2.h),
                      Text(
                        item.label,
                        style: TextStyle(
                          fontSize: 12.sp,
                          color: textColor,
                          fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}
