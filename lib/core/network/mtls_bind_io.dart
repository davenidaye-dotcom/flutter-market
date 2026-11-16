import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/services.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../security/shield_cert_pin.dart';
import 'api_exception.dart';
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

const _mainlandBlocked = '当前地区暂不支持登录';
const _mainlandUnknown = '当前网络无法确认地区，请稍后重试';

/// 登录和注册前直连查询出口地址。不走盾，包内不放业务域名。
Future<void> ensureMainland() async {
  await VpnGuard.assertClear();
  final mainland = await _isMainland();
  if (mainland == null) {
    throw const ApiException(message: _mainlandUnknown, isNetwork: true);
  }
  if (!mainland) {
    throw const ApiException(message: _mainlandBlocked);
  }
}

Future<bool?> _isMainland() async {
  final ipip = await _publicGet('https://myip.ipip.net');
  final fromIpip = _ipipMainland(ipip);
  if (fromIpip != null) return fromIpip;
  final who = await _publicGet('https://ipwho.is/');
  return _whoMainland(who);
}

bool? _ipipMainland(String? text) {
  if (text == null || text.isEmpty) return null;
  const mark = '来自于：';
  final at = text.indexOf(mark);
  if (at < 0) return null;
  final place = text.substring(at + mark.length).trim();
  if (place.startsWith('中国香港') || place.startsWith('中国澳门') || place.startsWith('中国台湾')) {
    return false;
  }
  if (place.startsWith('香港') || place.startsWith('澳门') || place.startsWith('台湾')) {
    return false;
  }
  return place.startsWith('中国 ');
}

bool? _whoMainland(String? text) {
  if (text == null || text.isEmpty) return null;
  final match = RegExp('"country_code"\\s*:\\s*"([A-Za-z]{2})"').firstMatch(text);
  final code = match?.group(1);
  if (code == null) return null;
  return code.toUpperCase() == 'CN';
}

Future<String?> _publicGet(String url) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
  try {
    final request = await client.getUrl(Uri.parse(url));
    final response = await request.close().timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) return null;
    return await response.transform(utf8.decoder).join().timeout(const Duration(seconds: 8));
  } catch (_) {
    return null;
  } finally {
    client.close(force: true);
  }
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

/// 正式包认证请求直连防火墙域名，信任公网根，不拨游戏盾。
void bindAuthClient(Dio dio) {
  final old = dio.httpClientAdapter;
  dio.httpClientAdapter = _TlsOnlyAdapter(
    IOHttpClientAdapter(
      createHttpClient: _appEnv == 'pro' ? _authClient : () => _httpClient(false),
    ),
  );
  old.close();
}

HttpClient _authClient() {
  final client = HttpClient(context: SecurityContext(withTrustedRoots: true));
  client.findProxy = (_) {
    if (VpnGuard.blocked) {
      throw const VpnBlockedException();
    }
    return 'DIRECT';
  };
  client.badCertificateCallback = (_, _, _) => false;
  return client;
}

Future<WebSocketChannel> connectFlyroomSocket(
  Uri uri, {
  Map<String, dynamic>? headers,
}) async {
  if (uri.scheme.toLowerCase() != 'wss') {
    throw const TlsException('refuse cleartext websocket');
  }
  await VpnGuard.assertClear();
  await ensureMtlsMaterialLoaded();
  final merged = <String, dynamic>{
    if (_appEnv == 'pro') 'host': ShieldGate.ruleHost,
    ...?headers,
  };
  final channel = IOWebSocketChannel.connect(
    uri,
    customClient: _httpClient(false),
    headers: merged.isEmpty ? null : merged,
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

/// 正式包 TCP 只拨盾的本机端口。四层要端口不带域名，www.demo.com 只放在 HTTP Host。TLS 只核对公钥指纹。
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
