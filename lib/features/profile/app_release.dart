import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config/env/env_config.dart';
import '../../config/theme/app_colors.dart';
import '../../core/network/api_client.dart';
import '../../shared/widgets/emulator_safe_dialog.dart';
import '../../shared/widgets/page_app_bar.dart';

/// 检查版本、分享安装二维码。数据来自总后台当前发布。
class AppRelease {
  AppRelease._();

  static bool _coldDone = false;
  static bool _showing = false;

  static String _qrUrlOf(Map<String, dynamic> release) {
    final rev = (release['qrRev'] ?? '').toString().trim();
    final base = '${EnvConfig.apiBaseUrl}/app/qrcode';
    return rev.isEmpty ? base : '$base?v=$rev';
  }

  /// 登录页展示用。有当前发布就用发布版本号，否则用本机版本。
  static Future<String> footerVersion() async {
    try {
      final release = await _load();
      final name = (release?['version'] ?? '').toString().trim();
      if (release != null && release['published'] == true && name.isNotEmpty) {
        return name;
      }
    } catch (_) {}
    return EnvConfig.appVersion;
  }

  /// 冷启动提醒一次。已是最新或拉取失败都不弹 Toast。
  static Future<void> promptOnColdStart(BuildContext context) async {
    if (_coldDone) return;
    _coldDone = true;
    await check(context, quiet: true);
  }

  static Future<Map<String, dynamic>?> _load() async {
    final data = await ApiClient.instance.get('/app/release');
    if (data is! Map) return null;
    return Map<String, dynamic>.from(data);
  }

  static Future<void> check(BuildContext context, {bool quiet = false}) async {
    if (_showing) return;
    Map<String, dynamic>? release;
    try {
      release = await _load();
    } catch (e) {
      if (!quiet) AppToast.error(e.toString());
      return;
    }
    if (!context.mounted) return;
    if (release == null || release['published'] != true) {
      if (!quiet) AppToast.info('已是最新版本 ${displayVersion(EnvConfig.appVersion)}');
      return;
    }
    final latestName = (release['version'] ?? '').toString();
    final minName = (release['minVersion'] ?? '').toString().trim();
    final level = (release['updateLevel'] ?? '').toString().toUpperCase();
    final notes = (release['notes'] ?? '').toString().trim();
    final belowLatest = _cmp(EnvConfig.appVersion, latestName) < 0;
    if (!belowLatest) {
      if (!quiet) AppToast.info('已是最新版本 ${displayVersion(EnvConfig.appVersion)}');
      return;
    }
    final belowMin = minName.isNotEmpty && _cmp(EnvConfig.appVersion, minName) < 0;
    final force = belowMin || level == 'FORCE';
    final updateUrl = (release['updateUrl'] ?? '').toString().trim();
    _showing = true;
    try {
      await showEmulatorSafeDialog<void>(
        context: context,
        barrierDismissible: !force,
        builder: (ctx) => PopScope(
          canPop: !force,
          child: AlertDialog(
            title: Row(
              children: [
                Expanded(child: Text('发现新版本 $latestName')),
                if (!force)
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    onPressed: safeDialogPop(ctx),
                    icon: const Icon(Icons.close),
                  ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('当前 ${displayVersion(EnvConfig.appVersion)}', style: TextStyle(fontSize: 13.sp, color: AppColors.textSecondary)),
                SizedBox(height: 8.h),
                Text(notes.isEmpty ? '请更新到最新版本' : notes),
              ],
            ),
            actions: [
              if (!force)
                TextButton(onPressed: safeDialogPop(ctx), child: const Text('稍后')),
              TextButton(
                onPressed: () => _applyUpdate(ctx, updateUrl, force),
                child: const Text('更新'),
              ),
            ],
          ),
        ),
      );
    } finally {
      _showing = false;
    }
  }

  static Future<void> _applyUpdate(BuildContext dialogContext, String updateUrl, bool force) async {
    final uri = Uri.tryParse(updateUrl);
    final openable = uri != null && (uri.scheme == 'http' || uri.scheme == 'https');
    if (!openable) {
      AppToast.info('请通过分享二维码安装新版本');
      return;
    }
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok) {
      AppToast.error('无法打开更新');
      return;
    }
    if (!force && dialogContext.mounted) {
      Navigator.of(dialogContext).pop();
    }
  }

  static Future<void> share(BuildContext context) async {
    Map<String, dynamic>? release;
    try {
      release = await _load();
    } catch (e) {
      AppToast.error(e.toString());
      return;
    }
    if (!context.mounted) return;
    if (release == null || release['hasQr'] != true) {
      AppToast.info('暂未上传分享二维码');
      return;
    }
    final version = (release['version'] ?? '').toString();
    final qrUrl = _qrUrlOf(release);
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
            Image.network(
              qrUrl,
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
    final s = raw.trim();
    if (s.isEmpty) return 'v${EnvConfig.appVersion}';
    if (s.startsWith('v') || s.startsWith('V')) return 'v${s.substring(1)}';
    return 'v$s';
  }

  /// 从左到右比数字段。前面相同则段更多的更大：1.1 > 1.0，1.100.1 > 1.100，1.100.2 > 1.100.1。
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
