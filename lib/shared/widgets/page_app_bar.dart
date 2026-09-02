import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../config/theme/app_colors.dart';

/// 全局 Loading 提示。
/// 在 ShellCover / 聊天 Overlay 内走本地层（保证可见）；否则走 EasyLoading。
abstract final class AppToast {
  static final List<_AppToastLayer> _layers = <_AppToastLayer>[];

  static void _bind(_AppToastLayer layer) => _layers.add(layer);

  static void _unbind(_AppToastLayer layer) => _layers.remove(layer);

  static _AppToastLayer? get _top => _layers.isEmpty ? null : _layers.last;

  static void info(String msg) {
    final layer = _top;
    if (layer != null) {
      layer.show(msg);
      return;
    }
    EasyLoading.showToast(msg);
  }

  static void success(String msg) {
    final layer = _top;
    if (layer != null) {
      layer.show(msg);
      return;
    }
    EasyLoading.showSuccess(msg);
  }

  static void error(String msg) {
    final layer = _top;
    if (layer != null) {
      layer.show(msg);
      return;
    }
    EasyLoading.showError(msg);
  }
}

abstract class _AppToastLayer {
  void show(String msg);
}

/// 包在 Overlay 盖层里：AppToast 显示在本层最上方，关闭盖层时一起消失
class AppToastScope extends StatefulWidget {
  const AppToastScope({super.key, required this.child});

  final Widget child;

  @override
  State<AppToastScope> createState() => _AppToastScopeState();
}

class _AppToastScopeState extends State<AppToastScope> implements _AppToastLayer {
  String? _msg;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    AppToast._bind(this);
  }

  @override
  void dispose() {
    _timer?.cancel();
    AppToast._unbind(this);
    super.dispose();
  }

  @override
  void show(String msg) {
    if (!mounted) return;
    _timer?.cancel();
    setState(() => _msg = msg);
    _timer = Timer(const Duration(milliseconds: 1800), () {
      if (!mounted) return;
      setState(() => _msg = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(child: widget.child),
        if (_msg != null)
          Positioned.fill(
            child: IgnorePointer(
              child: Center(
                child: Material(
                  color: const Color(0xE6000000),
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 280),
                      child: Text(
                        _msg!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.3),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// 安全返回：无栈可弹时不抛异常（避免闪退）
void appSafePop(BuildContext context) {
  final nav = Navigator.of(context);
  if (nav.canPop()) {
    nav.pop();
    return;
  }
  final closer = ShellCoverCloser.maybeOf(context);
  if (closer != null) {
    closer.close();
    return;
  }
}

/// Overlay 全屏盖层的关闭句柄（不走 go_router / 根 Navigator，Shell 保活）
class ShellCoverCloser extends InheritedWidget {
  const ShellCoverCloser({
    super.key,
    required this.close,
    required super.child,
  });

  final VoidCallback close;

  static ShellCoverCloser? maybeOf(BuildContext context) {
    return context.getInheritedWidgetOfExactType<ShellCoverCloser>();
  }

  @override
  bool updateShouldNotify(ShellCoverCloser oldWidget) => close != oldWidget.close;
}

/// 全屏盖住底部 Tab：用 Overlay，禁止 go_router / 根 Navigator（二者会卸 Shell）
final List<OverlayEntry> _shellCoverEntries = <OverlayEntry>[];

void dismissAllShellCovers() {
  for (final e in List<OverlayEntry>.from(_shellCoverEntries)) {
    e.remove();
  }
  _shellCoverEntries.clear();
}

/// 压入当前 Navigator（聊天 Overlay / ShellCover 内栈），不另开 root Overlay
Future<T?> pushLocalPage<T>(BuildContext context, Widget page) {
  return Navigator.of(context).push<T>(
    MaterialPageRoute<T>(builder: (_) => page),
  );
}

/// 已在 ShellCover 内则压本地栈；否则开 Overlay 盖层（保活底部 Tab）
Future<void> pushHostPage(BuildContext context, Widget page) {
  if (ShellCoverCloser.maybeOf(context) != null) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => page),
    );
  }
  return pushShellCover(context, page);
}

Future<void> pushShellCover(BuildContext context, Widget page) {
  final overlay = Overlay.of(context, rootOverlay: true);
  late OverlayEntry entry;

  void close() {
    entry.remove();
    _shellCoverEntries.remove(entry);
  }

  entry = OverlayEntry(
    builder: (_) => Material(
      color: const Color(0xFFF5F5F5),
      child: AppToastScope(
        child: ShellCoverCloser(
          close: close,
          child: HeroControllerScope.none(
            child: Navigator(
              onGenerateRoute: (_) => MaterialPageRoute<void>(
                builder: (_) => page,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  _shellCoverEntries.add(entry);
  overlay.insert(entry);
  return Future<void>.value();
}

/// 页面顶部标题栏（返回 + 居中标题）
class PageAppBar extends StatelessWidget {
  const PageAppBar({
    super.key,
    required this.title,
    this.onBack,
    this.trailing,
    this.foregroundColor,
  });

  final String title;
  final VoidCallback? onBack;
  final Widget? trailing;
  final Color? foregroundColor;

  @override
  Widget build(BuildContext context) {
    final color = foregroundColor ?? AppColors.textPrimary;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 4.w, vertical: 4.h),
      child: SizedBox(
        height: 44.h,
        child: Row(
          children: [
            SizedBox(
              width: 44.w,
              child: onBack == null
                  ? null
                  : IconButton(
                      icon: Icon(Icons.arrow_back_ios, size: 18.sp, color: color),
                      onPressed: onBack,
                    ),
            ),
            Expanded(
              child: Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 17.sp,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ),
            SizedBox(width: 44.w, child: trailing),
          ],
        ),
      ),
    );
  }
}
