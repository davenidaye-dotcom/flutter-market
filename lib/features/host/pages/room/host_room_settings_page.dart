import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../../config/theme/app_colors.dart';
import '../../../../shared/widgets/emulator_safe_text_field.dart';
import '../../../../shared/widgets/gradient_background.dart';
import '../../../../shared/widgets/page_app_bar.dart';
import 'host_advance_rebate_page.dart';
import 'host_default_rebate_page.dart';
import 'host_odds_limits_page.dart';

/// \u623f\u95f4\u8bbe\u7f6e\uff1a\u8d54\u7387 / \u56de\u6c34 / \u63d0\u524d\u8fd4\u70b9
class HostRoomSettingsPage extends StatelessWidget {
  const HostRoomSettingsPage({super.key, required this.roomId});

  final String roomId;

  @override
  Widget build(BuildContext context) {
    final items = <(String, Widget)>[
      ('\u8d54\u7387\u8bbe\u7f6e', HostOddsLimitsPage(roomId: roomId)),
      ('\u56de\u6c34\u8bbe\u7f6e', HostDefaultRebatePage(roomId: roomId)),
      ('\u63d0\u524d\u8fd4\u70b9', HostAdvanceRebatePage(roomId: roomId)),
    ];

    return AppPageScaffold(
      body: GradientBackground(
        child: SafeArea(
          child: Column(
            children: [
              PageAppBar(title: '\u623f\u95f4\u8bbe\u7f6e', onBack: () => appSafePop(context)),
              Padding(
                padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 0),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12.r),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      for (var i = 0; i < items.length; i++) ...[
                        if (i > 0) Divider(height: 1, color: AppColors.divider),
                        InkWell(
                          onTap: () => pushHostPage(context, items[i].$2),
                          child: Padding(
                            padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 16.h),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(items[i].$1, style: TextStyle(fontSize: 15.sp, color: AppColors.textPrimary)),
                                ),
                                Icon(Icons.chevron_right, color: AppColors.textHint, size: 18.sp),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
