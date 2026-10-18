import 'dart:async';

import 'package:dio/dio.dart';
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
import 'apk_update_stub.dart' if (dart.library.io) 'apk_update_io.dart';

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

class _UpdateDialog extends StatefulWidget {
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

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> with WidgetsBindingObserver {
  int _received = 0;
  int _total = 0;
  bool _downloading = false;
  bool _installing = false;
  bool _waitPermission = false;
  bool _retriedPermission = false;
  String? _apkPath;
  CancelToken? _cancel;
  StreamSubscription<String>? _installSub;

  bool get _busy => _downloading || _installing;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.android) {
      _installSub = apkInstallEvents().listen(_onInstall);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cancel?.cancel();
    _installSub?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !_waitPermission || _apkPath == null) return;
    _waitPermission = false;
    _installFile(_apkPath!);
  }

  Future<void> _onUpdate() async {
    if (_busy) return;
    if (widget.android) {
      await _downloadThenInstall();
      return;
    }
    await _openDownloadPage();
  }

  Future<void> _openDownloadPage() async {
    final uri = Uri.tryParse(widget.updateUrl);
    final openable = uri != null && (uri.scheme == 'http' || uri.scheme == 'https');
    if (!openable) {
      AppToast.info('请通过分享二维码安装新版本');
      return;
    }
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok) {
      AppToast.error('无法打开下载页');
      return;
    }
    AppToast.info('已打开下载页，请点安装');
    if (!widget.force && mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _downloadThenInstall() async {
    final uri = Uri.tryParse(widget.updateUrl);
    if (uri == null || uri.scheme != 'https') {
      AppToast.info('安装包地址需要是 https');
      return;
    }
    final cancel = CancelToken();
    _cancel = cancel;
    setState(() {
      _downloading = true;
      _installing = false;
      _received = 0;
      _total = 0;
    });
    try {
      final path = await downloadReleaseApk(widget.updateUrl, (got, total) {
        if (!mounted || cancel.isCancelled) return;
        setState(() {
          _received = got;
          _total = total;
        });
      }, cancel);
      if (!mounted) return;
      _apkPath = path;
      setState(() {
        _downloading = false;
        _installing = true;
        if (_total > 0) _received = _total;
      });
      await _installFile(path);
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) return;
      _fail(_messageOf(e.error ?? e));
    } catch (e) {
      _fail(_messageOf(e));
    }
  }

  Future<void> _installFile(String path) async {
    setState(() => _installing = true);
    try {
      final status = await startApkInstall(path, AppRelease._stripV(widget.latestName));
      if (!mounted) return;
      if (status == 'permission') {
        if (_retriedPermission) {
          _fail('请允许安装未知应用');
          return;
        }
        _retriedPermission = true;
        _waitPermission = true;
        return;
      }
      if (status != 'started') {
        _fail('无法安装');
      }
    } catch (_) {
      _fail('无法安装');
    }
  }

  void _onInstall(String kind) {
    if (!mounted) return;
    if (kind == 'success') {
      AppRelease._adopt(widget.latestName);
      if (!widget.force) {
        Navigator.of(context).pop();
      } else {
        setState(() => _installing = false);
      }
      return;
    }
    if (kind == 'confirm') return;
    if (kind == 'cancel') {
      setState(() {
        _downloading = false;
        _installing = false;
      });
      AppToast.info('未完成安装');
      return;
    }
    _fail('安装失败');
  }

  void _fail(String message) {
    if (!mounted) return;
    setState(() {
      _downloading = false;
      _installing = false;
    });
    AppToast.error(message);
  }

  String _messageOf(Object error) {
    final text = error.toString();
    if (text.contains('安装包地址需要是 https')) return '安装包地址需要是 https';
    if (text.contains('二维码里不是安装包地址')) return '二维码里不是安装包地址';
    if (text.contains('VPN')) return '检测到 VPN 或代理，请关闭后重试';
    return '下载失败';
  }

  String _mb(int bytes) => (bytes / (1024 * 1024)).toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    final percent = _total > 0 ? (_received * 100 / _total).round().clamp(0, 100) : null;
    final button = _downloading
        ? '下载中'
        : _installing
            ? '正在安装'
            : '更新';
    return PopScope(
      canPop: !widget.force && !_busy,
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
                  if (!widget.force && !_busy)
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
                  Text(AppRelease.displayVersion(widget.latestName), style: TextStyle(fontSize: 22.sp, fontWeight: FontWeight.w600, color: AppColors.primary)),
                  SizedBox(height: 6.h),
                  Text('当前 ${AppRelease.displayVersion(widget.local)}', style: TextStyle(fontSize: 13.sp, color: AppColors.textSecondary)),
                  SizedBox(height: 10.h),
                  Text(widget.notes, style: TextStyle(fontSize: 14.sp, height: 1.4)),
                  if (_busy) ...[
                    SizedBox(height: 12.h),
                    Row(
                      children: [
                        Expanded(child: Text(_downloading ? '下载中' : '正在安装', style: TextStyle(fontSize: 13.sp, color: AppColors.textSecondary))),
                        if (percent != null) Text('$percent%', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600)),
                      ],
                    ),
                    SizedBox(height: 6.h),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4.r),
                      child: LinearProgressIndicator(
                        value: percent == null ? null : percent / 100,
                        minHeight: 8.h,
                        backgroundColor: AppColors.divider,
                        color: AppColors.primary,
                      ),
                    ),
                    if (_total > 0) ...[
                      SizedBox(height: 6.h),
                      Text('${_mb(_received)} MB / ${_mb(_total)} MB', style: TextStyle(fontSize: 12.sp, color: AppColors.textHint)),
                    ],
                  ],
                ],
              ),
            ),
            if (!widget.force && !_busy)
              Center(child: TextButton(onPressed: safeDialogPop(context), child: const Text('稍后')))
            else
              SizedBox(height: 12.h),
            Material(
              color: AppColors.primary,
              child: InkWell(
                onTap: _busy ? null : _onUpdate,
                child: SizedBox(
                  height: 48.h,
                  child: Center(child: Text(button, style: TextStyle(color: Colors.white, fontSize: 16.sp, fontWeight: FontWeight.w600))),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
