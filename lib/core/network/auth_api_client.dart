import 'mtls_bind_stub.dart' if (dart.library.io) 'mtls_bind_io.dart';

import 'package:dio/dio.dart';

import '../../config/env/env_config.dart';
import '../security/api_request_signer.dart';
import '../security/shield_gate.dart';
import 'api_exception.dart';
import 'client_cert_store.dart';
import 'session_kick.dart';

/// 登录、注册、设备快登、换证。内存里有客户端证才附带，没有就按普通 TLS。
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
    _rebind();
    ClientCertStore.instance.addListener(_rebind);
  }

  static final AuthApiClient instance = AuthApiClient._();
  late final Dio _dio;

  void _rebind() {
    bindMtlsClient(_dio, presentClientCert: ClientCertStore.instance.hasCert);
  }

  void syncBaseUrl() {
    _dio.options.baseUrl = EnvConfig.authBaseUrl;
    _rebind();
  }

  Future<dynamic> post(String path, {Object? data}) async {
    if (!EnvConfig.requestsAllowed || ShieldGate.blocksBusiness) {
      throw const ApiException(message: '线路未就绪', bizCode: 'NO_ENDPOINT');
    }
    await ensureMtlsMaterialLoaded();
    try {
      final res = await _dio.post<dynamic>(path, data: data);
      return unwrapResponse(res);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }
}
