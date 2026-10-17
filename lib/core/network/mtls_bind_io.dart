import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/services.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../security/vpn_guard.dart';
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
  await VpnGuard.assertClear();
  await ensureMtlsMaterialLoaded();
  final channel = IOWebSocketChannel.connect(
    uri,
    customClient: _httpClient(true),
  );
  await channel.ready;
  return channel;
}

/// 登录、换证不带客户端证，信系统公信根（Let's Encrypt）。
/// 业务 API、WebSocket 带客户端证，只信包内 FlyRoom 根证书，不信系统证书。
HttpClient _httpClient(bool presentClientCert) {
  final context = SecurityContext(withTrustedRoots: !presentClientCert);
  if (presentClientCert) {
    final ca = _caBytes;
    if (ca != null && ca.isNotEmpty) {
      context.setTrustedCertificatesBytes(ca);
    }
    final store = ClientCertStore.instance;
    if (store.hasCert) {
      context.useCertificateChainBytes(utf8.encode(store.certPem!));
      context.usePrivateKeyBytes(utf8.encode(store.keyPem!));
    }
  }
  final client = HttpClient(context: context);
  // 连接真正建立前再看一次。回调已经把 VPN 标上时，这里抛错，TCP 不会发，抓包里没有 CONNECT。
  client.findProxy = (_) {
    if (VpnGuard.blocked) {
      throw const VpnBlockedException();
    }
    return 'DIRECT';
  };
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
