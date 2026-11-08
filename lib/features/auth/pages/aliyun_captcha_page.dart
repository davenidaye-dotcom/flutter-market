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
  static var _webHeight = _captchaRestHeight();
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
    _error = null;
    _webHeight = _captchaRestHeight();
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
        return Center(
          child: Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            clipBehavior: Clip.antiAlias,
            child: SizedBox(width: width, child: const AliyunCaptchaPage()),
          ),
        );
      },
    );
  }

  static void _ensureController() {
    if (_controller != null) return;
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
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
    if (decoded['ok'] == true) {
      if (!_visible) return;
      final param = decoded['param']?.toString() ?? '';
      if (param.isEmpty) return;
      _finish(param);
      return;
    }
    var changed = false;
    final height = decoded['height'];
    if (height is num) {
      final next = height.toDouble().clamp(48.0, 520.0);
      if ((next - _webHeight).abs() > 2) {
        _webHeight = next;
        changed = true;
      }
    }
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
    _error = null;
    _webHeight = _captchaRestHeight();
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
    if (!_visible) {
      return Positioned(
        left: -1200,
        top: 0,
        width: _androidPuzzle ? 360.0 : 280.0,
        height: _androidPuzzle ? 420.0 : 80.0,
        child: IgnorePointer(child: web),
      );
    }
    final width = _captchaDialogWidth(MediaQuery.sizeOf(context).width);
    final maxH = MediaQuery.sizeOf(context).height * (_androidPuzzle ? 0.78 : 0.62);
    final webHeight = _webHeight.clamp(48.0, maxH);
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
                padding: const EdgeInsets.fromLTRB(0, 4, 0, 16),
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
                    if (!_androidPuzzle)
                      const Padding(
                        padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
                        child: Text(
                          '拖到最右边完成验证',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
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
                      height: webHeight,
                      child: Stack(
                        children: [
                          web,
                          if (!_ready && _error == null)
                            const ColoredBox(
                              color: Colors.white,
                              child: _LoadingButton(),
                            ),
                        ],
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
  var _finished = false;
  var _webHeight = _captchaRestHeight();

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
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
    if (decoded['ok'] == true) {
      final param = decoded['param']?.toString() ?? '';
      if (param.isEmpty) return;
      _finished = true;
      Navigator.of(context).pop(param);
      return;
    }
    final maxH = MediaQuery.sizeOf(context).height * (_androidPuzzle ? 0.78 : 0.62);
    var changed = false;
    final height = decoded['height'];
    if (height is num) {
      final next = height.toDouble().clamp(48.0, maxH);
      if ((next - _webHeight).abs() > 2) {
        _webHeight = next;
        changed = true;
      }
    }
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 16),
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
          if (!_androidPuzzle)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Text(
                '拖到最右边完成验证',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
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
            height: _webHeight,
            child: Stack(
              children: [
                WebViewWidget(controller: _controller),
                if (!_ready && _error == null)
                  const ColoredBox(
                    color: Colors.white,
                    child: _LoadingButton(),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

bool get _androidPuzzle => defaultTargetPlatform == TargetPlatform.android;

/// 安卓拼图用新场景，iOS 滑块继续用原来的场景。
String _fillCaptchaHtml(String raw) {
  final puzzle = _androidPuzzle;
  final rem = puzzle ? _puzzleRem().toStringAsFixed(3) : '0.75';
  final scene = puzzle ? 'n5qc0nf5c' : '1x1kohduf';
  return raw.replaceAll('__SCENE_ID__', scene).replaceAll('__CAPTCHA_REM__', rem);
}

double _captchaDialogWidth(double screen) {
  if (!_androidPuzzle) {
    return screen < 300 ? screen - 32 : 280.0;
  }
  final width = screen - 32;
  if (width < 260) return width;
  if (width > 360) return 360.0;
  return width;
}

double _captchaRestHeight() => _androidPuzzle ? 320.0 : 56.0;

double _puzzleRem() {
  final views = WidgetsBinding.instance.platformDispatcher.views;
  if (views.isEmpty) return 1;
  final view = views.first;
  final logical = view.physicalSize.width / view.devicePixelRatio;
  if (logical <= 0) return 1;
  final inner = _captchaDialogWidth(logical) - 16;
  final rem = inner / 320;
  if (rem > 1) return 1;
  if (rem < 0.8) return 0.8;
  return rem;
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
