import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../data/models/app_role.dart';
import '../../../data/models/user_model.dart';
import '../../../data/repositories/providers.dart';
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
    await _ref.read(authRepositoryProvider).logout();
    state = const AuthSession();
  }
}

final authSessionProvider =
    StateNotifierProvider<AuthSessionNotifier, AuthSession>((ref) {
  return AuthSessionNotifier(ref);
});
