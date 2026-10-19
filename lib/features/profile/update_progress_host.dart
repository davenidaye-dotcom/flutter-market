import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../config/theme/app_colors.dart';
import '../../shared/widgets/page_app_bar.dart';
import 'update_task.dart';

/// 屏幕正中的更新进度。普通更新只有中间一块，旁边照常能点；强制更新加整屏遮罩，返回键也关不掉。
class UpdateProgressHost extends StatefulWidget {
  const UpdateProgressHost({super.key});

  @override
  State<UpdateProgressHost> createState() => _UpdateProgressHostState();
}

class _UpdateProgressHostState extends State<UpdateProgressHost> {
  AppBackLayer? _backLayer;

  @override
  void initState() {
    super.initState();
    UpdateTask.instance.progress.addListener(_syncBack);
  }

  @override
  void dispose() {
    UpdateTask.instance.progress.removeListener(_syncBack);
    final layer = _backLayer;
    if (layer != null) unregisterAppBackLayer(layer);
    super.dispose();
  }

  void _syncBack() {
    final now = UpdateTask.instance.progress.value;
    final block = now.force && now.phase != UpdatePhase.idle;
    if (block && _backLayer == null) {
      final layer = AppBackLayer(() => true, overlay: true);
      _backLayer = layer;
      registerAppBackLayer(layer);
    } else if (!block && _backLayer != null) {
      unregisterAppBackLayer(_backLayer!);
      _backLayer = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<UpdateProgress>(
      valueListenable: UpdateTask.instance.progress,
      builder: (context, now, _) {
        if (now.phase == UpdatePhase.idle) return const SizedBox.shrink();
        final badge = Center(child: _Badge(progress: now));
        if (!now.force) return badge;
        return Stack(
          fit: StackFit.expand,
          children: [
            const ModalBarrier(dismissible: false, color: Colors.black38),
            badge,
          ],
        );
      },
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.progress});

  final UpdateProgress progress;

  String get _label {
    switch (progress.phase) {
      case UpdatePhase.downloading:
        final p = progress.percent;
        return p == null ? '下载中' : '$p%';
      case UpdatePhase.installing:
        return '安装中';
      case UpdatePhase.failed:
        return '重试';
      case UpdatePhase.needInstall:
        return '点此安装';
      case UpdatePhase.needPermission:
        return '去开启';
      case UpdatePhase.idle:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = 84.w;
    return Material(
      type: MaterialType.transparency,
      child: GestureDetector(
        onTap: UpdateTask.instance.tap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16.r),
            border: Border.all(color: AppColors.divider),
          ),
          alignment: Alignment.center,
          child: SizedBox(
            width: 60.w,
            height: 60.w,
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (progress.busy)
                  SizedBox.expand(
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      color: AppColors.primary,
                      backgroundColor: AppColors.divider,
                    ),
                  )
                else
                  SizedBox.expand(
                    child: CircularProgressIndicator(
                      value: 1,
                      strokeWidth: 3,
                      color: AppColors.divider,
                    ),
                  ),
                Text(
                  _label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12.sp,
                    fontWeight: FontWeight.w600,
                    color: progress.busy ? AppColors.textPrimary : AppColors.primary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
