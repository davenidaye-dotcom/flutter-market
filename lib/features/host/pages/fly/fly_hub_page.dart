import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../../config/theme/app_colors.dart';
import '../../../../shared/widgets/page_app_bar.dart';
import '../../widgets/host_ui.dart';
import 'fly_balance_page.dart';
import 'fly_bind_page.dart';
import 'fly_logs_page.dart';
import 'fly_odds_page.dart';
import 'fly_report_page.dart';

/// 飞单管理 — 功能入口
class FlyHubPage extends StatelessWidget {
  const FlyHubPage({super.key, required this.roomId});

  final String roomId;

  @override
  Widget build(BuildContext context) {
    final menus = <(String, IconData, Widget)>[
      ('绑定代理会员', Icons.link, FlyBindPage(roomId: roomId)),
      ('飞单赔率设置', Icons.tune, FlyOddsPage(roomId: roomId)),
      ('飞单报表', Icons.bar_chart, FlyReportPage(roomId: roomId)),
      ('额度变动', Icons.account_balance_wallet_outlined, FlyBalancePage(roomId: roomId)),
      ('操作日志', Icons.history, FlyLogsPage(roomId: roomId)),
    ];

    return HostSubPageScaffold(
      title: '飞单管理',
      body: ListView.separated(
        padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 16.h),
        itemCount: menus.length,
        separatorBuilder: (_, _) => SizedBox(height: 8.h),
        itemBuilder: (_, i) {
          final (label, icon, page) = menus[i];
          return Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12.r),
            child: InkWell(
              borderRadius: BorderRadius.circular(12.r),
              onTap: () => pushHostPage(context, page),
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
                child: Row(
                  children: [
                    Icon(icon, color: AppColors.navBlue, size: 22.sp),
                    SizedBox(width: 12.w),
                    Expanded(
                      child: Text(label, style: TextStyle(fontSize: 15.sp, color: AppColors.textPrimary)),
                    ),
                    Icon(Icons.chevron_right, color: AppColors.textHint, size: 20.sp),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
