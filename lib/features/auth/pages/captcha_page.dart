import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import '../../../config/env/env_config.dart';
import '../../profile/app_release.dart';
import '../../../config/theme/app_colors.dart';
import '../../../core/sdk/dingxiang/dingxiang_provider.dart';
import '../../../core/sdk/dingxiang/dingxiang_service.dart';
import '../../../shared/widgets/app_logo.dart';
import '../../../shared/widgets/emulator_safe_text_field.dart';
import '../../../shared/widgets/gradient_background.dart';

/// 顶象滑块验证占位页 — 后期替换为 SDK WebView/Native 组件
class CaptchaPage extends ConsumerStatefulWidget {
  const CaptchaPage({super.key});

  @override
  ConsumerState<CaptchaPage> createState() => _CaptchaPageState();
}

class _CaptchaPageState extends ConsumerState<CaptchaPage> {
  double _sliderValue = 0;
  String _version = EnvConfig.appVersion;

  @override
  void initState() {
    super.initState();
    Future.microtask(_loadVersion);
  }

  Future<void> _loadVersion() async {
    final version = await AppRelease.footerVersion();
    if (!mounted) return;
    setState(() => _version = version);
  }

  void _verify() {
    ref.read(dingxiangServiceProvider);
    (ref.read(dingxiangServiceProvider) as DingxiangPlaceholderService)
        .setVerifyResult(const DingxiangVerifyResult(success: true, token: 'mock_dx_token'));
    context.pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return AppPageScaffold(
      body: GradientBackground(
        child: SafeArea(
          child: Stack(
            children: [
              Column(
                children: [
                  SizedBox(height: 48.h),
                  const Center(child: AppLogoHeader()),
                  SizedBox(height: 40.h),
                  _CaptchaDialog(
                    sliderValue: _sliderValue,
                    onSliderChanged: (v) => setState(() => _sliderValue = v),
                    onVerify: _verify,
                    onClose: () => context.pop(false),
                    onRefresh: () => setState(() => _sliderValue = 0),
                  ),
                ],
              ),
              Positioned(
                right: 16.w,
                bottom: 16.h,
                child: GestureDetector(
                  onTap: () => AppRelease.check(context),
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 6.h),
                    child: Text('v$_version', style: TextStyle(fontSize: 11.sp, color: AppColors.textHint)),
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

class _CaptchaDialog extends StatelessWidget {
  const _CaptchaDialog({
    required this.sliderValue,
    required this.onSliderChanged,
    required this.onVerify,
    required this.onClose,
    required this.onRefresh,
  });

  final double sliderValue;
  final ValueChanged<double> onSliderChanged;
  final VoidCallback onVerify;
  final VoidCallback onClose;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 24.w),
      child: Container(
        padding: EdgeInsets.all(16.w),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12.r),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 16)],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8.r),
              child: Stack(
                children: [
                  Container(
                    height: 160.h,
                    width: double.infinity,
                    color: const Color(0xFF87CEEB),
                    child: Icon(Icons.landscape, size: 64.sp, color: Colors.white54),
                  ),
                  Positioned(
                    left: sliderValue * 200.w,
                    top: 40.h,
                    child: Container(
                      width: 50.w,
                      height: 50.w,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.8),
                        border: Border.all(color: AppColors.primary),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 12.h),
            Container(
              height: 40.h,
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.divider),
                borderRadius: BorderRadius.circular(4.r),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40.w,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 4)],
                    ),
                    child: Icon(Icons.arrow_forward, size: 18.sp),
                  ),
                  Expanded(
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        overlayShape: SliderComponentShape.noOverlay,
                        trackHeight: 40,
                        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 0),
                      ),
                      child: Slider(
                        value: sliderValue,
                        onChanged: onSliderChanged,
                        onChangeEnd: (v) { if (v > 0.8) onVerify(); },
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 8.h),
            Align(
              alignment: Alignment.center,
              child: Text('滑动滑块填充拼图', style: TextStyle(fontSize: 12.sp, color: AppColors.textSecondary)),
            ),
            SizedBox(height: 8.h),
            Row(
              children: [
                _iconBtn(Icons.close, onClose),
                SizedBox(width: 12.w),
                _iconBtn(Icons.refresh, onRefresh),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _iconBtn(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32.w,
        height: 32.w,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.textHint),
        ),
        child: Icon(icon, size: 16.sp, color: AppColors.textSecondary),
      ),
    );
  }
}
