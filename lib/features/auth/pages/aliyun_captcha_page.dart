import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// 登录和注册共用的阿里云验证。通过返回 captchaVerifyParam，取消返回 null。
///
/// 网页只加载阿里的 JS。点登录或注册后铺满屏幕，再由代码点一次开始按钮。
/// 暗色遮罩和验证内容都由阿里的 popup 绘制。
class AliyunCaptchaPage extends StatefulWidget {
  const AliyunCaptchaPage({super.key});

  static OverlayEntry? _entry;
  static Completer<String?>? _wait;
  static WebViewController? _controller;
  static Timer? _showTimer;
  static var _session = 0;
  static var _showGen = 0;
  static var _loadGen = 0;
  static var _visible = false;
  static var _shown = false;
  static String? _notice;
  static String? _loadError;

  static final Set<Factory<OneSequenceGestureRecognizer>> _gestures = {
    Factory<OneSequenceGestureRecognizer>(() => EagerGestureRecognizer()),
  };

  static String? takeNotice() {
    final value = _notice;
    _notice = null;
    return value;
  }

  /// 登录页打开时把脚本放到屏幕外，点登录时再铺到屏幕上。
  static void prewarm(BuildContext context) {
    final current = _entry;
    if (current != null && current.mounted) return;
    if (current != null) {
      _entry = null;
      try {
        current.remove();
      } catch (_) {}
    }
    final overlay = Overlay.maybeOf(context);
    if (overlay == null) return;
    _ensureController();
    final entry = OverlayEntry(builder: _buildOverlay);
    _entry = entry;
    overlay.insert(entry);
  }

  static void release() {
    final entry = _entry;
    final wait = _wait;
    _showTimer?.cancel();
    _showTimer = null;
    _showGen++;
    _entry = null;
    _wait = null;
    _session++;
    _controller = null;
    _visible = false;
    _shown = false;
    _loadError = null;
    _notice = null;
    if (entry != null) {
      try {
        entry.remove();
      } catch (_) {}
    }
    if (wait != null && !wait.isCompleted) wait.complete(null);
  }

