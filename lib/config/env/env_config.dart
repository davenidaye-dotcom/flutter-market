/// App environment — switch via --dart-define=APP_ENV=dev|test|pro
enum AppEnvironment {
  dev('dev', '瑞丰Dev'),
  test('test', '瑞丰Test'),
  pro('pro', '瑞丰');

  const AppEnvironment(this.key, this.appName);

  final String key;
  final String appName;

  static AppEnvironment fromKey(String? key) {
    return AppEnvironment.values.firstWhere(
      (e) => e.key == key,
      orElse: () => AppEnvironment.dev,
    );
  }
}

/// Environment config（业务 API/WS 可由 OSS 引导覆盖，包内不长期依赖写死源站）
class EnvConfig {
  EnvConfig._();

  static const _envKey = String.fromEnvironment('APP_ENV', defaultValue: 'dev');

  static final AppEnvironment environment = AppEnvironment.fromKey(_envKey);

  /// OSS/CDN 下发或缓存覆盖；未就绪时用 [builtinApiBaseUrl]
  static String? _apiBaseUrlOverride;
  static String? _wsBaseUrlOverride;
  static String? _authBaseUrlOverride;

  // 只走 TLS：443 业务、8443 认证。证书只认包内 FlyRoom 根证书，抓包证书握手即失败。
  static String get builtinApiBaseUrl => switch (environment) {
        AppEnvironment.dev => 'https://207.148.105.182/api/v1',
        AppEnvironment.test => 'https://207.148.105.182/api/v1',
        AppEnvironment.pro => 'https://207.148.105.182/api/v1',
      };

  /// 登录和换证也走 443。认证请求不带客户端证，optional 下照常通过。
  static String get builtinAuthBaseUrl => builtinApiBaseUrl;

  static String get builtinWsBaseUrl => switch (environment) {
        AppEnvironment.dev => 'wss://207.148.105.182/ws/v1',
        AppEnvironment.test => 'wss://207.148.105.182/ws/v1',
        AppEnvironment.pro => 'wss://207.148.105.182/ws/v1',
      };

  /// HTTP API prefix (no trailing slash). Paths are like /auth/member/login
  static String get apiBaseUrl => _apiBaseUrlOverride ?? builtinApiBaseUrl;

  /// WebSocket prefix (no trailing slash). Paths like /member?token=
  static String get wsBaseUrl => _wsBaseUrlOverride ?? builtinWsBaseUrl;

  /// 登录 / 换证。未单独下发时与 [apiBaseUrl] 相同。
  static String get authBaseUrl =>
      _authBaseUrlOverride ?? _apiBaseUrlOverride ?? builtinAuthBaseUrl;

  /// 下发的地址不是 https / wss 一律丢弃，退回内置 TLS 地址，不给明文降级的机会。
  static void applyEndpoint({
    required String apiBaseUrl,
    required String wsBaseUrl,
    String? authBaseUrl,
  }) {
    _apiBaseUrlOverride = _secure(apiBaseUrl, 'https');
    _wsBaseUrlOverride = _secure(wsBaseUrl, 'wss');
    _authBaseUrlOverride = _secure(authBaseUrl, 'https');
  }

  static String? _secure(String? raw, String scheme) {
    final v = raw?.trim().replaceAll(RegExp(r'/+$'), '');
    if (v == null || v.isEmpty) return null;
    return v.toLowerCase().startsWith('$scheme://') ? v : null;
  }

  static void clearEndpointOverride() {
    _apiBaseUrlOverride = null;
    _wsBaseUrlOverride = null;
    _authBaseUrlOverride = null;
  }

  static const clientId = 'flyroom';

  static String get dingxiangAppId => switch (environment) {
        AppEnvironment.dev => 'dx_dev_app_id',
        AppEnvironment.test => 'dx_test_app_id',
        AppEnvironment.pro => 'dx_pro_app_id',
      };

  static bool get isDebug => environment != AppEnvironment.pro;

  /// 内置版本。是否要更新只和发布版本号按段比较，不看版本序号。
  static String get appVersion => '1.0';

  /// 与 pubspec 的构建号一致。更新判断不用它。
  static const int appVersionCode = 1;
}
