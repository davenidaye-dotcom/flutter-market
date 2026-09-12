/// App environment — switch via --dart-define=APP_ENV=dev|test|pro
enum AppEnvironment {
  dev('dev', '乐投Dev'),
  test('test', '乐投Test'),
  pro('pro', '乐投');

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

  static String get builtinApiBaseUrl => switch (environment) {
        // 走 80 反代 → Java 9080；不要写成后台 Vue 的 8088/8098
        AppEnvironment.dev => 'http://207.148.105.182/api/v1',
        AppEnvironment.test => 'http://207.148.105.182/api/v1',
        AppEnvironment.pro => 'http://207.148.105.182/api/v1',
      };

  static String get builtinWsBaseUrl => switch (environment) {
        AppEnvironment.dev => 'ws://207.148.105.182/ws/v1',
        AppEnvironment.test => 'ws://207.148.105.182/ws/v1',
        AppEnvironment.pro => 'ws://207.148.105.182/ws/v1',
      };

  /// HTTP API prefix (no trailing slash). Paths are like /auth/member/login
  static String get apiBaseUrl =>
      (_apiBaseUrlOverride?.trim().isNotEmpty ?? false)
          ? _apiBaseUrlOverride!.trim().replaceAll(RegExp(r'/+$'), '')
          : builtinApiBaseUrl;

  /// WebSocket prefix (no trailing slash). Paths like /member?token=
  static String get wsBaseUrl =>
      (_wsBaseUrlOverride?.trim().isNotEmpty ?? false)
          ? _wsBaseUrlOverride!.trim().replaceAll(RegExp(r'/+$'), '')
          : builtinWsBaseUrl;

  static void applyEndpoint({required String apiBaseUrl, required String wsBaseUrl}) {
    _apiBaseUrlOverride = apiBaseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    _wsBaseUrlOverride = wsBaseUrl.trim().replaceAll(RegExp(r'/+$'), '');
  }

  static void clearEndpointOverride() {
    _apiBaseUrlOverride = null;
    _wsBaseUrlOverride = null;
  }

  static const clientId = 'flyroom';

  static String get dingxiangAppId => switch (environment) {
        AppEnvironment.dev => 'dx_dev_app_id',
        AppEnvironment.test => 'dx_test_app_id',
        AppEnvironment.pro => 'dx_pro_app_id',
      };

  static bool get isDebug => environment != AppEnvironment.pro;

  static String get appVersion => '100.3.19';
}