  static Future<String?> open(BuildContext context) {
    prewarm(context);
    final entry = _entry;
    if (entry == null || !entry.mounted) return _openDialog(context);
    if (_wait != null && !_wait!.isCompleted) {
      _notice = '已取消安全验证';
      _finish(null);
    }
    if (_loadError != null) {
      _loadError = null;
      _session++;
      _controller = null;
      _shown = false;
      _ensureController();
    }
    _visible = true;
    _notice = null;
    final wait = Completer<String?>();
    _wait = wait;
    entry.markNeedsBuild();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future<void>.delayed(const Duration(milliseconds: 60), () {
        if (!identical(_wait, wait) || !_visible) return;
        _armShow();
      });
    });
    return wait.future;
  }

  static Future<String?> _openDialog(BuildContext context) {
    return showGeneralDialog<String>(
      context: context,
      barrierDismissible: true,
      barrierLabel: '安全验证',
      barrierColor: const Color(0x73000000),
      pageBuilder: (_, _, _) => const AliyunCaptchaPage(),
    );
  }

  static void _armShow() {
    final gen = ++_showGen;
    _shown = false;
    _showTimer?.cancel();
    _pokeShow(gen);
    _showTimer = Timer(const Duration(seconds: 8), () {
      if (gen != _showGen || !_visible || _shown) return;
      _notice = '安全验证加载失败';
      _finish(null);
    });
  }

  static void _pokeShow(int gen) {
    if (gen != _showGen || !_visible) return;
    final controller = _controller;
    if (controller == null) return;
    unawaited(
      controller.runJavaScript('window.openByJs && window.openByJs()').catchError((Object _) {}),
    );
  }

  static void _ensureController() {
    if (_controller != null) return;
    final session = _session;
    final controller = WebViewController();
    _controller = controller;
    controller
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.transparent)
      ..addJavaScriptChannel(
        'AliyunCaptchaBridge',
        onMessageReceived: (message) {
          if (session != _session || !identical(_controller, controller)) return;
          _onWarm(message.message);
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onWebResourceError: (error) {
            if (error.isForMainFrame != true) return;
            _loadError = '安全验证加载失败';
            if (!_visible) return;
            _notice = _loadError;
            _finish(null);
          },
        ),
      );
    unawaited(_load(controller));
  }

  static Future<void> _load(WebViewController controller) async {
    final gen = ++_loadGen;
    final html = await rootBundle.loadString('assets/captcha/aliyun_captcha.html');
    if (gen != _loadGen || !identical(_controller, controller)) return;
    await controller.loadHtmlString(html, baseUrl: 'https://o.alicdn.com/');
    if (gen != _loadGen || !identical(_controller, controller) || !_visible) return;
    _pokeShow(_showGen);
  }

  static void _onWarm(String raw) {
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return;
    }
    if (decoded is! Map) return;
    if (decoded['shown'] == true) {
      _shown = true;
      _showTimer?.cancel();
    }
    if (decoded['closed'] == true) {
      final msg = decoded['msg']?.toString();
      if (!_visible) {
        if (msg != null && msg.isNotEmpty) _loadError = msg;
        return;
      }
      _notice = (msg != null && msg.isNotEmpty) ? msg : '已取消安全验证';
      _finish(null);
      return;
    }
    if (decoded['ok'] == true) {
      if (!_visible) return;
      final param = decoded['param']?.toString() ?? '';
      if (param.isEmpty) return;
      _notice = null;
      _finish(param);
    }
  }

  static void _finish(String? value) {
    if (!_visible) return;
    _showTimer?.cancel();
    _showGen++;
    _visible = false;
    _shown = false;
    final wait = _wait;
    _wait = null;
    // 滑过一次的验证不能再拖。丢掉这一页，下一回用新的。
    _session++;
    _controller = null;
    _entry?.markNeedsBuild();
    if (wait != null && !wait.isCompleted) wait.complete(value);
    final entry = _entry;
    if (entry != null && entry.mounted) {
      _ensureController();
      entry.markNeedsBuild();
    }
  }

  static Widget _buildOverlay(BuildContext context) {
    final controller = _controller;
    if (controller == null) return const SizedBox.shrink();
    final web = WebViewWidget(
      key: ValueKey(_session),
      controller: controller,
      gestureRecognizers: _gestures,
    );
    final size = MediaQuery.sizeOf(context);
    if (!_visible) {
      return Positioned(
        left: -size.width - 20,
        top: 0,
        width: size.width,
        height: size.height,
        child: web,
      );
    }
    return Positioned.fill(child: web);
  }

  @override
  State<AliyunCaptchaPage> createState() => _AliyunCaptchaPageState();
}

class _AliyunCaptchaPageState extends State<AliyunCaptchaPage> {
  late final WebViewController _controller;
  var _finished = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.transparent)
      ..addJavaScriptChannel(
        'AliyunCaptchaBridge',
        onMessageReceived: (message) => _onBridge(message.message),
      );
    _load();
  }

  Future<void> _load() async {
    final html = await rootBundle.loadString('assets/captcha/aliyun_captcha.html');
    if (!mounted || _finished) return;
    await _controller.loadHtmlString(html, baseUrl: 'https://o.alicdn.com/');
    if (!mounted || _finished) return;
    await _controller.runJavaScript('window.openByJs && window.openByJs()');
  }

  void _onBridge(String raw) {
    if (_finished || !mounted) return;
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return;
    }
    if (decoded is! Map) return;
    if (decoded['closed'] == true) {
      final msg = decoded['msg']?.toString();
      AliyunCaptchaPage._notice = (msg != null && msg.isNotEmpty) ? msg : '已取消安全验证';
      _finished = true;
      Navigator.of(context).pop();
      return;
    }
    if (decoded['ok'] == true) {
      final param = decoded['param']?.toString() ?? '';
      if (param.isEmpty) return;
      AliyunCaptchaPage._notice = null;
      _finished = true;
      Navigator.of(context).pop(param);
    }
  }

  @override
  Widget build(BuildContext context) {
    return WebViewWidget(
      controller: _controller,
      gestureRecognizers: AliyunCaptchaPage._gestures,
    );
  }
}
