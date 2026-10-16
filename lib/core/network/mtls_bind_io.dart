import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

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
  final old = dio.httpClientAdapter;
  dio.httpClientAdapter = _TlsOnlyAdapter(
    IOHttpClientAdapter(
      createHttpClient: () => _httpClient(presentClientCert),
    ),
  );
  old.close();
}

Future<WebSocketChannel> connectFlyroomSocket(Uri uri) async {
  if (uri.scheme.toLowerCase() != 'wss') {
    throw const TlsException('refuse cleartext websocket');
  }
  await ensureMtlsMaterialLoaded();
  final channel = IOWebSocketChannel.connect(
    uri,
    customClient: _httpClient(true),
  );
  await channel.ready;
  return channel;
}

/// 只信包内根证书，不信系统和用户装的证书（含抓包软件的根证书），不走系统代理。
HttpClient _httpClient(bool presentClientCert) {
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
  client.badCertificateCallback = (_, _, _) => false;
  return client;
}

/// 明文地址在发出前就拒掉，不会退回 HTTP。
class _TlsOnlyAdapter implements HttpClientAdapter {
  _TlsOnlyAdapter(this._inner);

  final HttpClientAdapter _inner;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    if (options.uri.scheme.toLowerCase() != 'https') {
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.connectionError,
        error: const TlsException('refuse cleartext'),
      );
    }
    return _inner.fetch(options, requestStream, cancelFuture);
  }

  @override
  void close({bool force = false}) => _inner.close(force: force);
}
