import 'package:shared_preferences/shared_preferences.dart';

/// In-memory + persisted auth/room session for Dio interceptors.
class SessionStore {
  SessionStore._();
  static final SessionStore instance = SessionStore._();

  static const _kToken = 'flyroom_access_token';
  static const _kRoomId = 'flyroom_room_id';
  static const _kRoomCode = 'flyroom_room_code';
  static const _kRoomName = 'flyroom_room_name';
  static const _kOwnerNickname = 'flyroom_owner_nickname';
  static const _kBetConfirm = 'flyroom_bet_confirm';
  static const _kShowQuick = 'flyroom_show_quick';

  String? accessToken;
  String? roomId;
  String? roomCode;
  String? roomName;
  String? ownerNickname;
  bool betConfirm = false;
  /// 房主「显示快捷」。关则聊天页不显示盘口入口。默认开。
  bool showQuick = true;

  bool get hasToken => accessToken != null && accessToken!.isNotEmpty;

  /// 大厅顶栏：房主昵称 → 房间名。
  String get hallTitle {
    final nick = ownerNickname?.trim() ?? '';
    if (nick.isNotEmpty) return nick;
    return roomName?.trim() ?? '';
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    accessToken = prefs.getString(_kToken);
    roomId = prefs.getString(_kRoomId);
    roomCode = prefs.getString(_kRoomCode);
    roomName = prefs.getString(_kRoomName);
    ownerNickname = prefs.getString(_kOwnerNickname);
    betConfirm = prefs.getBool(_kBetConfirm) ?? false;
    showQuick = prefs.getBool(_kShowQuick) ?? true;
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

  Future<void> setRoom({
    String? roomId,
    String? roomCode,
    String? roomName,
    String? ownerNickname,
    bool? betConfirm,
    bool? showQuick,
  }) async {
    this.roomId = roomId;
    this.roomCode = roomCode;
    if (roomName != null) this.roomName = roomName;
    if (ownerNickname != null) this.ownerNickname = ownerNickname;
    if (betConfirm != null) this.betConfirm = betConfirm;
    if (showQuick != null) this.showQuick = showQuick;
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
    final name = this.roomName?.trim() ?? '';
    if (name.isEmpty) {
      await prefs.remove(_kRoomName);
    } else {
      await prefs.setString(_kRoomName, name);
    }
    final nick = this.ownerNickname?.trim() ?? '';
    if (nick.isEmpty) {
      await prefs.remove(_kOwnerNickname);
    } else {
      await prefs.setString(_kOwnerNickname, nick);
    }
    if (betConfirm != null) {
      await prefs.setBool(_kBetConfirm, betConfirm);
    }
    if (showQuick != null) {
      await prefs.setBool(_kShowQuick, showQuick);
    }
  }

  Future<void> setShowQuick(bool value) async {
    showQuick = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kShowQuick, value);
  }

  Future<void> clear() async {
    accessToken = null;
    roomId = null;
    roomCode = null;
    roomName = null;
    ownerNickname = null;
    betConfirm = false;
    showQuick = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kToken);
    await prefs.remove(_kRoomId);
    await prefs.remove(_kRoomCode);
    await prefs.remove(_kRoomName);
    await prefs.remove(_kOwnerNickname);
    await prefs.remove(_kBetConfirm);
    await prefs.remove(_kShowQuick);
  }
}
