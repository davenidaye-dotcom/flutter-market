import 'package:shared_preferences/shared_preferences.dart';

/// In-memory + persisted auth/room session for Dio interceptors.
class SessionStore {
  SessionStore._();
  static final SessionStore instance = SessionStore._();

  static const _kToken = 'flyroom_access_token';
  static const _kRoomId = 'flyroom_room_id';
  static const _kRoomCode = 'flyroom_room_code';
  static const _kBetConfirm = 'flyroom_bet_confirm';

  String? accessToken;
  String? roomId;
  String? roomCode;
  bool betConfirm = false;

  bool get hasToken => accessToken != null && accessToken!.isNotEmpty;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    accessToken = prefs.getString(_kToken);
    roomId = prefs.getString(_kRoomId);
    roomCode = prefs.getString(_kRoomCode);
    betConfirm = prefs.getBool(_kBetConfirm) ?? false;
  }

  Future<void> setToken(String? token) async {
    accessToken = token;
    final prefs = await SharedPreferences.getInstance();
    if (token == null || token.isEmpty) {
      await prefs.remove(_kToken);
    } else {
      await prefs.setString(_kToken, token);
    }
  }

  Future<void> setRoom({String? roomId, String? roomCode, bool? betConfirm}) async {
    this.roomId = roomId;
    this.roomCode = roomCode;
    if (betConfirm != null) this.betConfirm = betConfirm;
    final prefs = await SharedPreferences.getInstance();
    if (roomId == null || roomId.isEmpty) {
      await prefs.remove(_kRoomId);
    } else {
      await prefs.setString(_kRoomId, roomId);
    }
    if (roomCode == null || roomCode.isEmpty) {
      await prefs.remove(_kRoomCode);
    } else {
      await prefs.setString(_kRoomCode, roomCode);
    }
    if (betConfirm != null) {
      await prefs.setBool(_kBetConfirm, betConfirm);
    }
  }

  Future<void> clear() async {
    accessToken = null;
    roomId = null;
    roomCode = null;
    betConfirm = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kToken);
    await prefs.remove(_kRoomId);
    await prefs.remove(_kRoomCode);
    await prefs.remove(_kBetConfirm);
  }
}
