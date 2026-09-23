import 'package:easy_refresh/easy_refresh.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../config/theme/app_colors.dart';

/// 统一下拉刷新：下拉刷新 → 松开刷新 → 正在刷新 → 刷新成功（含默认箭头/转圈/对勾图标）
Header appRefreshHeader({
  Color? textColor,
  Color? iconColor,
  Duration processedDuration = const Duration(milliseconds: 600),
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
    textStyle: TextStyle(fontSize: 13.sp, color: color),
    iconTheme: IconThemeData(color: icon, size: 18.sp),
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
    textStyle: TextStyle(fontSize: 13.sp, color: color),
    iconTheme: IconThemeData(color: icon, size: 18.sp),
  );
}

/// 公共下拉刷新壳。内部用 [easy_refresh]，自带图标 + 中文状态文案。
///
/// ```dart
/// AppPullRefresh(
///   onRefresh: () async { await load(); },
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
  final Future<void> Function()? onLoad;
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
                await onLoad!();
                return IndicatorResult.success;
              } catch (_) {
                return IndicatorResult.fail;
              }
            },
      child: child,
    );
  }
}
