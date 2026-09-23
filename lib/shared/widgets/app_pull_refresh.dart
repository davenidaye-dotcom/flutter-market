import 'dart:math' as math;

import 'package:easy_refresh/easy_refresh.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../config/theme/app_colors.dart';

Widget _refreshPullIcon(
  BuildContext context,
  IndicatorState state,
  double animation, {
  required bool forFooter,
  required Color color,
}) {
  final size = 12.sp;
  if (state.mode == IndicatorMode.processing ||
      state.mode == IndicatorMode.ready) {
    return SizedBox(
      width: size,
      height: size,
      child: CircularProgressIndicator(
        strokeWidth: 1.4,
        color: color,
      ),
    );
  }
  if (state.result == IndicatorResult.success) {
    return Icon(Icons.check_rounded, size: size, color: const Color(0xFF43A047));
  }
  if (state.result == IndicatorResult.fail) {
    return Icon(Icons.close_rounded, size: size, color: AppColors.danger);
  }
  if (state.result == IndicatorResult.noMore) {
    return Icon(Icons.remove_rounded, size: size, color: color);
  }
  // 拖拽/待触发：小箭头随拉动旋转
  final turn = forFooter ? 1.0 - animation : animation;
  return Transform.rotate(
    angle: turn * math.pi,
    child: Icon(
      forFooter ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
      size: size,
      color: color,
    ),
  );
}

/// 统一下拉刷新：下拉刷新 → 松开刷新 → 正在刷新 → 刷新成功
Header appRefreshHeader({
  Color? textColor,
  Color? iconColor,
  Duration processedDuration = const Duration(milliseconds: 500),
}) {
  final color = textColor ?? AppColors.textSecondary;
  final icon = iconColor ?? AppColors.textSecondary;
  return ClassicHeader(
    dragText: '下拉刷新',
    armedText: '松开刷新',
    readyText: '正在刷新',
    processingText: '正在刷新',
    processedText: '刷新成功',
    failedText: '刷新失败',
    noMoreText: '没有更多了',
    showMessage: false,
    processedDuration: processedDuration,
    triggerOffset: 48,
    iconDimension: 16,
    spacing: 4,
    progressIndicatorSize: 12,
    progressIndicatorStrokeWidth: 1.4,
    textStyle: TextStyle(fontSize: 11.sp, color: color, height: 1.1),
    iconTheme: IconThemeData(color: icon, size: 12.sp),
    succeededIcon: Icon(Icons.check_rounded, size: 12.sp, color: const Color(0xFF43A047)),
    failedIcon: Icon(Icons.close_rounded, size: 12.sp, color: AppColors.danger),
    noMoreIcon: Icon(Icons.remove_rounded, size: 12.sp, color: color),
    pullIconBuilder: (context, state, animation) =>
        _refreshPullIcon(context, state, animation, forFooter: false, color: icon),
  );
}

/// 统一上拉加载文案（可选）
Footer appLoadFooter({
  Color? textColor,
  Color? iconColor,
}) {
  final color = textColor ?? AppColors.textSecondary;
  final icon = iconColor ?? AppColors.textSecondary;
  return ClassicFooter(
    dragText: '上拉加载',
    armedText: '松开加载',
    readyText: '正在加载',
    processingText: '正在加载',
    processedText: '加载成功',
    failedText: '加载失败',
    noMoreText: '没有更多了',
    showMessage: false,
    triggerOffset: 48,
    iconDimension: 16,
    spacing: 4,
    progressIndicatorSize: 12,
    progressIndicatorStrokeWidth: 1.4,
    textStyle: TextStyle(fontSize: 11.sp, color: color, height: 1.1),
    iconTheme: IconThemeData(color: icon, size: 12.sp),
    succeededIcon: Icon(Icons.check_rounded, size: 12.sp, color: const Color(0xFF43A047)),
    failedIcon: Icon(Icons.close_rounded, size: 12.sp, color: AppColors.danger),
    noMoreIcon: Icon(Icons.remove_rounded, size: 12.sp, color: color),
    pullIconBuilder: (context, state, animation) =>
        _refreshPullIcon(context, state, animation, forFooter: true, color: icon),
  );
}

/// 公共下拉刷新壳。内部用 [easy_refresh]，自带图标 + 中文状态文案。
///
/// ```dart
/// AppPullRefresh(
///   onRefresh: () async { await load(); },
///   onLoad: () async => hasMore, // false → 没有更多了
///   child: ListView(...),
/// )
/// ```
class AppPullRefresh extends StatelessWidget {
  const AppPullRefresh({
    super.key,
    required this.onRefresh,
    required this.child,
    this.onLoad,
    this.controller,
    this.header,
    this.footer,
    this.refreshOnStart = false,
  });

  final Future<void> Function() onRefresh;
  /// 返回 `false` 表示没有更多，页脚显示「没有更多了」。
  final Future<bool> Function()? onLoad;
  final Widget child;
  final EasyRefreshController? controller;
  final Header? header;
  final Footer? footer;
  final bool refreshOnStart;

  @override
  Widget build(BuildContext context) {
    return EasyRefresh(
      controller: controller,
      header: header ?? appRefreshHeader(),
      footer: onLoad == null ? null : (footer ?? appLoadFooter()),
      refreshOnStart: refreshOnStart,
      onRefresh: () async {
        try {
          await onRefresh();
          return IndicatorResult.success;
        } catch (_) {
          return IndicatorResult.fail;
        }
      },
      onLoad: onLoad == null
          ? null
          : () async {
              try {
                final hasMore = await onLoad!();
                return hasMore ? IndicatorResult.success : IndicatorResult.noMore;
              } catch (_) {
                return IndicatorResult.fail;
              }
            },
      child: child,
    );
  }
}
