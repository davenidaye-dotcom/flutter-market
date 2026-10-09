import 'package:shared_preferences/shared_preferences.dart';

/// 登录页「记住密码」：玩家 / 房主代理分入口存储。
class LoginRememberStore {
  LoginRememberStore._();

  static const _kPlayerRemember = 'flyroom_login_remember_player';
  static const _kPlayerUser = 'flyroom_login_user_player';
  static const _kPlayerPass = 'flyroom_login_pass_player';
  static const _kHostRemember = 'flyroom_login_remember_host';
  static const _kHostUser = 'flyroom_login_user_host';
  static const _kHostPass = 'flyroom_login_pass_host';

  static String _rememberKey(bool hostMode) =>
      hostMode ? _kHostRemember : _kPlayerRemember;
  static String _userKey(bool hostMode) => hostMode ? _kHostUser : _kPlayerUser;
  static String _passKey(bool hostMode) => hostMode ? _kHostPass : _kPlayerPass;

  static Future<({bool remember, String username, String password})> load(
    bool hostMode,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final remember = prefs.getBool(_rememberKey(hostMode)) ?? false;
    if (!remember) {
      return (remember: false, username: '', password: '');
    }
    return (
      remember: true,
      username: prefs.getString(_userKey(hostMode)) ?? '',
      password: prefs.getString(_passKey(hostMode)) ?? '',
    );
  }

  static Future<void> save({
    required bool hostMode,
    required bool remember,
    required String username,
    required String password,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (!remember) {
      await clear(hostMode);
      return;
    }
    await prefs.setBool(_rememberKey(hostMode), true);
    await prefs.setString(_userKey(hostMode), username.trim());
    await prefs.setString(_passKey(hostMode), password);
  }

  static Future<void> clear(bool hostMode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_rememberKey(hostMode));
    await prefs.remove(_userKey(hostMode));
    await prefs.remove(_passKey(hostMode));
  }
}
