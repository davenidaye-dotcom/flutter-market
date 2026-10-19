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
    // 先占代际，上一次还没写完的密码登录不能再写 token。
    final epoch = SessionStore.instance.bumpEpoch();
    return _loginWithEpoch(
      epoch: epoch,
      username: username,
      password: password,
      captchaToken: captchaToken,
      expectedRole: expectedRole,
    );
  }

  Future<UserModel> _loginWithEpoch({
    required int epoch,
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
          commitEpoch: epoch,
        );
    if (SessionStore.instance.epoch != epoch) {
      throw const ApiException(message: '\u767b\u5f55\u5df2\u53d6\u6d88', bizCode: 'LOGIN_SUPERSEDED');
    }
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
    // 提示音同步失败不能挡跳转，更不能在读用户之前把会话踢掉。
    unawaited(BgmPrompt.resetForLogin(
      host: user.isHostSide,
      player: user.role == AppRole.player,
    ));
    return user;
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
    final cleared = await _ref.read(authRepositoryProvider).logout();
    if (!cleared) return;
    if (username != null) await DeviceLoginStore.clear(username);
    _ref.read(csUnreadCountProvider.notifier).clear();
    state = const AuthSession();
  }

  /// 还停在登录页时切到房主/代理：丢掉已经写上的玩家会话，但不删设备快登令牌。
  void abandonLocal() {
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
