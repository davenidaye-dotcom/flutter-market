import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';

import '../../shared/widgets/page_app_bar.dart';
import 'apk_update_stub.dart' if (dart.library.io) 'apk_update_io.dart';

enum UpdatePhase {
  idle,
  downloading,
  installing,

  /// 下载或安装失败，点图标重下。
  failed,

  /// 包已下好，安装页被取消，点图标直接装。
  needInstall,

  /// 要先在系统里允许安装未知应用。
  needPermission,
}

@immutable
class UpdateProgress {
  const UpdateProgress({
    this.phase = UpdatePhase.idle,
    this.received = 0,
    this.total = 0,
    this.force = false,
  });

  final UpdatePhase phase;
  final int received;
  final int total;
  final bool force;

  bool get busy => phase == UpdatePhase.downloading || phase == UpdatePhase.installing;

  int? get percent => total > 0 ? (received * 100 / total).round().clamp(0, 100) : null;
}

/// 安卓整包更新。弹框点「更新」后交给这里，弹框立刻关闭，进度由 [UpdateProgressHost] 显示。
/// 只有系统回报安装成功才调用 [onInstalled]，下载失败、取消安装都不换本机版本。
class UpdateTask with WidgetsBindingObserver {
  UpdateTask._();
  static final UpdateTask instance = UpdateTask._();

  final ValueNotifier<UpdateProgress> progress = ValueNotifier(const UpdateProgress());

  String _url = '';
  String _version = '';
  bool _force = false;
  String? _apkPath;
  CancelToken? _cancel;
  StreamSubscription<String>? _installSub;
  bool _observing = false;
  void Function(String version)? _onInstalled;

  void start({
    required String url,
    required String version,
    required bool force,
    required void Function(String version) onInstalled,
  }) {
    if (progress.value.busy) {
      AppToast.info('正在更新');
      return;
    }
    if (_url != url || _version != version) _apkPath = null;
    _url = url;
    _version = version;
    _force = force;
    _onInstalled = onInstalled;
    _installSub ??= apkInstallEvents().listen(_onInstallEvent);
    if (!_observing) {
      WidgetsBinding.instance.addObserver(this);
      _observing = true;
    }
    final apk = _apkPath;
    if (apk != null) {
      unawaited(_install(apk));
    } else {
      unawaited(_download());
    }
  }

  /// 点中间图标。
  void tap() {
    final now = progress.value;
    switch (now.phase) {
      case UpdatePhase.idle:
        return;
      case UpdatePhase.downloading:
        final p = now.percent;
        AppToast.info(p == null ? '正在下载' : '正在下载 $p%');
      case UpdatePhase.installing:
        AppToast.info('正在安装');
      case UpdatePhase.failed:
        _apkPath = null;
        unawaited(_download());
      case UpdatePhase.needInstall:
      case UpdatePhase.needPermission:
        final apk = _apkPath;
        if (apk == null) {
          unawaited(_download());
        } else {
          unawaited(_install(apk));
        }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    final apk = _apkPath;
    if (progress.value.phase != UpdatePhase.needPermission || apk == null) return;
    unawaited(_install(apk));
  }

  void _set(UpdatePhase phase, {int? received, int? total}) {
    final now = progress.value;
    progress.value = UpdateProgress(
      phase: phase,
      received: received ?? now.received,
      total: total ?? now.total,
      force: _force,
    );
  }

  Future<void> _download() async {
    _cancel?.cancel();
    final cancel = CancelToken();
    _cancel = cancel;
    _set(UpdatePhase.downloading, received: 0, total: 0);
    try {
      final path = await downloadReleaseApk(_url, (got, total) {
        if (cancel.isCancelled) return;
        _set(UpdatePhase.downloading, received: got, total: total);
      }, cancel);
      if (cancel.isCancelled) return;
      _apkPath = path;
      final total = progress.value.total;
      if (total > 0) _set(UpdatePhase.downloading, received: total);
      await _install(path);
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) return;
      _fail(_messageOf(e.error ?? e));
    } catch (e) {
      _fail(_messageOf(e));
    }
  }

  Future<void> _install(String path) async {
    _set(UpdatePhase.installing);
    try {
      final status = await startApkInstall(path, _version);
      if (status == 'permission') {
        _set(UpdatePhase.needPermission);
        AppToast.info('请允许安装未知应用');
        return;
      }
      if (status != 'started') {
        _set(UpdatePhase.needInstall);
        AppToast.error('无法安装');
      }
    } catch (_) {
      _set(UpdatePhase.needInstall);
      AppToast.error('无法安装');
    }
  }

  void _onInstallEvent(String kind) {
    if (progress.value.phase == UpdatePhase.idle) return;
    switch (kind) {
      case 'success':
        _onInstalled?.call(_version);
        _apkPath = null;
        progress.value = const UpdateProgress();
      case 'confirm':
        return;
      case 'cancel':
        _set(UpdatePhase.needInstall);
        AppToast.info('未完成安装');
      default:
        _apkPath = null;
        _fail('安装失败');
    }
  }

  void _fail(String message) {
    _set(UpdatePhase.failed);
    AppToast.error(message);
  }

  String _messageOf(Object error) {
    final text = error.toString();
    if (text.contains('二维码里不是下载地址')) return '二维码里不是下载地址';
    if (text.contains('二维码里不是安装包地址')) return '二维码里不是安装包地址';
    if (text.contains('VPN')) return '检测到 VPN 或代理，请关闭后重试';
    return '下载失败';
  }
}
