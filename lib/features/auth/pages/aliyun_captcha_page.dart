import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../config/theme/app_colors.dart';

/// 登录页上的安全验证弹框。通过返回 captchaVerifyParam，取消返回 null。
class AliyunCaptchaPage extends StatefulWidget {
  const AliyunCaptchaPage({super.key});

  static OverlayEntry? _entry;
  static Completer<String?>? _wait;
  static WebViewController? _controller;
  static final GlobalKey _webKey = GlobalKey();
  static var _visible = false;
  static var _ready = false;
  static var _stage = 'start';
  static var _webHeight = _captchaRestHeight();
  static var _webWidth = 0.0;
  static String? _error;
  static var _loadGen = 0;

  /// 登录页打开时就把验证码页放进屏幕外，点登录时直接拖出来。
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
    _entry = null;
    _wait = null;
    _controller = null;
    _visible = false;
    _ready = false;
    _stage = 'start';
    _error = null;
    _webHeight = _captchaRestHeight();
    _webWidth = 0;
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
    if (entry != null && entry.mounted) {
      final existing = _wait;
      if (existing != null && !existing.isCompleted) return existing.future;
      _visible = true;
      entry.markNeedsBuild();
      final wait = Completer<String?>();
      _wait = wait;
      return wait.future;
    }
    return _openDialog(context);
  }

  static Future<String?> _openDialog(BuildContext context) {
    return showGeneralDialog<String>(
      context: context,
      barrierDismissible: true,
      barrierLabel: '安全验证',
      barrierColor: const Color(0x73000000),
      pageBuilder: (dialogContext, _, _) {
        final width = _captchaDialogWidth(MediaQuery.sizeOf(dialogContext).width);
        return Center(child: SizedBox(width: width, child: const AliyunCaptchaPage()));
      },
    );
  }

  static void _ensureController() {
    if (_controller != null) return;
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.transparent)
      ..addJavaScriptChannel(
        'AliyunCaptchaBridge',
        onMessageReceived: (message) => _onWarm(message.message),
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onWebResourceError: (error) {
            if (error.isForMainFrame != true) return;
            _error = '安全验证加载失败';
            _entry?.markNeedsBuild();
          },
        ),
      );
    _controller = controller;
    unawaited(_load(controller));
  }

  static Future<void> _load(WebViewController controller) async {
    final gen = ++_loadGen;
    final html = _fillCaptchaHtml(await rootBundle.loadString('assets/captcha/aliyun_captcha.html'));
    if (gen != _loadGen || !identical(_controller, controller)) return;
    await controller.loadHtmlString(html, baseUrl: 'https://o.alicdn.com/');
  }

  static void _onWarm(String raw) {
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return;
    }
    if (decoded is! Map) return;
    if (decoded['closed'] == true) {
      _finish(null);
      return;
    }
    if (decoded['ok'] == true) {
      if (!_visible) return;
      final param = decoded['param']?.toString() ?? '';
      if (param.isEmpty) return;
      _finish(param);
      return;
    }
    var changed = false;
    final stage = decoded['stage']?.toString();
    if (stage == 'puzzle' || stage == 'start') {
      if (_stage != stage) {
        _stage = stage!;
        changed = true;
      }
      if (stage == 'puzzle' && _error != null) {
        _error = null;
        changed = true;
      }
    }
    changed = _applyCaptchaSize(decoded, changed, 520);
    if (decoded['ready'] == true && !_ready) {
      _ready = true;
      changed = true;
    }
    final msg = decoded['msg']?.toString();
    if (msg != null && msg.isNotEmpty && _error != msg) {
      _error = msg;
      changed = true;
    }
    if (changed) _entry?.markNeedsBuild();
  }

  static void _finish(String? value) {
    if (!_visible) return;
    _visible = false;
    _ready = false;
    _stage = 'start';
    _error = null;
    _webHeight = _captchaRestHeight();
    _webWidth = 0;
    final wait = _wait;
    _wait = null;
    _entry?.markNeedsBuild();
    if (wait != null && !wait.isCompleted) wait.complete(value);
    final controller = _controller;
    if (controller != null) unawaited(_load(controller));
  }

  static Widget _buildOverlay(BuildContext context) {
    final controller = _controller;
    if (controller == null) return const SizedBox.shrink();
    final web = WebViewWidget(key: _webKey, controller: controller);
    final width = _captchaDialogWidth(MediaQuery.sizeOf(context).width);
    if (!_visible || (!_ready && _error == null)) {
      return Stack(
        children: [
          if (_visible)
            Positioned.fill(
              child: GestureDetector(
                onTap: () => _finish(null),
                child: const ColoredBox(color: Color(0x73000000)),
              ),
            ),
          Positioned(
            left: -1200,
            top: 0,
            width: width,
            height: 420,
            child: IgnorePointer(child: web),
          ),
          if (_visible) Center(child: _WaitingCard(onClose: () => _finish(null))),
        ],
      );
    }
    final maxH = MediaQuery.sizeOf(context).height * 0.78;
    final webHeight = _webHeight.clamp(48.0, maxH);
    if (_stage == 'puzzle') {
      return Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onTap: () => _finish(null),
              child: const ColoredBox(color: Color(0x73000000)),
            ),
          ),
          Center(
            child: SizedBox(width: _puzzleWidth(MediaQuery.sizeOf(context).width), height: webHeight, child: web),
          ),
        ],
      );
    }
    final barHeight = _webHeight.clamp(48.0, 72.0);
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            onTap: () => _finish(null),
            child: const ColoredBox(color: Color(0x73000000)),
          ),
        ),
        Center(
          child: Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            clipBehavior: Clip.antiAlias,
            child: SizedBox(
              width: width,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(0, 4, 0, 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      height: 44,
                      child: Row(
                        children: [
                          const SizedBox(width: 44),
                          const Expanded(
                            child: Text(
                              '安全验证',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: () => _finish(null),
                            icon: const Icon(Icons.close, size: 22, color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                        child: Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: AppColors.danger, fontSize: 14),
                        ),
                      ),
                    SizedBox(
                      height: barHeight,
                      child: ClipRect(
                        child: OverflowBox(
                          alignment: Alignment.topCenter,
                          minHeight: 420,
                          maxHeight: 420,
                          child: SizedBox(width: width, height: 420, child: web),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  State<AliyunCaptchaPage> createState() => _AliyunCaptchaPageState();
}

class _AliyunCaptchaPageState extends State<AliyunCaptchaPage> {
  late final WebViewController _controller;
  String? _error;
  var _ready = false;
  var _stage = 'start';
  var _finished = false;
  final _webHeight = _captchaRestHeight();

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.transparent)
      ..addJavaScriptChannel(
        'AliyunCaptchaBridge',
        onMessageReceived: (message) => _onBridge(message.message),
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onWebResourceError: (error) {
            if (error.isForMainFrame == true && mounted && !_finished) {
              setState(() => _error = '安全验证加载失败');
            }
          },
        ),
      );
    _load();
  }

  Future<void> _load() async {
    final html = _fillCaptchaHtml(await rootBundle.loadString('assets/captcha/aliyun_captcha.html'));
    if (!mounted || _finished) return;
    await _controller.loadHtmlString(html, baseUrl: 'https://o.alicdn.com/');
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
      _finished = true;
      Navigator.of(context).pop();
      return;
    }
    if (decoded['ok'] == true) {
      final param = decoded['param']?.toString() ?? '';
      if (param.isEmpty) return;
      _finished = true;
      Navigator.of(context).pop(param);
      return;
    }
    var changed = false;
    final stage = decoded['stage']?.toString();
    if (stage == 'puzzle' || stage == 'start') {
      if (_stage != stage) {
        _stage = stage!;
        changed = true;
      }
      if (stage == 'puzzle' && _error != null) {
        _error = null;
        changed = true;
      }
    }
    final maxH = MediaQuery.sizeOf(context).height * 0.78;
    changed = _applyCaptchaSize(decoded, changed, maxH);
    if (decoded['ready'] == true && !_ready) {
      _ready = true;
      changed = true;
    }
    final msg = decoded['msg']?.toString();
    if (msg != null && msg.isNotEmpty && _error != msg) {
      _error = msg;
      changed = true;
    }
    if (changed) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final width = _captchaDialogWidth(MediaQuery.sizeOf(context).width);
    if (_stage == 'puzzle') {
      final maxH = MediaQuery.sizeOf(context).height * 0.78;
      return SizedBox(
        width: _puzzleWidth(width),
        height: AliyunCaptchaPage._webHeight.clamp(120.0, maxH),
        child: WebViewWidget(controller: _controller),
      );
    }
    final barHeight = _webHeight.clamp(48.0, 72.0);
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: width,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(0, 4, 0, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: 44,
                child: Row(
                  children: [
                    const SizedBox(width: 44),
                    const Expanded(
                      child: Text(
                        '安全验证',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close, size: 22, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                  child: Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppColors.danger, fontSize: 14),
                  ),
                ),
              SizedBox(
                height: barHeight,
                child: ClipRect(
                  child: OverflowBox(
                    alignment: Alignment.topCenter,
                    minHeight: 420,
                    maxHeight: 420,
                    child: SizedBox(width: width, height: 420, child: WebViewWidget(controller: _controller)),
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

/// 两端都用滑块场景。样式交给阿里云脚本，这里不改颜色。
String _fillCaptchaHtml(String raw) {
  return raw
      .replaceAll('__SCENE_ID__', '1x1kohduf')
      .replaceAll('__CAPTCHA_REM__', '1')
      .replaceAll('__SLIDE_WIDTH__', _slideWidth().round().toString())
      .replaceAll('__PUZZLE_MODE__', 'false');
}

double _captchaDialogWidth(double screen) {
  final width = screen - 72;
  if (width < 240) return width;
  if (width > 300) return 300.0;
  return width;
}

double _captchaRestHeight() => 56.0;

double _puzzleWidth(double screen) {
  final maxW = screen - 16;
  final reported = AliyunCaptchaPage._webWidth;
  if (reported < 200) return maxW < 340 ? maxW : 340.0;
  if (reported > maxW) return maxW;
  return reported;
}

bool _applyCaptchaSize(Map decoded, bool changed, double maxH) {
  final height = decoded['height'];
  if (height is num) {
    final next = _captchaHeight(height, maxH);
    if (next != null && (next - AliyunCaptchaPage._webHeight).abs() > 2) {
      AliyunCaptchaPage._webHeight = next;
      changed = true;
    }
  }
  final width = decoded['width'];
  if (width is num && (width.toDouble() - AliyunCaptchaPage._webWidth).abs() > 2) {
    AliyunCaptchaPage._webWidth = width.toDouble();
    changed = true;
  }
  return changed;
}

double? _captchaHeight(num height, double maxH) {
  final next = height.toDouble();
  if (next < 40) return null;
  return next.clamp(80, maxH);
}

double _slideWidth() {
  final views = WidgetsBinding.instance.platformDispatcher.views;
  if (views.isEmpty) return 300;
  final view = views.first;
  final logical = view.physicalSize.width / view.devicePixelRatio;
  if (logical <= 0) return 300;
  return _captchaDialogWidth(logical);
}

class _WaitingCard extends StatelessWidget {
  const _WaitingCard({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final width = _captchaDialogWidth(MediaQuery.sizeOf(context).width);
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: width,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(0, 4, 0, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: 44,
                child: Row(
                  children: [
                    const SizedBox(width: 44),
                    const Expanded(
                      child: Text(
                        '安全验证',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                      ),
                    ),
                    IconButton(
                      onPressed: onClose,
                      icon: const Icon(Icons.close, size: 22, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              const _LoadingButton(),
            ],
          ),
        ),
      ),
    );
  }
}

class _LoadingButton extends StatelessWidget {
  const _LoadingButton();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
      ),
    );
  }
}
