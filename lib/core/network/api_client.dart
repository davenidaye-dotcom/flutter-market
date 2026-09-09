import 'package:dio/dio.dart';
import '../../config/env/env_config.dart';
import 'api_exception.dart';
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
          final token = SessionStore.instance.accessToken;
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          final roomId = SessionStore.instance.roomId;
          if (roomId != null && roomId.isNotEmpty) {
            options.headers['X-Room-Id'] = roomId;
          }
          options.headers['clientid'] = EnvConfig.clientId;
          ApiRequestSigner.attach(options);
          handler.next(options);
        },
      ),
    );
  }

  static final ApiClient instance = ApiClient._();
  late final Dio _dio;

  Dio get dio => _dio;

  /// OSS 引导拿到新地址后刷新 Dio baseUrl
  void syncBaseUrl() {
    _dio.options.baseUrl = EnvConfig.apiBaseUrl;
  }

  Future<dynamic> get(
    String path, {
    Map<String, dynamic>? query,
  }) async {
    try {
      final res = await _dio.get<dynamic>(path, queryParameters: query);
      return unwrapResponse(res);
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
      final res = await _dio.post<dynamic>(
        path,
        data: data,
        queryParameters: query,
        options: headers == null || headers.isEmpty
            ? null
            : Options(headers: headers),
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
  }) async {
    try {
      final res =
          await _dio.put<dynamic>(path, data: data, queryParameters: query);
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
      final res = await _dio.delete<dynamic>(path, queryParameters: query);
      return unwrapResponse(res);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }
}
