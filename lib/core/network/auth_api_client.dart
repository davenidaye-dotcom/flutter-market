import 'mtls_bind_stub.dart' if (dart.library.io) 'mtls_bind_io.dart';

import 'package:dio/dio.dart';

import '../../config/env/env_config.dart';
import '../security/api_request_signer.dart';
import 'api_exception.dart';
import 'session_kick.dart';

/// 登录、注册、设备快登、换证。单向 TLS，不带客户端证。
class AuthApiClient {
  AuthApiClient._() {
    _dio = Dio(
      BaseOptions(
        baseUrl: EnvConfig.authBaseUrl,
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
    bindMtlsClient(_dio, presentClientCert: false);
  }

  static final AuthApiClient instance = AuthApiClient._();
  late final Dio _dio;

  void syncBaseUrl() {
    _dio.options.baseUrl = EnvConfig.authBaseUrl;
    bindMtlsClient(_dio, presentClientCert: false);
  }

  Future<dynamic> post(String path, {Object? data}) async {
    await ensureMtlsMaterialLoaded();
    try {
      final res = await _dio.post<dynamic>(path, data: data);
      return unwrapResponse(res);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }
}
