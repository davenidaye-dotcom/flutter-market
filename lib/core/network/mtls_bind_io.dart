import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/services.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'client_cert_store.dart';

const _caAsset = 'assets/certs/flyroom_root_ca.crt';

List<int>? _caBytes;
Future<void>? _loading;

Future<void> ensureMtlsMaterialLoaded() {
  return _loading ??= _load();
}

Future<void> _load() async {
  try {
    final data = await rootBundle.load(_caAsset);
    _caBytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  } catch (_) {
    _caBytes = null;
  }
}

void bindMtlsClient(Dio dio, {required bool presentClientCert}) {
  dio.httpClientAdapter = IOHttpClientAdapter(
    createHttpClient: () => _httpClient(dio.options.baseUrl, presentClientCert),
  );
}

Future<WebSocketChannel> connectFlyroomSocket(Uri uri) async {
  await ensureMtlsMaterialLoaded();
  if (uri.scheme != 'wss') {
    return IOWebSocketChannel.connect(uri);
  }
  final client = _httpClient(uri.toString(), true);
  return IOWebSocketChannel.connect(uri, customClient: client);
}

HttpClient _httpClient(String url, bool presentClientCert) {
  final secure = url.startsWith('https://') || url.startsWith('wss://');
  if (!secure) return HttpClient();
  final context = SecurityContext(withTrustedRoots: false);
  final ca = _caBytes;
  if (ca != null && ca.isNotEmpty) {
    context.setTrustedCertificatesBytes(ca);
  }
  final store = ClientCertStore.instance;
  if (presentClientCert && store.hasCert) {
    context.useCertificateChainBytes(utf8.encode(store.certPem!));
    context.usePrivateKeyBytes(utf8.encode(store.keyPem!));
  }
  final client = HttpClient(context: context);
  client.findProxy = (_) => 'DIRECT';
  return client;
}
