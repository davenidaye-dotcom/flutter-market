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

/// Environment config
class EnvConfig {
  EnvConfig._();

  static const _envKey = String.fromEnvironment('APP_ENV', defaultValue: 'dev');

  static final AppEnvironment environment = AppEnvironment.fromKey(_envKey);

  /// HTTP API prefix (no trailing slash). Paths are like /auth/member/login
  static String get apiBaseUrl => switch (environment) {
        // Local/dev defaults to same test host until dedicated gateway exists
        AppEnvironment.dev => 'http://207.148.105.182/api/v1',
        AppEnvironment.test => 'http://207.148.105.182/api/v1',
        AppEnvironment.pro => 'http://207.148.105.182/api/v1',
      };

  /// WebSocket prefix (no trailing slash). Paths like /member?token=
  static String get wsBaseUrl => switch (environment) {
        AppEnvironment.dev => 'ws://207.148.105.182/ws/v1',
        AppEnvironment.test => 'ws://207.148.105.182/ws/v1',
        AppEnvironment.pro => 'ws://207.148.105.182/ws/v1',
      };

  static const clientId = 'flyroom';

  static String get dingxiangAppId => switch (environment) {
        AppEnvironment.dev => 'dx_dev_app_id',
        AppEnvironment.test => 'dx_test_app_id',
        AppEnvironment.pro => 'dx_pro_app_id',
      };

  static bool get isDebug => environment != AppEnvironment.pro;

  static String get appVersion => '100.3.19';
}
