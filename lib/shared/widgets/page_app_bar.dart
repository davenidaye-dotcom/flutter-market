import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../config/theme/app_colors.dart';
import 'stable_screen_metrics.dart';

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

/// 安全返回：无栈可弹时不抛异常（避免闪退）。
/// 壳首页 / 系统返回请用 [appHandleBack]（app_back.dart）。
void appSafePop(BuildContext context) {
  FocusManager.instance.primaryFocus?.unfocus();
  SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
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

/// 系统返回要先处理的一层（后注册的在最上，先消费）。
/// 聊天浮层、壳盖层、审核弹窗都登记在这里，因为它们不在路由栈上。
class AppBackLayer {
  AppBackLayer(this.tryStep, {this.overlay = false, this.navigatorOf});

  /// 返回 true 表示这一下返回已经用掉。
  final bool Function() tryStep;

  /// 盖在壳上面（聊天、全屏盖层、弹窗）。页内下钻为 false，排在分支弹层之后。
  final bool overlay;

  /// 这一层挂在哪个 Navigator 上。盖层只处理自己栈里的页内层。
  final NavigatorState? Function()? navigatorOf;
}

/// 页面还在屏幕上：分支没被收起，且是所在 Navigator 的当前页。
bool appBackLayerActive(BuildContext context) {
  var visible = true;
  context.visitAncestorElements((el) {
    final widget = el.widget;
    if (widget is Offstage && widget.offstage) {
      visible = false;
      return false;
    }
    if (widget is TickerMode && !widget.enabled) {
      visible = false;
      return false;
    }
    return true;
  });
  if (!visible) return false;
  final route = ModalRoute.of(context);
  if (route != null && !route.isCurrent) return false;
  return true;
}

/// 栈顶是弹窗时弹掉它。普通页面留给页内层。
bool popNavigatorPopup(NavigatorState nav) {
  if (!nav.canPop()) return false;
  Route<dynamic>? top;
  nav.popUntil((route) {
    top = route;
    return true;
  });
  if (top is! PopupRoute) return false;
  nav.pop();
  return true;
}

final List<AppBackLayer> _appBackLayers = <AppBackLayer>[];

void registerAppBackLayer(AppBackLayer layer) {
  if (_appBackLayers.contains(layer)) return;
  _appBackLayers.add(layer);
}

void unregisterAppBackLayer(AppBackLayer layer) {
  _appBackLayers.remove(layer);
}

/// 从最上层开始尝试消费一次返回。
/// [overlay] 为 true 只试浮层，false 只试页内下钻，null 两种都试。
/// [onlyNavigator] 只试挂在这个 Navigator 上的页内层。
bool tryAppBackLayers({bool? overlay, NavigatorState? onlyNavigator}) {
  for (var i = _appBackLayers.length - 1; i >= 0; i--) {
    final layer = _appBackLayers[i];
    if (overlay != null && layer.overlay != overlay) continue;
    if (onlyNavigator != null) {
      final owner = layer.navigatorOf?.call();
      if (!identical(owner, onlyNavigator)) continue;
    }
    if (layer.tryStep()) return true;
  }
  return false;
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
class _ShellCover {
  _ShellCover(this.layer);

  OverlayEntry? entry;
  final AppBackLayer layer;
  bool closed = false;
}

final List<_ShellCover> _shellCovers = <_ShellCover>[];

void _safeRemoveOverlayEntry(OverlayEntry entry) {
  if (!entry.mounted) return;
  try {
    entry.remove();
  } catch (_) {
    // 键盘收起/热重载时可能已被拆除，忽略
  }
}

void dismissAllShellCovers() {
  final covers = List<_ShellCover>.from(_shellCovers);
  _shellCovers.clear();
  for (final cover in covers) {
    cover.closed = true;
    unregisterAppBackLayer(cover.layer);
    final entry = cover.entry;
    if (entry != null) _safeRemoveOverlayEntry(entry);
  }
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
  final navKey = GlobalKey<NavigatorState>();
  late OverlayEntry entry;
  late final _ShellCover cover;

  void close() {
    if (cover.closed) return;
    cover.closed = true;
    FocusManager.instance.primaryFocus?.unfocus();
    SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
    _shellCovers.remove(cover);
    // 等 IME 收起再拆。这段时间返回层仍占着，避免底下页面被连着退掉。
    Future<void>.delayed(const Duration(milliseconds: 80), () {
      unregisterAppBackLayer(cover.layer);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _safeRemoveOverlayEntry(entry);
      });
      WidgetsBinding.instance.scheduleFrame();
    });
  }

  bool tryStep() {
    if (cover.closed) return true;
    final nav = navKey.currentState;
    if (nav != null && popNavigatorPopup(nav)) return true;
    // 盖层里的附件栏、下钻先退，再弹子页，最后才关盖层。
    if (nav != null && tryAppBackLayers(overlay: false, onlyNavigator: nav)) {
      return true;
    }
    if (nav != null && nav.canPop()) {
      nav.pop();
      return true;
    }
    close();
    return true;
  }

  cover = _ShellCover(AppBackLayer(tryStep, overlay: true));
  entry = OverlayEntry(
    builder: (ctx) => StableScreenMetrics(
      child: Material(
        color: const Color(0xFFF5F5F5),
        child: AppToastScope(
          child: ShellCoverCloser(
            close: close,
            child: HeroControllerScope.none(
              child: Navigator(
                key: navKey,
                onGenerateRoute: (_) => MaterialPageRoute<void>(
                  builder: (_) => page,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  cover.entry = entry;
  _shellCovers.add(cover);
  registerAppBackLayer(cover.layer);
  overlay.insert(entry);
  return Future<void>.value();
}

/// 页面顶部标题栏（返回 + 靠左标题，距返回 8）
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
            if (onBack != null)
              SizedBox(
                width: 44.w,
                child: IconButton(
                  icon: Icon(Icons.arrow_back_ios, size: 18.sp, color: color),
                  onPressed: onBack,
                ),
              )
            else
              SizedBox(width: 8.w),
            SizedBox(width: 8.w),
            Expanded(
              child: Text(
                title,
                textAlign: TextAlign.left,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 17.sp,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ),
            if (trailing != null)
              Padding(
                padding: EdgeInsets.only(left: 8.w, right: 4.w),
                child: trailing,
              ),
          ],
        ),
      ),
    );
  }
}
