import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config/env/env_config.dart';
import '../../config/theme/app_colors.dart';
import '../../core/network/api_client.dart';
import '../../shared/widgets/emulator_safe_dialog.dart';
import '../../shared/widgets/page_app_bar.dart';

/// 检查版本、分享安装包。数据来自总后台当前发布。
class AppRelease {
  AppRelease._();

  static String get _apkUrl => '${EnvConfig.apiBaseUrl}/app/apk';
  static String get _qrUrl => '${EnvConfig.apiBaseUrl}/app/qrcode';

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

  static Future<Map<String, dynamic>?> _load() async {
    final data = await ApiClient.instance.get('/app/release');
    if (data is! Map) return null;
    return Map<String, dynamic>.from(data);
  }

  static Future<void> check(BuildContext context) async {
    Map<String, dynamic>? release;
    try {
      release = await _load();
    } catch (e) {
      AppToast.error(e.toString());
      return;
    }
    if (!context.mounted) return;
    if (release == null || release['published'] != true) {
      AppToast.info('已是最新版本 ${EnvConfig.appVersion}');
      return;
    }
    final latestName = (release['version'] ?? '').toString();
    final latestCode = _int(release['versionCode']);
    final minName = (release['minVersion'] ?? '').toString().trim();
    final level = (release['updateLevel'] ?? '').toString().toUpperCase();
    final notes = (release['notes'] ?? '').toString().trim();
    final belowLatest = latestCode > 0
        ? EnvConfig.appVersionCode < latestCode
        : _cmp(EnvConfig.appVersion, latestName) < 0;
    if (!belowLatest) {
      AppToast.info('已是最新版本 ${EnvConfig.appVersion}');
      return;
    }
    final belowMin = minName.isNotEmpty && _cmp(EnvConfig.appVersion, minName) < 0;
    final force = belowMin || level == 'FORCE';
    final hasPackage = release['hasPackage'] == true;
    await showEmulatorSafeDialog<void>(
      context: context,
      barrierDismissible: !force,
      builder: (ctx) => PopScope(
        canPop: !force,
        child: AlertDialog(
          title: Text('发现新版本 $latestName'),
          content: Text(notes.isEmpty ? '请更新到最新版本' : notes),
          actions: [
            if (!force)
              TextButton(onPressed: safeDialogPop(ctx), child: const Text('稍后')),
            TextButton(
              onPressed: () async {
                if (!hasPackage) {
                  AppToast.info('暂无安装包');
                  return;
                }
                await _openApk();
              },
              child: const Text('下载'),
            ),
          ],
        ),
      ),
    );
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
              _qrUrl,
              width: 220.w,
              height: 220.w,
              errorBuilder: (context, error, stack) => const Text('二维码加载失败'),
            ),
            SizedBox(height: 8.h),
            Text('扫码下载安装包', style: TextStyle(fontSize: 12.sp, color: AppColors.textHint)),
          ],
        ),
        actions: [
          TextButton(onPressed: safeDialogPop(ctx), child: const Text('关闭')),
        ],
      ),
    );
  }

  static Future<void> _openApk() async {
    final uri = Uri.parse(_apkUrl);
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok) {
      AppToast.error('无法打开下载');
    }
  }

  static int _int(dynamic v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;

  static int _cmp(String a, String b) {
    final as = a.split('.');
    final bs = b.split('.');
    final n = as.length > bs.length ? as.length : bs.length;
    for (var i = 0; i < n; i++) {
      final ai = i < as.length ? int.tryParse(as[i]) ?? 0 : 0;
      final bi = i < bs.length ? int.tryParse(bs[i]) ?? 0 : 0;
      if (ai != bi) return ai.compareTo(bi);
    }
    return 0;
  }
}
