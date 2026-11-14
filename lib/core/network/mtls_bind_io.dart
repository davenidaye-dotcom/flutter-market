import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/services.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../security/shield_cert_pin.dart';
import '../security/shield_gate.dart';
import '../security/vpn_guard.dart';
import 'client_cert_store.dart';

/// dev/test 连旧测试机，服务端证由私有根签发。pro 继续用生产根。
const _appEnv = String.fromEnvironment('APP_ENV', defaultValue: 'dev');
const _trustPrivateRoot = _appEnv != 'pro';
const _caAsset = _trustPrivateRoot
    ? 'assets/certs/flyroom_root_ca.dev.crt'
    : 'assets/certs/flyroom_root_ca.crt';

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

/// 安装包就是二维码里的链接，http、https 都下。https 时公网证书和包内根证书都信，不带客户端证。
Future<void> downloadPackage(
  String url,
  String savePath, {
  required void Function(int received, int total) onProgress,
  CancelToken? cancelToken,
}) async {
  final uri = Uri.tryParse(url);
  final scheme = uri?.scheme.toLowerCase();
  if (scheme != 'https' && scheme != 'http') {
    throw const FormatException('二维码里不是下载地址');
  }
  await ensureMtlsMaterialLoaded();
  final dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(minutes: 10),
      followRedirects: true,
    ),
  );
  dio.httpClientAdapter = _VpnGuardAdapter(
    IOHttpClientAdapter(createHttpClient: _downloadClient),
  );
  try {
    await dio.download(
      url,
      savePath,
      cancelToken: cancelToken,
      onReceiveProgress: onProgress,
    );
  } finally {
    dio.close();
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
    customClient: _httpClient(false),
  );
  await channel.ready;
  return channel;
}

/// 不再出示客户端证。dev/test 的服务端证仍由包内测试根签发。
/// 正式包不信公网根，也不按域名核对，只在盾隧道里核对公钥指纹。
HttpClient _httpClient(bool presentClientCert) {
  final trustPublicRoots = _appEnv != 'pro' && !_trustPrivateRoot && !presentClientCert;
  final context = SecurityContext(withTrustedRoots: trustPublicRoots);
  if (!trustPublicRoots) {
    final ca = _caBytes;
    if (ca != null && ca.isNotEmpty) {
      context.setTrustedCertificatesBytes(ca);
    }
  }
  if (presentClientCert) {
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
  client.badCertificateCallback = (cert, _, _) =>
      _appEnv == 'pro' && shieldCertPinMatches(cert.der);
  if (_appEnv == 'pro') {
    client.idleTimeout = Duration.zero;
    client.connectionFactory = (_, _, _) => _shieldConnect(context);
  }
  return client;
}

/// 正式包 TCP 只拨盾的本机端口。不传业务域名，TLS 只核对公钥指纹。
/// 直连时 HttpClient 不会再给 connectionFactory 返回的套接字做一次握手。
Future<ConnectionTask<Socket>> _shieldConnect(SecurityContext context) async {
  if (VpnGuard.blocked) {
    throw const VpnBlockedException();
  }
  final endpoint = await ShieldGate.localEndpoint();
  if (endpoint == null) {
    throw const SocketException('shield unavailable');
  }
  final task = await Socket.startConnect(endpoint.ip, endpoint.port);
  return ConnectionTask.fromSocket(
    task.socket.then((raw) async {
      try {
        return await SecureSocket.secure(
          raw,
          context: context,
          onBadCertificate: (cert) => shieldCertPinMatches(cert.der),
        );
      } catch (_) {
        raw.destroy();
        rethrow;
      }
    }),
    task.cancel,
  );
}

HttpClient _downloadClient() {
  // 安装包地址不固定，保持直连，不走游戏盾。
  final context = SecurityContext(withTrustedRoots: true);
  final ca = _caBytes;
  if (ca != null && ca.isNotEmpty) {
    context.setTrustedCertificatesBytes(ca);
  }
  final client = HttpClient(context: context);
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

/// 只给安装包下载用：放行明文，有 VPN 照样不发。
class _VpnGuardAdapter implements HttpClientAdapter {
  _VpnGuardAdapter(this._inner);

  final HttpClientAdapter _inner;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
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
