import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/network/mtls_bind_io.dart';

const _channel = MethodChannel('flyroom/update');
const _events = EventChannel('flyroom/update/status');

/// 下到应用缓存，再交给系统安装。返回本地路径。
Future<String> downloadReleaseApk(
  String url,
  void Function(int received, int total) onProgress,
  CancelToken cancel,
) async {
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/ruifeng-update.apk');
  if (await file.exists()) {
    await file.delete();
  }
  await downloadHttps(url, file.path, onProgress: onProgress, cancelToken: cancel);
  final head = await file.openRead(0, 2).fold<List<int>>(<int>[], (buf, chunk) {
    buf.addAll(chunk);
    return buf;
  });
  if (head.length < 2 || head[0] != 0x50 || head[1] != 0x4B) {
    await file.delete();
    throw const FormatException('二维码里不是安装包地址');
  }
  return file.path;
}

/// started：已交给系统。permission：去系统里允许安装未知应用。
Future<String> startApkInstall(String path, String version) async {
  if (!Platform.isAndroid) return 'unsupported';
  final result = await _channel.invokeMethod<String>('installApk', {
    'path': path,
    'version': version,
  });
  return result ?? 'fail';
}

Stream<String> apkInstallEvents() {
  return _events.receiveBroadcastStream().map((event) => '$event');
}
