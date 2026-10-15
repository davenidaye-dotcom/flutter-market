import 'api_exception.dart';
import 'auth_api_client.dart';
import 'client_cert_store.dart';

enum CertRefreshResult { installed, disabled, failed }

/// 认证域换证。同一时刻只跑一次。
class ClientCertRefresh {
  ClientCertRefresh._();

  static Future<CertRefreshResult>? _inflight;

  static Future<CertRefreshResult> refresh() {
    final existing = _inflight;
    if (existing != null) return existing;
    final fut = _once();
    _inflight = fut;
    return fut.whenComplete(() {
      if (identical(_inflight, fut)) _inflight = null;
    });
  }

  static Future<CertRefreshResult> _once() async {
    try {
      final data = await AuthApiClient.instance.post('/auth/cert/refresh');
      if (data is Map) {
        ClientCertStore.instance.applyLoginMap(Map<String, dynamic>.from(data));
        return ClientCertStore.instance.hasCert
            ? CertRefreshResult.installed
            : CertRefreshResult.failed;
      }
      return CertRefreshResult.failed;
    } on ApiException catch (e) {
      if (e.bizCode == 'MTLS_DISABLED') {
        ClientCertStore.instance.clear();
        return CertRefreshResult.disabled;
      }
      return CertRefreshResult.failed;
    }
  }
}
