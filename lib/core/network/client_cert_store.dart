/// 登录下发的客户端证。只放内存，不进 SharedPreferences。
class ClientCertStore {
  ClientCertStore._();
  static final ClientCertStore instance = ClientCertStore._();

  final List<void Function()> _listeners = [];

  String? certPem;
  String? keyPem;
  DateTime? expiresAt;
  int renewBeforeSeconds = 900;
  /// 登录已回会话，证书还在 /auth/cert/refresh 上。业务请求先等这一次。
  bool pending = false;

  bool get hasCert =>
      certPem != null &&
      certPem!.isNotEmpty &&
      keyPem != null &&
      keyPem!.isNotEmpty;

  bool get shouldRenew {
    if (!hasCert || expiresAt == null) return false;
    final left = expiresAt!.difference(DateTime.now()).inSeconds;
    return left < renewBeforeSeconds;
  }

  void addListener(void Function() listener) {
    if (!_listeners.contains(listener)) _listeners.add(listener);
  }

  /// 登录或换证响应。没有 PEM 时清掉内存证，回到纯 Token。
  /// clientCertPending 只表示马上去领证，不能把这次登录当成「没有证书要求」。
  void applyLoginMap(Map<String, dynamic> map) {
    if (map['clientCertPending'] == true) {
      certPem = null;
      keyPem = null;
      expiresAt = null;
      pending = true;
      _notify();
      return;
    }
    pending = false;
    final cert = map['clientCertPem']?.toString();
    final key = map['clientKeyPem']?.toString();
    if (cert == null || cert.isEmpty || key == null || key.isEmpty) {
      clear();
      return;
    }
    certPem = cert;
    keyPem = key;
    final seconds = int.tryParse('${map['clientCertExpiresIn'] ?? ''}');
    expiresAt = DateTime.now().add(Duration(seconds: seconds ?? 14400));
    final renew = int.tryParse('${map['clientCertRenewBefore'] ?? ''}');
    if (renew != null && renew > 0) renewBeforeSeconds = renew;
    _notify();
  }

  void clear() {
    if (!hasCert && expiresAt == null) return;
    certPem = null;
    keyPem = null;
    expiresAt = null;
    _notify();
  }

  void _notify() {
    for (final listener in List<void Function()>.from(_listeners)) {
      listener();
    }
  }
}
