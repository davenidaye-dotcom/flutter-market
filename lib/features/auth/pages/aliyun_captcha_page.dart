import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../config/theme/app_colors.dart';

/// 登录页上的安全验证弹框。通过返回 captchaVerifyParam，取消返回 null。
class AliyunCaptchaPage extends StatefulWidget {
  const AliyunCaptchaPage({super.key});

  static Future<String?> open(BuildContext context) {
    return showGeneralDialog<String>(
      context: context,
      barrierDismissible: true,
      barrierLabel: '安全验证',
      barrierColor: const Color(0x73000000),
      pageBuilder: (dialogContext, _, _) {
        final screen = MediaQuery.sizeOf(dialogContext).width;
        final width = screen < 300 ? screen - 32 : 280.0;
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

  @override
  State<AliyunCaptchaPage> createState() => _AliyunCaptchaPageState();
}

class _AliyunCaptchaPageState extends State<AliyunCaptchaPage> {
  late final WebViewController _controller;
  String? _error;
  var _ready = false;
  var _finished = false;
  var _webHeight = 56.0;

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
    final html = await rootBundle.loadString('assets/captcha/aliyun_captcha.html');
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
    final maxH = MediaQuery.sizeOf(context).height * 0.62;
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
