import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/services.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../security/vpn_guard.dart';
import 'client_cert_store.dart';

/// dev/test 与 pro 各信任自己的根 CA。由 --dart-define=APP_ENV=dev|test|pro 决定。
const _appEnv = String.fromEnvironment('APP_ENV', defaultValue: 'dev');
const _caAsset = _appEnv == 'pro'
    ? 'assets/certs/flyroom_root_ca.pro.crt'
    : 'assets/certs/flyroom_root_ca.dev.crt';

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
  await VpnGuard.assertClear();
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
  ) async {
    if (options.uri.scheme.toLowerCase() != 'https') {
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.connectionError,
        error: const TlsException('refuse cleartext'),
      );
    }
    // 有 VPN（抓包软件）就不发，连 TCP 都不建。
    if (await VpnGuard.active()) {
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.connectionError,
        error: const VpnBlockedException(),
      );
    }
    return _inner.fetch(options, requestStream, cancelFuture);
  }

  @override
  void close({bool force = false}) => _inner.close(force: force);
}
