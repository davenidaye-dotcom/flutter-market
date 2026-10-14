import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/audio/bgm_prompt.dart';
import '../../../core/network/api_exception.dart';
import '../../../data/models/app_role.dart';
import '../../../data/models/user_model.dart';
import '../../../data/repositories/providers.dart';
import '../../room/cs_unread.dart';
import '../device_login_store.dart';
import '../../../core/network/session_store.dart';

class AuthSession {
  const AuthSession({this.user});

  final UserModel? user;

  bool get isLoggedIn => user != null;
  AppRole? get role => user?.role;
  bool get isHostSide => user?.isHostSide ?? false;
  bool get isAgentSide => user?.isAgentSide ?? false;
  bool get isManagementSide => isHostSide || isAgentSide;
  bool get canPlaceBet => user?.canPlaceBet ?? false;
}

class AuthSessionNotifier extends StateNotifier<AuthSession> {
  AuthSessionNotifier(this._ref) : super(const AuthSession());

  final Ref _ref;

  Future<UserModel> login({
    required String username,
    required String password,
    required String captchaToken,
    required AppRole expectedRole,
  }) async {
    final user = await _ref.read(authRepositoryProvider).login(
          username: username,
          password: password,
          captchaToken: captchaToken,
          expectedRole: expectedRole,
        );
    if (expectedRole == AppRole.player) {
      if (user.role != AppRole.player) {
        await SessionStore.instance.clear();
        throw Exception('\u8be5\u8d26\u53f7\u4e0d\u662f\u73a9\u5bb6\u8d26\u53f7');
      }
    } else {
      if (!user.role.isManagementLoginSide) {
        await SessionStore.instance.clear();
        throw Exception('\u8be5\u8d26\u53f7\u4e0d\u662f\u623f\u4e3b/\u4ee3\u7406\u8d26\u53f7');
      }
    }
    state = AuthSession(user: user);
    await BgmPrompt.resetForLogin(
      host: user.isHostSide,
      player: user.role == AppRole.player,
    );
    return user;
  }

  /// 启动时用保存的设备令牌静默登录。没有令牌 / 失败返回 null（走密码登录）。
  /// 令牌被服务端判无效（DEVICE_TOKEN_INVALID）时清掉本地令牌。
  Future<UserModel?> tryDeviceLogin() async {
    final saved = await DeviceLoginStore.loadSaved();
    if (saved == null) return null;
    try {
      final user = await _ref.read(authRepositoryProvider).deviceLogin(
            username: saved.username,
            deviceToken: saved.token,
          );
      if (user.role != AppRole.player) {
        await SessionStore.instance.clear();
        return null;
      }
      state = AuthSession(user: user);
      await BgmPrompt.resetForLogin(host: false, player: true);
      return user;
    } catch (e) {
      if (e is ApiException &&
          (e.bizCode == 'DEVICE_TOKEN_INVALID' ||
              e.message.contains('DEVICE_TOKEN_INVALID'))) {
        await DeviceLoginStore.clear(saved.username);
      }
      return null;
    }
  }

  void bindRoomCode(String roomCode) {
    final user = state.user;
    if (user == null) return;
    state = AuthSession(user: user.copyWith(roomId: roomCode));
  }

  void updateNickname(String nickname) {
    final user = state.user;
    if (user == null) return;
    state = AuthSession(user: user.copyWith(nickname: nickname));
  }

  void updateAvatar(String avatarUrl) {
    final user = state.user;
    if (user == null) return;
    state = AuthSession(user: user.copyWith(avatarUrl: avatarUrl));
  }

  Future<void> logout() async {
    final username = state.user?.username;
    await _ref.read(authRepositoryProvider).logout();
    if (username != null) await DeviceLoginStore.clear(username);
    _ref.read(csUnreadCountProvider.notifier).clear();
    state = const AuthSession();
  }

  /// 服务端已注销时只清本地会话，不再请求退出接口。
  void dropLocal() {
    // 被踢/会话失效：不能让登录页立刻拿旧设备令牌又登回去
    final username = state.user?.username;
    if (username != null) unawaited(DeviceLoginStore.clear(username));
    _ref.read(csUnreadCountProvider.notifier).clear();
    state = const AuthSession();
  }
}

final authSessionProvider =
    StateNotifierProvider<AuthSessionNotifier, AuthSession>((ref) {
  return AuthSessionNotifier(ref);
});
