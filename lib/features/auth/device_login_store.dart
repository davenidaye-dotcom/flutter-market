import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/utils/request_id.dart';

/// 设备令牌快速登录：deviceId 随机生成并常驻；deviceToken 每次登录轮换，
/// 存进安全存储（Keychain / Keystore），以用户名为键。
class DeviceLoginStore {
  DeviceLoginStore._();

  static const _kDeviceId = 'flyroom_device_id';
  static const _kLastUser = 'flyroom_device_last_user';
  static const _secure = FlutterSecureStorage();

  static String _tokenKey(String username) =>
      'flyroom_device_token_${username.trim().toLowerCase()}';

  static Future<String> deviceId() async {
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString(_kDeviceId);
    if (id == null || id.isEmpty) {
      id = newRequestId();
      await prefs.setString(_kDeviceId, id);
    }
    return id;
  }

  static Future<void> saveToken(String username, String token) async {
    final name = username.trim();
    if (name.isEmpty || token.isEmpty) return;
    try {
      await _secure.write(key: _tokenKey(name), value: token);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kLastUser, name);
    } catch (_) {
      // 安全存储不可用时只是退化为密码登录
    }
  }

  /// 最近一次带令牌登录的用户及其令牌；没有则 null。
  static Future<({String username, String token})?> loadSaved() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final user = prefs.getString(_kLastUser);
      if (user == null || user.isEmpty) return null;
      final token = await _secure.read(key: _tokenKey(user));
      if (token == null || token.isEmpty) return null;
      return (username: user, token: token);
    } catch (_) {
      return null;
    }
  }

  static Future<void> clear(String username) async {
    final name = username.trim();
    if (name.isEmpty) return;
    try {
      await _secure.delete(key: _tokenKey(name));
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getString(_kLastUser) == name) await prefs.remove(_kLastUser);
    } catch (_) {}
  }
}
