import 'dart:async';

import '../models/app_role.dart';
import '../models/user_model.dart';
import '../../core/network/api_client.dart';
import '../../core/network/auth_api_client.dart';
import '../../core/network/api_exception.dart';
import '../../core/network/client_cert_store.dart';
import '../../core/network/session_store.dart';
import '../../features/auth/device_login_store.dart';

/// Auth against `/auth/member/*` (player) and `/auth/portal/*` (owner/agent).
class AuthRepository {
  AuthRepository({ApiClient? client}) : _client = client ?? ApiClient.instance;

  final ApiClient _client;

  Future<UserModel> login({
    required String username,
    required String password,
    required String captchaToken,
    required AppRole expectedRole,
    required int commitEpoch,
  }) async {
    // captcha reserved for Dingxiang; server currently optional
    final _ = captchaToken;
    final path = expectedRole == AppRole.player
        ? '/auth/member/login'
        : '/auth/portal/login';

    // 玩家登录带 deviceId，服务端才会下发 deviceToken（用于下次快速登录）
    final deviceId = expectedRole == AppRole.player
        ? await DeviceLoginStore.deviceId()
        : null;
    final data = await AuthApiClient.instance.post(path, data: {
      'username': username.trim(),
      'password': password,
      'clientType': 'APP',
      if (deviceId != null) 'deviceId': deviceId,
    });
    return _finishLogin(
      data,
      username: username,
      expectedRole: expectedRole,
      commitEpoch: commitEpoch,
    );
  }

  /// 设备令牌快速登录：成功返回与密码登录相同的用户，并换存新的 deviceToken。
  /// 令牌失效（DEVICE_TOKEN_INVALID）时抛出，由调用方清令牌并回到密码登录。
  Future<UserModel> deviceLogin({
    required String username,
    required String deviceToken,
    int? epoch,
  }) async {
    final commitEpoch = epoch ?? SessionStore.instance.epoch;
    final data = await AuthApiClient.instance.post('/auth/member/device-login', data: {
      'username': username.trim(),
      'deviceId': await DeviceLoginStore.deviceId(),
      'deviceToken': deviceToken,
      'clientType': 'APP',
    });
    return _finishLogin(
      data,
      username: username,
      expectedRole: AppRole.player,
      commitEpoch: commitEpoch,
    );
  }

  Future<UserModel> _finishLogin(
    dynamic data, {
    required String username,
    required AppRole expectedRole,
    required int commitEpoch,
  }) async {
    if (data is! Map) {
      throw const ApiException(message: '\u767b\u5f55\u54cd\u5e94\u5f02\u5e38');
    }
    final map = Map<String, dynamic>.from(data);
    final token = map['accessToken']?.toString();
    if (token == null || token.isEmpty) {
      throw const ApiException(message: '\u767b\u5f55\u5931\u8d25\uff1a\u65e0 Token');
    }

    final accountType = map['accountType']?.toString();
    if (!AppRoleX.isAppLoginAllowedType(accountType)) {
      throw const ApiException(message: '\u8d26\u53f7\u5bc6\u7801\u9519\u8bef');
    }
    _ensureEpoch(commitEpoch);

    final saved = await SessionStore.instance.setToken(token, epoch: commitEpoch);
    if (!saved) {
      throw const ApiException(message: '\u767b\u5f55\u5df2\u53d6\u6d88', bizCode: 'LOGIN_SUPERSEDED');
    }
    _ensureEpoch(commitEpoch, token);

    late final UserModel user;
    try {
      user = UserModel.fromLoginPayload(map, fallbackUsername: username.trim());
    } on FormatException {
      if (SessionStore.instance.epoch == commitEpoch) {
        await SessionStore.instance.clear();
      } else {
        _ensureEpoch(commitEpoch, token);
      }
      throw const ApiException(message: '\u8d26\u53f7\u5bc6\u7801\u9519\u8bef');
    }
    _ensureEpoch(commitEpoch, token);

    // 玩家登录后先回首页手动进房，清掉上次会话残留的房间上下文。
    if (expectedRole == AppRole.player) {
      await SessionStore.instance.setRoom(
        roomId: null,
        roomCode: null,
        epoch: commitEpoch,
      );
    } else {
      final room = map['room'];
      if (room is Map) {
        final roomId = room['roomId']?.toString();
        final roomCode = room['roomCode']?.toString();
        await SessionStore.instance.setRoom(
          roomId: roomId,
          roomCode: roomCode,
          epoch: commitEpoch,
        );
      }
    }
    // setRoom 会让出执行权。代际已变就撤掉这次写下的 token，不能清掉后来的登录。
    _ensureEpoch(commitEpoch, token);
    if (expectedRole == AppRole.player) {
      final deviceToken = map['deviceToken']?.toString() ?? '';
      if (deviceToken.isNotEmpty) {
        await DeviceLoginStore.saveToken(user.username, deviceToken);
      }
    }
    _ensureEpoch(commitEpoch, token);
    ClientCertStore.instance.applyLoginMap(map);

    return user;
  }

  void _ensureEpoch(int commitEpoch, [String? ownedToken]) {
    if (SessionStore.instance.epoch == commitEpoch) return;
    if (ownedToken != null &&
        ownedToken.isNotEmpty &&
        SessionStore.instance.accessToken == ownedToken) {
      unawaited(SessionStore.instance.dropToken(ownedToken));
    }
    throw const ApiException(message: '\u767b\u5f55\u5df2\u53d6\u6d88', bizCode: 'LOGIN_SUPERSEDED');
  }

  Future<UserModel> register({
    required String username,
    required String password,
    String? nickname,
  }) async {
    final epoch = SessionStore.instance.bumpEpoch();
    final data = await AuthApiClient.instance.post('/auth/member/register', data: {
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
      final saved = await SessionStore.instance.setToken(token, epoch: epoch);
      if (!saved || SessionStore.instance.epoch != epoch) {
        throw const ApiException(message: '\u767b\u5f55\u5df2\u53d6\u6d88', bizCode: 'LOGIN_SUPERSEDED');
      }
    } else if (SessionStore.instance.epoch != epoch) {
      throw const ApiException(message: '\u767b\u5f55\u5df2\u53d6\u6d88', bizCode: 'LOGIN_SUPERSEDED');
    }
    ClientCertStore.instance.applyLoginMap(map);
    ApiClient.instance.rebindTls();
    try {
      return UserModel.fromLoginPayload(map, fallbackUsername: username.trim());
    } on FormatException {
      if (token != null && token.isNotEmpty) {
        await SessionStore.instance.dropToken(token);
      }
      throw const ApiException(message: '\u6ce8\u518c\u54cd\u5e94\u5f02\u5e38');
    }
  }

  Future<void> changePassword({
    required String oldPassword,
    required String newPassword,
    required String confirmPassword,
  }) async {
    await _client.post('/auth/password/change', data: {
      'oldPassword': oldPassword,
      'newPassword': newPassword,
      'confirmPassword': confirmPassword,
    });
  }

  /// 返回 false：退出请求期间已经开始了新登录，本地会话留给那次登录。
  Future<bool> logout() async {
    final epoch = SessionStore.instance.epoch;
    try {
      if (SessionStore.instance.hasToken) {
        await _client.post('/auth/logout');
      }
    } catch (_) {
      // ignore network errors on logout
    }
    if (SessionStore.instance.epoch != epoch) return false;
    await SessionStore.instance.clear();
    return true;
  }
}
