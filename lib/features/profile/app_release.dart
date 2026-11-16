import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../config/env/env_config.dart';
import '../../config/theme/app_colors.dart';
import '../../core/network/api_client.dart';
import '../../shared/widgets/emulator_safe_dialog.dart';
import '../../shared/widgets/page_app_bar.dart';
import 'update_task.dart';

/// 检查版本只显示本机版本。分享二维码仍从 /app/qrcode 取。
class AppRelease {
  AppRelease._();

  static bool _coldDone = false;
  static bool _showing = false;
  static const _prefKey = 'builtin_app_version';

  /// 界面上的版本号。安装包内是 v1.0。安卓只有系统安装成功才写成发布版本。
  static final ValueNotifier<String> builtinVersion = ValueNotifier(EnvConfig.appVersion);
  static Future<String>? _localLoad;

  /// 走业务客户端取图：只信包内根证书。Image.network 用系统证书，连不上私有 CA 的 443。
  static Future<Uint8List?> _qrBytes(Map<String, dynamic> release) async {
    final rev = (release['qrRev'] ?? '').toString().trim();
    final query = <String>[
      'platform=$_platformName',
      if (rev.isNotEmpty) 'v=${Uri.encodeQueryComponent(rev)}',
    ];
    final path = '/app/qrcode?${query.join('&')}';
    try {
      return await ApiClient.instance.getBytes(path);
    } catch (_) {
      return null;
    }
  }

  /// 登录页、个人中心展示内置版本，不用后台发布版本。
  static Future<String> footerVersion() => localVersion();

  static Future<String> localVersion() {
    return _localLoad ??= _readLocal();
  }

  static Future<String> _readLocal() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = _stripV(prefs.getString(_prefKey) ?? '');
      final binary = EnvConfig.appVersion;
      if (saved.isNotEmpty && _cmp(binary, saved) <= 0) {
        builtinVersion.value = saved;
        return saved;
      }
      if (saved.isNotEmpty) {
        await prefs.remove(_prefKey);
      }
    } catch (_) {}
    builtinVersion.value = EnvConfig.appVersion;
    return EnvConfig.appVersion;
  }

  /// 冷启动不再请求已关闭的检查更新接口。
  static Future<void> promptOnColdStart(BuildContext context) async {
    if (_coldDone) return;
    _coldDone = true;
    await check(context, quiet: true);
  }

  static String get _platformName => defaultTargetPlatform == TargetPlatform.iOS ? 'IOS' : 'ANDROID';

  static Future<void> check(BuildContext context, {bool quiet = false}) async {
    if (_showing) return;
    if (UpdateTask.instance.progress.value.phase != UpdatePhase.idle) {
      if (!quiet) UpdateTask.instance.tap();
      return;
    }
    final local = await localVersion();
    if (!context.mounted || quiet) return;
    AppToast.info('已是最新版本 ${displayVersion(local)}');
  }

  static Future<void> share(BuildContext context) async {
    final version = await localVersion();
    if (!context.mounted) return;
    final qr = await _qrBytes(const {});
    if (!context.mounted) return;
    await showEmulatorSafeDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('分享App'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (version.isNotEmpty)
              Padding(
                padding: EdgeInsets.only(bottom: 8.h),
                child: Text('版本 $version', style: TextStyle(fontSize: 13.sp, color: AppColors.textSecondary)),
              ),
            if (qr == null)
              const Text('二维码加载失败')
            else
              Image.memory(
                qr,
                width: 220.w,
                height: 220.w,
                errorBuilder: (context, error, stack) => const Text('二维码加载失败'),
              ),
            SizedBox(height: 8.h),
            Text('扫码安装', style: TextStyle(fontSize: 12.sp, color: AppColors.textHint)),
          ],
        ),
        actions: [
          TextButton(onPressed: safeDialogPop(ctx), child: const Text('关闭')),
        ],
      ),
    );
  }

  /// 展示成 v1.0。已带 v 时不再加一个。
  static String displayVersion(String raw) {
    final s = _stripV(raw);
    if (s.isEmpty) return 'v${EnvConfig.appVersion}';
    return 'v$s';
  }

  static String _stripV(String raw) {
    var s = raw.trim();
    if (s.startsWith('v') || s.startsWith('V')) s = s.substring(1);
    return s;
  }

  static int _cmp(String a, String b) {
    final as = _parts(a);
    final bs = _parts(b);
    final n = as.length < bs.length ? as.length : bs.length;
    for (var i = 0; i < n; i++) {
      if (as[i] != bs[i]) return as[i].compareTo(bs[i]);
    }
    return as.length.compareTo(bs.length);
  }

  static List<int> _parts(String raw) {
    var s = raw.trim();
    if (s.startsWith('v') || s.startsWith('V')) s = s.substring(1);
    if (s.isEmpty) return const [0];
    return s.split('.').map((p) => int.tryParse(p.trim()) ?? 0).toList();
  }
}
