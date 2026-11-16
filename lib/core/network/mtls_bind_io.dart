import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/services.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

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
    customClient: _httpClient(true),
  );
  await channel.ready;
  return channel;
}

/// pro：登录、换证不带客户端证，信系统公信根。业务和 WebSocket 只信包内生产根。
/// dev/test：测试机 443 的服务端证是私有根签的，登录也只信这张根，不信公网根。
HttpClient _httpClient(bool presentClientCert) {
  final trustPublicRoots = !_trustPrivateRoot && !presentClientCert;
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
  client.badCertificateCallback = (_, _, _) => false;
  return client;
}

HttpClient _downloadClient() {
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

final _ipv4 = RegExp(
  r'(?:(?:25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)\.){3}(?:25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)',
);

/// 本机当前出口 IP，也就是防火墙封禁记录里的来源 IP。直连公网，不走盾。
Future<String> fetchEgressIp() async {
  await VpnGuard.assertClear();
  Object? last;
  for (final url in const ['https://myip.ipip.net', 'https://api.ipify.org']) {
    try {
      final body = await _egressText(url);
      final ip = _ipv4.firstMatch(body)?.group(0);
      if (ip != null) return ip;
      last = const FormatException('未获取到出口IP');
    } catch (e) {
      last = e;
      if (e is VpnBlockedException) break;
    }
  }
  if (last is VpnBlockedException) throw last;
  throw last ?? const FormatException('未获取到出口IP');
}

Future<String> _egressText(String url) async {
  final client = HttpClient(context: SecurityContext(withTrustedRoots: true))
    ..connectionTimeout = const Duration(seconds: 8)
    ..findProxy = ((_) => 'DIRECT')
    ..badCertificateCallback = (_, _, _) => false;
  try {
    final request = await client.getUrl(Uri.parse(url)).timeout(const Duration(seconds: 8));
    final response = await request.close().timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) {
      await response.drain<void>();
      throw HttpException('IP查询失败', uri: request.uri);
    }
    final bytes = await response.fold<List<int>>(<int>[], (buf, chunk) => buf..addAll(chunk));
    return utf8.decode(bytes, allowMalformed: true);
  } finally {
    client.close(force: true);
  }
}
