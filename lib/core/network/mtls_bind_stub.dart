import 'package:dio/dio.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

Future<void> ensureMtlsMaterialLoaded() async {}

void bindMtlsClient(Dio dio, {required bool presentClientCert}) {}

Future<WebSocketChannel> connectFlyroomSocket(Uri uri) {
  return Future<WebSocketChannel>.value(WebSocketChannel.connect(uri));
}
