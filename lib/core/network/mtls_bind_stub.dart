import 'package:dio/dio.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

Future<void> ensureMtlsMaterialLoaded() async {}

Future<void> ensureMainland() async {}

Future<void> downloadPackage(
  String url,
  String savePath, {
  required void Function(int received, int total) onProgress,
  CancelToken? cancelToken,
}) async {
  throw UnsupportedError('当前平台不能下载安装包');
}

void bindMtlsClient(Dio dio, {required bool presentClientCert}) {}

void bindAuthClient(Dio dio) {}

Future<WebSocketChannel> connectFlyroomSocket(
  Uri uri, {
  Map<String, dynamic>? headers,
}) {
  return Future<WebSocketChannel>.value(WebSocketChannel.connect(uri));
}

Future<String> fetchEgressIp() {
  return Future<String>.error(UnsupportedError('当前平台不能查询出口IP'));
}
