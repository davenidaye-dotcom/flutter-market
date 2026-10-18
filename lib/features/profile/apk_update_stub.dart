import 'package:dio/dio.dart';

Future<String> downloadReleaseApk(
  String url,
  void Function(int received, int total) onProgress,
  CancelToken cancel,
) async {
  throw UnsupportedError('当前平台不能下载安装包');
}

Future<String> startApkInstall(String path, String version) async => 'unsupported';

Stream<String> apkInstallEvents() => const Stream.empty();
