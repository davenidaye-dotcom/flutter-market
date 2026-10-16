import 'dart:typed_data';

import 'package:dio/dio.dart';
import '../../config/env/env_config.dart';
import 'api_exception.dart';
import 'client_cert_refresh.dart';
import 'client_cert_store.dart';
import 'mtls_bind_stub.dart' if (dart.library.io) 'mtls_bind_io.dart';
import 'session_kick.dart';
import 'session_store.dart';
import '../security/api_request_signer.dart';

/// HTTP client for FlyRoom `/api/v1`
class ApiClient {
  ApiClient._() {
    _dio = Dio(
      BaseOptions(
        baseUrl: EnvConfig.apiBaseUrl,
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 20),
        headers: {
          'Content-Type': 'application/json',
          'clientid': EnvConfig.clientId,
        },
      ),
    );
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          SessionKick.attach(options);
          final roomId = SessionStore.instance.roomId;
          if (roomId != null && roomId.isNotEmpty) {
            options.headers['X-Room-Id'] = roomId;
          }
          options.headers['clientid'] = EnvConfig.clientId;
          ApiRequestSigner.attach(options);
          handler.next(options);
        },
        onResponse: (response, handler) {
          SessionKick.consider(
            response.requestOptions,
            response.data,
            response.statusCode,
          );
          handler.next(response);
        },
        onError: (error, handler) {
          SessionKick.consider(
            error.requestOptions,
            error.response?.data,
            error.response?.statusCode,
          );
          handler.next(error);
        },
      ),
    );
    ClientCertStore.instance.addListener(rebindTls);
    rebindTls();
  }

  static final ApiClient instance = ApiClient._();
  late final Dio _dio;

  Dio get dio => _dio;

  /// OSS 引导拿到新地址后刷新 Dio baseUrl
  void syncBaseUrl() {
    _dio.options.baseUrl = EnvConfig.apiBaseUrl;
    rebindTls();
  }

  void rebindTls() {
    bindMtlsClient(_dio, presentClientCert: true);
  }

  Future<Response<T>> _send<T>(
    Future<Response<T>> Function() send,
  ) async {
    await ensureMtlsMaterialLoaded();
    if (ClientCertStore.instance.shouldRenew) {
      await ClientCertRefresh.refresh();
    }
    try {
      return await send();
    } on DioException catch (e) {
      if (!await _recover(e)) rethrow;
      return await send();
    }
  }

  Future<bool> _recover(DioException error) async {
    if (!_needsFreshCert(error)) return false;
    final result = await ClientCertRefresh.refresh();
    return result == CertRefreshResult.installed ||
        result == CertRefreshResult.disabled;
  }

  bool _needsFreshCert(DioException error) {
    final data = error.response?.data;
    if (data is Map && bizCodeOf(data) == 'MTLS_REQUIRED') return true;
    // 带着过期证书时 Nginx 直接回 400（HTML，不是 JSON）
    final status = error.response?.statusCode;
    if (data is String &&
        (status == 400 || status == 495 || status == 496) &&
        data.toLowerCase().contains('ssl certificate')) {
      return true;
    }
    final kind = error.error?.runtimeType.toString() ?? '';
    final text = '${error.error ?? ''} ${error.message ?? ''}';
    return kind.contains('HandshakeException') ||
        text.contains('HandshakeException');
  }

  Future<dynamic> get(
    String path, {
    Map<String, dynamic>? query,
  }) async {
    try {
      final res = await _send(() => _dio.get<dynamic>(path, queryParameters: query));
      return unwrapResponse(res);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// 需要读响应头（如分页游标 X-Chat-Next-Before-Seq）时使用；header 名统一小写。
  Future<({dynamic data, Map<String, String> headers})> getWithHeaders(
    String path, {
    Map<String, dynamic>? query,
  }) async {
    try {
      final res = await _send(() => _dio.get<dynamic>(path, queryParameters: query));
      final headers = <String, String>{
        for (final e in res.headers.map.entries)
          if (e.value.isNotEmpty) e.key.toLowerCase(): e.value.first,
      };
      return (data: unwrapResponse(res), headers: headers);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<dynamic> post(
    String path, {
    Object? data,
    Map<String, dynamic>? query,
    Map<String, dynamic>? headers,
  }) async {
    try {
      final res = await _send(
        () => _dio.post<dynamic>(
          path,
          data: data,
          queryParameters: query,
          options: headers == null || headers.isEmpty
              ? null
              : Options(headers: headers),
        ),
      );
      return unwrapResponse(res);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<dynamic> put(
    String path, {
    Object? data,
    Map<String, dynamic>? query,
    bool ignoreUnauthorized = false,
  }) async {
    try {
      final res = await _send(
        () => _dio.put<dynamic>(
          path,
          data: data,
          queryParameters: query,
          options: ignoreUnauthorized
              ? Options(extra: {SessionKick.skipExtra: true})
              : null,
        ),
      );
      return unwrapResponse(res);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<dynamic> delete(
    String path, {
    Map<String, dynamic>? query,
  }) async {
    try {
      final res = await _send(
        () => _dio.delete<dynamic>(path, queryParameters: query),
      );
      return unwrapResponse(res);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// 二进制下载（客服图片等）；走同一套签名/鉴权，不走 JSON unwrap。
  Future<Uint8List> getBytes(String path) async {
    try {
      final res = await _send(
        () => _dio.get<List<int>>(
          path,
          options: Options(responseType: ResponseType.bytes),
        ),
      );
      final data = res.data;
      if (data == null || data.isEmpty) {
        throw const ApiException(message: '文件为空');
      }
      return Uint8List.fromList(data);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }
}
