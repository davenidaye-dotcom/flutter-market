import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config/env/env_config.dart';
import '../../config/theme/app_colors.dart';
import '../../core/network/api_client.dart';
import '../../shared/widgets/emulator_safe_dialog.dart';
import '../../shared/widgets/page_app_bar.dart';
import 'update_task.dart';

/// 检查版本、分享安装二维码。数据来自总后台当前发布。
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

  /// 安卓系统安装成功后，把发布版本写成本机版本。苹果打开下载页不算装完。
  static Future<void> _adopt(String published) async {
    final next = _stripV(published);
    if (next.isEmpty) return;
    builtinVersion.value = next;
    _localLoad = Future.value(next);
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

  static String get _platformName => defaultTargetPlatform == TargetPlatform.iOS ? 'IOS' : 'ANDROID';

  static bool get _isAndroid => defaultTargetPlatform == TargetPlatform.android;

  static Future<Map<String, dynamic>?> _load() async {
    final data = await ApiClient.instance.get('/app/release', query: {'platform': _platformName});
    if (data is! Map) return null;
    return Map<String, dynamic>.from(data);
  }

  static Future<void> check(BuildContext context, {bool quiet = false}) async {
    if (_showing) return;
    if (UpdateTask.instance.progress.value.phase != UpdatePhase.idle) {
      if (!quiet) UpdateTask.instance.tap();
      return;
    }
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
    // 安卓点「更新」后弹框关闭，下载进度在屏幕中间；系统回报安装成功才换本机版本。
    final force = level == 'FORCE';
    final updateUrl = (release['updateUrl'] ?? '').toString().trim();
    _showing = true;
    try {
      await showEmulatorSafeDialog<void>(
        context: context,
        barrierDismissible: !force,
        builder: (ctx) => _UpdateDialog(
          local: local,
          latestName: latestName,
          notes: notes.isEmpty ? '请更新到最新版本' : notes,
          force: force,
          updateUrl: updateUrl,
          android: _isAndroid,
        ),
      );
    } finally {
      _showing = false;
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
    final qr = await _qrBytes(release);
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

class _UpdateDialog extends StatelessWidget {
  const _UpdateDialog({
    required this.local,
    required this.latestName,
    required this.notes,
    required this.force,
    required this.updateUrl,
    required this.android,
  });

  final String local;
  final String latestName;
  final String notes;
  final bool force;
  final String updateUrl;
  final bool android;

  bool get _openable {
    final scheme = Uri.tryParse(updateUrl)?.scheme.toLowerCase();
    return scheme == 'http' || scheme == 'https';
  }

  Future<void> _onUpdate(BuildContext context) async {
    if (android) {
      if (!_openable) {
        AppToast.info('二维码里不是下载地址');
        return;
      }
      UpdateTask.instance.start(
        url: updateUrl,
        version: AppRelease._stripV(latestName),
        force: force,
        onInstalled: AppRelease._adopt,
      );
      Navigator.of(context).pop();
      return;
    }
    await _openDownloadPage(context);
  }

  Future<void> _openDownloadPage(BuildContext context) async {
    if (!_openable) {
      AppToast.info('请通过分享二维码安装新版本');
      return;
    }
    final ok = await launchUrl(Uri.parse(updateUrl), mode: LaunchMode.externalApplication);
    if (!ok) {
      AppToast.error('无法打开下载页');
      return;
    }
    AppToast.info('已打开下载页，请点安装');
    if (!force && context.mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
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
                      onPressed: safeDialogPop(context),
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
                  Text(AppRelease.displayVersion(latestName), style: TextStyle(fontSize: 22.sp, fontWeight: FontWeight.w600, color: AppColors.primary)),
                  SizedBox(height: 6.h),
                  Text('当前 ${AppRelease.displayVersion(local)}', style: TextStyle(fontSize: 13.sp, color: AppColors.textSecondary)),
                  SizedBox(height: 10.h),
                  Text(notes, style: TextStyle(fontSize: 14.sp, height: 1.4)),
                ],
              ),
            ),
            if (!force)
              Center(child: TextButton(onPressed: safeDialogPop(context), child: const Text('稍后')))
            else
              SizedBox(height: 12.h),
            Material(
              color: AppColors.primary,
              child: InkWell(
                onTap: () => _onUpdate(context),
                child: SizedBox(
                  height: 48.h,
                  child: Center(child: Text('更新', style: TextStyle(color: Colors.white, fontSize: 16.sp, fontWeight: FontWeight.w600))),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
