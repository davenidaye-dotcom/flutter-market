import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
  static const _prefKey = 'builtin_app_version';

  /// 界面上的版本号。安装包内是 v1.0，点更新打开地址成功后才写成发布版本。
  static final ValueNotifier<String> builtinVersion = ValueNotifier(EnvConfig.appVersion);
  static Future<String>? _localLoad;

  static String _qrUrlOf(Map<String, dynamic> release) {
    final rev = (release['qrRev'] ?? '').toString().trim();
    final base = '${EnvConfig.apiBaseUrl}/app/qrcode';
    return rev.isEmpty ? base : '$base?v=$rev';
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
      if (saved.isNotEmpty) {
        builtinVersion.value = saved;
        return saved;
      }
    } catch (_) {}
    builtinVersion.value = EnvConfig.appVersion;
    return EnvConfig.appVersion;
  }

  /// 更新地址打开成功后，把发布版本写成本机版本。
  static Future<void> _adopt(String published) async {
    final next = _stripV(published);
    if (next.isEmpty) return;
    builtinVersion.value = next;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKey, next);
    } catch (_) {}
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
    final local = await localVersion();
    if (!context.mounted) return;
    if (release == null || release['published'] != true) {
      if (!quiet) AppToast.info('已是最新版本 ${displayVersion(local)}');
      return;
    }
    final latestName = (release['version'] ?? '').toString();
    final level = (release['updateLevel'] ?? '').toString().toUpperCase();
    final notes = (release['notes'] ?? '').toString().trim();
    final belowLatest = _cmp(local, latestName) < 0;
    if (!belowLatest) {
      if (!quiet) AppToast.info('已是最新版本 ${displayVersion(local)}');
      return;
    }
    // 新包内置 v1.0。发布版本更高时弹出；普通可以关掉，只有后台选强制才不能关。
    final force = level == 'FORCE';
    final updateUrl = (release['updateUrl'] ?? '').toString().trim();
    _showing = true;
    try {
      await showEmulatorSafeDialog<void>(
        context: context,
        barrierDismissible: !force,
        builder: (ctx) => PopScope(
          canPop: !force,
          child: Dialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.r)),
            clipBehavior: Clip.antiAlias,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(16.w, 14.h, 4.w, 0),
                  child: Row(
                    children: [
                      Expanded(child: Text('发现新版本', style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.w600))),
                      if (!force)
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          onPressed: safeDialogPop(ctx),
                          icon: const Icon(Icons.close),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 4.h),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(displayVersion(latestName), style: TextStyle(fontSize: 22.sp, fontWeight: FontWeight.w600, color: AppColors.primary)),
                      SizedBox(height: 6.h),
                      Text('当前 ${displayVersion(local)}', style: TextStyle(fontSize: 13.sp, color: AppColors.textSecondary)),
                      SizedBox(height: 10.h),
                      Text(notes.isEmpty ? '请更新到最新版本' : notes, style: TextStyle(fontSize: 14.sp, height: 1.4)),
                    ],
                  ),
                ),
                if (!force)
                  Center(
                    child: TextButton(onPressed: safeDialogPop(ctx), child: const Text('稍后')),
                  )
                else
                  SizedBox(height: 12.h),
                Material(
                  color: AppColors.primary,
                  child: InkWell(
                    onTap: () => _applyUpdate(ctx, updateUrl, force, latestName),
                    child: SizedBox(
                      height: 48.h,
                      child: Center(child: Text('更新', style: TextStyle(color: Colors.white, fontSize: 16.sp, fontWeight: FontWeight.w600))),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    } finally {
      _showing = false;
    }
  }

  static Future<void> _applyUpdate(BuildContext dialogContext, String updateUrl, bool force, String latestName) async {
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
    await _adopt(latestName);
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
    final s = _stripV(raw);
    if (s.isEmpty) return 'v${EnvConfig.appVersion}';
    return 'v$s';
  }

  static String _stripV(String raw) {
    var s = raw.trim();
    if (s.startsWith('v') || s.startsWith('V')) s = s.substring(1);
    return s;
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
