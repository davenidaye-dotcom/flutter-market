import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../../config/theme/app_colors.dart';
import '../../../../shared/widgets/page_app_bar.dart';
import '../../widgets/host_ui.dart';
import '../reports/rebate_report_page.dart';
import 'host_pending_commission_page.dart';
import 'host_pending_rebate_page.dart';
import 'host_rebate_records_page.dart';

/// 回水：未回水、未返佣、回水记录/报表、抽佣记录/报表
class HostRebateHubPage extends StatelessWidget {
  const HostRebateHubPage({super.key, required this.roomId});

  final String roomId;

  @override
  Widget build(BuildContext context) {
    final items = <_HubItem>[
      _HubItem(
        '用户未回水',
        Icons.access_time,
        const Color(0xFFFFE0B2),
        const Color(0xFFEF6C00),
        HostPendingRebatePage(roomId: roomId),
      ),
      _HubItem(
        '代理未返佣',
        Icons.groups_outlined,
        const Color(0xFFE1BEE7),
        const Color(0xFF6A1B9A),
        HostPendingCommissionPage(roomId: roomId),
      ),
      _HubItem(
        '彩票回水记录',
        Icons.receipt_long_outlined,
        const Color(0xFFB2DFDB),
        const Color(0xFF00897B),
        HostRebateRecordsPage(roomId: roomId),
      ),
      _HubItem(
        '彩票回水报表',
        Icons.bar_chart,
        const Color(0xFFBBDEFB),
        const Color(0xFF1565C0),
        RebateReportPage(roomId: roomId),
      ),
      _HubItem(
        '代理抽佣记录',
        Icons.receipt_long_outlined,
        const Color(0xFFFFE0B2),
        const Color(0xFFEF6C00),
        HostRebateRecordsPage(roomId: roomId, commission: true),
      ),
      _HubItem(
        '代理抽佣报表',
        Icons.bar_chart,
        const Color(0xFFD1C4E9),
        const Color(0xFF5E35B1),
        RebateReportPage(roomId: roomId, commission: true),
      ),
    ];
    return HostSubPageScaffold(
      title: '回水',
      body: ListView(
        padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 16.h),
        children: [
          Padding(
            padding: EdgeInsets.only(left: 4.w, bottom: 10.h),
            child: Text(
              '回水处理与查询',
              style: TextStyle(
                fontSize: 14.sp,
                color: AppColors.navBlue,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          for (final item in items) ...[
            HostWhiteCard(
              onTap: () => pushHostPage(context, item.page),
              padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 14.h),
              child: Row(
                children: [
                  Container(
                    width: 36.w,
                    height: 36.w,
                    decoration: BoxDecoration(
                      color: item.bg,
                      borderRadius: BorderRadius.circular(8.r),
                    ),
                    child: Icon(item.icon, color: item.fg, size: 20.sp),
                  ),
                  SizedBox(width: 12.w),
                  Expanded(
                    child: Text(
                      item.label,
                      style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w600),
                    ),
                  ),
                  Icon(Icons.chevron_right, color: AppColors.textHint, size: 20.sp),
                ],
              ),
            ),
            SizedBox(height: 10.h),
          ],
        ],
      ),
    );
  }
}

class _HubItem {
  const _HubItem(this.label, this.icon, this.bg, this.fg, this.page);

  final String label;
  final IconData icon;
  final Color bg;
  final Color fg;
  final Widget page;
}
