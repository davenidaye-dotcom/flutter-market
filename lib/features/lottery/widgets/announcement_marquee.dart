import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../config/theme/app_colors.dart';

/// 彩种列表顶栏公告：匀速连续滚动，下一段紧跟上一段。
class AnnouncementMarquee extends StatefulWidget {
  const AnnouncementMarquee({super.key, required this.text});

  final String text;

  @override
  State<AnnouncementMarquee> createState() => _AnnouncementMarqueeState();
}

class _AnnouncementMarqueeState extends State<AnnouncementMarquee>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  Duration _elapsed = Duration.zero;

  /// 当前这段文案开始滚动的时刻。换文案才重置，宽度变化不打断。
  Duration _origin = Duration.zero;
  double _textWidth = 0;
  double _viewportWidth = 0;
  String _measuredText = '';

  /// 两段文案之间的空隙
  static const double _gap = 32;

  /// 约 40 逻辑像素/秒
  static const double _pxPerSec = 40;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((elapsed) {
      if (!mounted) return;
      setState(() => _elapsed = elapsed);
    })..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _scheduleMeasure(double vw, String text, TextStyle style, TextScaler scaler) {
    if ((vw - _viewportWidth).abs() < 0.5 && text == _measuredText && _textWidth > 0) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: TextDirection.ltr,
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      final width = painter.width;
      if ((vw - _viewportWidth).abs() < 0.5 &&
          text == _measuredText &&
          (width - _textWidth).abs() < 0.5) {
        return;
      }
      setState(() {
        if (text != _measuredText) {
          _origin = _elapsed;
        }
        _viewportWidth = vw;
        _measuredText = text;
        _textWidth = width;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final text = widget.text.trim().isEmpty ? '欢迎进入本房间' : widget.text.trim();
    final style = TextStyle(fontSize: 13.sp, color: AppColors.textPrimary, height: 1);
    final scaler = MediaQuery.textScalerOf(context);

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
                    if (vw > 0) {
                      _scheduleMeasure(vw, text, style, scaler);
                    }
                    final cycle = _textWidth + _gap;
                    if (cycle <= _gap || vw <= 0) {
                      return Text(
                        text,
                        style: style,
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.clip,
                      );
                    }
                    final seconds = (_elapsed - _origin).inMicroseconds / 1000000.0;
                    final dx = -((seconds * _pxPerSec) % cycle);
                    final copies = (vw / cycle).ceil() + 2;
                    // OverflowBox：滚动条比视口宽时不触发 RenderFlex overflow（仍由外层 ClipRect 裁切）
                    return OverflowBox(
                      maxWidth: double.infinity,
                      alignment: Alignment.centerLeft,
                      child: Transform.translate(
                        offset: Offset(dx, 0),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (var i = 0; i < copies; i++) ...[
                              SizedBox(
                                width: _textWidth,
                                child: Text(text, style: style, maxLines: 1, softWrap: false),
                              ),
                              const SizedBox(width: _gap),
                            ],
                          ],
                        ),
                      ),
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
