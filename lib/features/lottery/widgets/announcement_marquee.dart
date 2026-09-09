import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../config/theme/app_colors.dart';

/// 彩种列表顶栏公告：横向无缝跑马灯。
class AnnouncementMarquee extends StatefulWidget {
  const AnnouncementMarquee({super.key, required this.text});

  final String text;

  @override
  State<AnnouncementMarquee> createState() => _AnnouncementMarqueeState();
}

class _AnnouncementMarqueeState extends State<AnnouncementMarquee>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  double _textWidth = 0;
  double _viewportWidth = 0;

  /// 两段文案之间的空隙
  static const double _gap = 48;

  /// 约 40 逻辑像素/秒
  static const double _pxPerSec = 40;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this);
  }

  @override
  void didUpdateWidget(covariant AnnouncementMarquee oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _measureAndStart();
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _measureAndStart() {
    final text = widget.text.trim().isEmpty ? '欢迎进入本房间' : widget.text.trim();
    if (_viewportWidth <= 0) {
      _controller.stop();
      return;
    }
    final style = TextStyle(fontSize: 13.sp, color: AppColors.textPrimary);
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    _textWidth = painter.width;
    // 短文案也滚动：以视口宽度为周期，避免停住无感
    final cycle = (_textWidth + _gap).clamp(_viewportWidth + _gap, double.infinity);
    final ms = ((cycle / _pxPerSec) * 1000).round().clamp(4000, 60000);
    _controller
      ..stop()
      ..duration = Duration(milliseconds: ms)
      ..repeat();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final text = widget.text.trim().isEmpty ? '欢迎进入本房间' : widget.text.trim();
    final style = TextStyle(fontSize: 13.sp, color: AppColors.textPrimary);

    return Container(
      margin: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20.r),
      ),
      child: Row(
        children: [
          Icon(Icons.campaign, color: AppColors.primary, size: 18.sp),
          SizedBox(width: 8.w),
          Expanded(
            child: SizedBox(
              height: 18.sp,
              child: ClipRect(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final vw = constraints.maxWidth;
                    if (vw != _viewportWidth && vw > 0) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (!mounted) return;
                        _viewportWidth = vw;
                        _measureAndStart();
                      });
                    }
                    final cycle = (_textWidth + _gap)
                        .clamp((_viewportWidth > 0 ? _viewportWidth : vw) + _gap, double.infinity);
                    return AnimatedBuilder(
                      animation: _controller,
                      builder: (context, _) {
                        final dx = -_controller.value * cycle;
                        Widget label(String t) => Text(
                              t,
                              style: style,
                              maxLines: 1,
                              softWrap: false,
                            );
                        return Stack(
                          clipBehavior: Clip.hardEdge,
                          children: [
                            Transform.translate(
                              offset: Offset(dx, 0),
                              child: label(text),
                            ),
                            Transform.translate(
                              offset: Offset(dx + cycle, 0),
                              child: label(text),
                            ),
                          ],
                        );
                      },
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
