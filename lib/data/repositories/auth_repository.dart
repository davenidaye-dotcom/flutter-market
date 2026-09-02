import '../models/app_role.dart';
import '../models/user_model.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../../core/network/session_store.dart';

/// Auth against `/auth/member/*` (player) and `/auth/portal/*` (owner/agent).
class AuthRepository {
  AuthRepository({ApiClient? client}) : _client = client ?? ApiClient.instance;

  final ApiClient _client;

  Future<UserModel> login({
    required String username,
    required String password,
    required String captchaToken,
    required AppRole expectedRole,
  }) async {
    // captcha reserved for Dingxiang; server currently optional
    final _ = captchaToken;
    final path = expectedRole == AppRole.player
        ? '/auth/member/login'
        : '/auth/portal/login';

    final data = await _client.post(path, data: {
      'username': username.trim(),
      'password': password,
      'clientType': 'APP',
    });

    if (data is! Map) {
      throw const ApiException(message: '\u767b\u5f55\u54cd\u5e94\u5f02\u5e38');
    }
    final map = Map<String, dynamic>.from(data);
    final token = map['accessToken']?.toString();
    if (token == null || token.isEmpty) {
      throw const ApiException(message: '\u767b\u5f55\u5931\u8d25\uff1a\u65e0 Token');
    }
    await SessionStore.instance.setToken(token);

    final user = UserModel.fromLoginPayload(map, fallbackUsername: username.trim());

    // 玩家登录后先回首页手动进房，清掉上次会话残留的房间上下文。
    if (expectedRole == AppRole.player) {
      await SessionStore.instance.setRoom(roomId: null, roomCode: null);
    } else {
      final room = map['room'];
      if (room is Map) {
        final roomId = room['roomId']?.toString();
        final roomCode = room['roomCode']?.toString();
        await SessionStore.instance.setRoom(roomId: roomId, roomCode: roomCode);
      }
    }

    return user;
  }

  Future<UserModel> register({
    required String username,
    required String password,
    String? nickname,
  }) async {
    final data = await _client.post('/auth/member/register', data: {
      'username': username.trim(),
      'password': password,
      if (nickname != null && nickname.isNotEmpty) 'nickname': nickname,
      'clientType': 'APP',
    });
    if (data is! Map) {
      throw const ApiException(message: '\u6ce8\u518c\u54cd\u5e94\u5f02\u5e38');
    }
    final map = Map<String, dynamic>.from(data);
    final token = map['accessToken']?.toString();
    if (token != null && token.isNotEmpty) {
      await SessionStore.instance.setToken(token);
    }
    return UserModel.fromLoginPayload(map, fallbackUsername: username.trim());
  }

  Future<void> changePassword({
    required String oldPassword,
    required String newPassword,
  }) async {
    await _client.post('/auth/password/change', data: {
      'oldPassword': oldPassword,
      'newPassword': newPassword,
      'confirmPassword': newPassword,
    });
  }

  Future<void> logout() async {
    try {
      if (SessionStore.instance.hasToken) {
        await _client.post('/auth/logout');
      }
    } catch (_) {
      // ignore network errors on logout
    } finally {
      await SessionStore.instance.clear();
    }
  }
}
