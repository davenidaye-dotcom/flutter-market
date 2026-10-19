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

  /// OSS 引导成功后覆盖内置地址。生产环境拉不到 OSS 时保持空。
  static String? _apiBaseUrlOverride;
  static String? _wsBaseUrlOverride;
  static String? _authBaseUrlOverride;

  /// 本次启动已从 OSS 拿到 https/wss 线路。
  static bool get hasEndpoint =>
      _apiBaseUrlOverride != null && _wsBaseUrlOverride != null;

  /// 开发/测试拉不到 OSS 时仍走内置测试地址。生产必须拿到 OSS 才允许请求。
  static bool get requestsAllowed =>
      environment != AppEnvironment.pro || hasEndpoint;

  // 开发、测试的内置地址，也用于生成加密配置。生产拉不到 OSS 时不用它发请求。
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

  /// HTTP API prefix (no trailing slash). 生产且没有 OSS 线路时为空。
  static String get apiBaseUrl => _apiBaseUrlOverride ?? _fallbackApiBaseUrl;

  /// WebSocket prefix (no trailing slash). 生产且没有 OSS 线路时为空。
  static String get wsBaseUrl => _wsBaseUrlOverride ?? _fallbackWsBaseUrl;

  /// 登录 / 换证。未单独下发时与 [apiBaseUrl] 相同。
  static String get authBaseUrl =>
      _authBaseUrlOverride ?? _apiBaseUrlOverride ?? _fallbackApiBaseUrl;

  static String get _fallbackApiBaseUrl =>
      environment == AppEnvironment.pro ? '' : builtinApiBaseUrl;

  static String get _fallbackWsBaseUrl =>
      environment == AppEnvironment.pro ? '' : builtinWsBaseUrl;

  /// 下发的地址不是 https / wss 一律丢弃。生产不回退到包内地址。
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
  static String get appVersion => '1.2';

  /// 与 pubspec 的构建号一致。更新判断不用它。
  static const int appVersionCode = 2;
}
