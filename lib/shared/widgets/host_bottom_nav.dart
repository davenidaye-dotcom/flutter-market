import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../config/theme/app_colors.dart';
import 'red_count_badge.dart';

class HostBottomNavItem {
  const HostBottomNavItem({required this.icon, required this.label});
  final IconData icon;
  final String label;
}

/// 竞品：在线客服｜房间管理｜个人中心｜审核列表
class HostBottomNavBar extends StatelessWidget {
  const HostBottomNavBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
    this.auditBadge = 0,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;
  /// 待审核总数：个人中心 + 审核列表两个 Tab 都显示
  final int auditBadge;

  static const items = [
    HostBottomNavItem(icon: Icons.support_agent, label: '在线客服'),
    HostBottomNavItem(icon: Icons.settings, label: '房间管理'),
    HostBottomNavItem(icon: Icons.person_outline, label: '个人中心'),
    HostBottomNavItem(icon: Icons.account_balance_wallet_outlined, label: '审核列表'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.primaryLight.withValues(alpha: 0.25))),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, -2)),
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
              final color = active ? const Color(0xFF2F7FD1) : const Color(0xFF3A8AD8);
              final showBadge = auditBadge > 0 && (i == 2 || i == 3);
              return Expanded(
                child: InkWell(
                  onTap: () => onTap(i),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      BadgedIcon(
                        count: showBadge ? auditBadge : 0,
                        child: Icon(item.icon, color: color, size: 24.sp),
                      ),
                      SizedBox(height: 2.h),
                      Text(
                        item.label,
                        style: TextStyle(
                          fontSize: 12.sp,
                          color: active ? const Color(0xFF1A1A1A) : const Color(0xFF333333),
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
